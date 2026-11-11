/*
 * GPU textures: the micro atlas, single-photo textures, and an LRU cache of
 * on-demand photo versions (the Metal counterpart of the web player's level cache).
 */
import CoreGraphics
import Metal
import UIKit

enum TextureFactory {
    /// RGBA texture (with mipmaps, for smooth minification) holding `image`. Thread-safe.
    static func make(_ image: CGImage, device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h,
                                                            mipmapped: true)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
        generateMipmaps(tex, queue: queue)
        return tex
    }

    static func generateMipmaps(_ tex: MTLTexture, queue: MTLCommandQueue, wait: Bool = true) {
        guard tex.mipmapLevelCount > 1, let cb = queue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return }
        blit.generateMipmaps(for: tex)
        blit.endEncoding()
        cb.commit()
        if wait { cb.waitUntilCompleted() }
    }
}

/// Every photo's micro, cropped to 16:9 at its crop position, in fixed 96x54 slots of a
/// texture array.
struct Atlas {
    static let side = 4096
    static let slotW = 96, slotH = 54
    static let cols = side / slotW, rows = side / slotH
    static let perPage = cols * rows

    let texture: MTLTexture

    static func build(micros: [CGImage?], positions: [CGFloat], aspect: CGFloat,
                      device: MTLDevice, queue: MTLCommandQueue) -> Atlas? {
        let pages = max(1, (micros.count + perPage - 1) / perPage)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side, height: side,
                                                            mipmapped: true)
        desc.textureType = .type2DArray
        desc.arrayLength = pages
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for page in 0..<pages {
            pixels.withUnsafeMutableBytes { raw in
                guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
                ctx.setFillColor(gray: 0, alpha: 1)
                ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
                ctx.interpolationQuality = .high
                for slot in 0..<perPage {
                    let i = page * perPage + slot
                    guard i < micros.count, let micro = micros[i] else { continue }
                    let crop = Features.cover(width: micro.width, height: micro.height, aspect: aspect,
                                              position: positions[i])
                    guard let tile = micro.cropping(to: crop) else { continue }
                    let col = slot % cols, row = slot / cols
                    // Core Graphics draws bottom-up; memory (and the texture) is top-down.
                    ctx.draw(tile, in: CGRect(x: col * slotW, y: side - (row + 1) * slotH,
                                              width: slotW, height: slotH))
                }
            }
            tex.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, slice: page,
                        withBytes: pixels, bytesPerRow: side * 4, bytesPerImage: side * side * 4)
        }
        TextureFactory.generateMipmaps(tex, queue: queue)
        return Atlas(texture: tex)
    }

    /// Redraw photos' slots at new crop positions (after Framing found their subjects):
    /// (photo, micro, position) each, with one mipmap refresh for the batch.
    func update(_ items: [(Int, CGImage, CGFloat)], aspect: CGFloat, queue: MTLCommandQueue) {
        guard !items.isEmpty else { return }
        let w = Self.slotW, h = Self.slotH
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for (i, micro, position) in items {
            let crop = Features.cover(width: micro.width, height: micro.height, aspect: aspect, position: position)
            guard let tile = micro.cropping(to: crop) else { continue }
            let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
                ctx.interpolationQuality = .high
                ctx.draw(tile, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { continue }
            let page = i / Self.perPage, s = i % Self.perPage
            texture.replace(region: MTLRegionMake2D((s % Self.cols) * w, (s / Self.cols) * h, w, h),
                            mipmapLevel: 0, slice: page, withBytes: pixels,
                            bytesPerRow: w * 4, bytesPerImage: w * h * 4)
        }
        TextureFactory.generateMipmaps(texture, queue: queue, wait: false)
    }

    /// Atlas page and UV rectangle for photo i (inset half a texel against bleeding).
    static func slot(_ i: Int) -> (page: Float, uv: SIMD4<Float>) {
        let page = i / perPage, s = i % perPage
        let x = Float((s % cols) * slotW), y = Float((s / cols) * slotH), d = Float(side)
        return (Float(page), SIMD4((x + 0.5) / d, (y + 0.5) / d,
                                   (x + Float(slotW) - 0.5) / d, (y + Float(slotH) - 0.5) / d))
    }
}

/// One photo version on the GPU, with the UV rectangle of its 16:9 cover crop.
struct PhotoTexture {
    let texture: MTLTexture
    let uv: SIMD4<Float>

    init(_ texture: MTLTexture, aspect: CGFloat, position: CGFloat) {
        self.texture = texture
        let c = Features.cover(width: texture.width, height: texture.height, aspect: aspect, position: position)
        let w = Float(texture.width), h = Float(texture.height)
        uv = SIMD4(Float(c.minX) / w, Float(c.minY) / h, Float(c.maxX) / w, Float(c.maxY) / h)
    }
}

/// Lets at most `limit` tasks through at a time; the rest wait their turn (first come,
/// first served). Loading a photo briefly holds it three times over — PhotoKit's decoded
/// image, the pixel copy and the texture, ~150 MB for a full-size one — so loads are
/// spaced out instead of all starting together when a cycle begins.
@MainActor
final class Gate {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ limit: Int) { self.limit = limit }

    func enter() async {
        if running < limit { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }   // the slot is handed over
    }

    func leave() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }

    var busy: Int { running + waiting.count }
}

/// LRU caches of on-demand photo versions, each kept within a memory budget (photos are
/// loaded uncropped, so their size varies with shape). Pinned photos are never evicted.
@MainActor
final class TextureCache {
    enum Kind { case mid, hires }

    static let sizes: [Kind: CGSize] = [.mid: CGSize(width: 480, height: 270),
                                        .hires: CGSize(width: 3840, height: 2160)]
    /// Bytes per cache. The app may use about 2 GB on an Apple TV before the system ends it;
    /// these plus the atlas (~170 MB for 6,000 photos) stay well under that. A screen holds at
    /// most ~350 tiles large enough for the 480 px version (~1 MB each with mipmaps); a full
    /// size photo takes 45–60 MB, and up to 11 are pinned around the target tile.
    static let budgets: [Kind: Int] = [.mid: 300 << 20, .hires: 500 << 20]

    private struct Entry {
        var texture: MTLTexture?
        var lastUse: Int
        var bytes: Int { texture.map { $0.width * $0.height * 4 * 4 / 3 } ?? 0 }   // with mipmaps
    }

    private var entries: [Kind: [Int: Entry]] = [.mid: [:], .hires: [:]]
    private(set) var used: [Kind: Int] = [.mid: 0, .hires: 0]
    /// Loads in progress at once, per size (see Gate).
    let gates: [Kind: Gate] = [.mid: Gate(4), .hires: Gate(2)]

    /// Photos held and loads in progress, per size (for the memory log).
    func census(_ kind: Kind) -> (held: Int, loading: Int) {
        (entries[kind]!.values.filter { $0.texture != nil }.count, gates[kind]!.busy)
    }
    var pinned: Set<Int> = []
    private var clock = 0

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: PhotoLibrary
    let aspect: CGFloat

    init(device: MTLDevice, queue: MTLCommandQueue, library: PhotoLibrary, aspect: CGFloat) {
        self.device = device
        self.queue = queue
        self.library = library
        self.aspect = aspect
    }

    func get(_ kind: Kind, _ i: Int) -> PhotoTexture? {
        guard var e = entries[kind]?[i] else { return nil }
        clock += 1
        e.lastUse = clock
        entries[kind]![i] = e
        // The crop is applied here, so a photo framed after loading is drawn at its new position.
        return e.texture.map { PhotoTexture($0, aspect: aspect, position: library.position(i)) }
    }

    /// Start loading photo i at this size unless it's loaded or loading.
    func request(_ kind: Kind, _ i: Int) {
        clock += 1
        if var e = entries[kind]?[i] {
            e.lastUse = clock
            entries[kind]![i] = e
            return
        }
        entries[kind]![i] = Entry(texture: nil, lastUse: clock)
        let size = Self.sizes[kind]!
        let gate = gates[kind]!
        Task {
            await gate.enter()
            defer { gate.leave() }
            // Dropped while waiting (zooming moves on quickly): no need to load it any more.
            guard entries[kind]?[i] != nil,
                  let image = await library.large(i, size: size) else { return }
            await self.store(kind, i, image: image)
        }
    }

    /// Insert a ready image (also used for photos fetched for analysis).
    func store(_ kind: Kind, _ i: Int, image: CGImage) async {
        let device = device, queue = queue
        let tex = await Task.detached(priority: .userInitiated) {
            TextureFactory.make(image, device: device, queue: queue)
        }.value
        guard let tex else { return }
        clock += 1
        let entry = Entry(texture: tex, lastUse: clock)
        used[kind]! += entry.bytes - (entries[kind]![i]?.bytes ?? 0)
        entries[kind]![i] = entry
        evict(kind)
    }

    /// Drop the least recently used unpinned photos until the cache is within its budget.
    /// (Requests still loading take no memory and are kept, unless far too many pile up.)
    private func evict(_ kind: Kind) {
        let budget = Self.budgets[kind]!
        while used[kind]! > budget || entries[kind]!.count > 2000 {
            guard let (victim, e) = entries[kind]!.filter({ !pinned.contains($0.key) })
                .min(by: { $0.value.lastUse < $1.value.lastUse }) else { return }
            used[kind]! -= e.bytes
            entries[kind]![victim] = nil
        }
    }
}
