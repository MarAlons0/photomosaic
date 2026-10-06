/*
 * The zoom player — a port of js/player.js onto Metal.
 *
 * Camera: a pure zoom about a fixed point. World space is the screen (W x H px);
 * the mosaic is an N x N grid of screen-shaped cells, so the target cell at
 * top-left t fills the screen at scale N. With f = N*t / (N - 1),
 * screen = f + s*(world - f) for s = N^p, p in [0, 1] (log-space, constant feel).
 * Zoom-out plays the same path backwards. Each cycle ends on exactly the frame
 * the next one starts with, and the next cycle is planned while this one plays.
 */
import MetalKit
import SwiftUI

struct TileInstance {
    var rect: SIMD4<Float>
    var uv: SIMD4<Float>
    var page: Float
    var alpha: Float
    var pad = SIMD2<Float>(0, 0)
}

@MainActor
final class Player: NSObject, ObservableObject {
    enum DirectionSetting { case zoomIn, zoomOut, alternate }

    struct Settings {
        var direction = DirectionSetting.alternate
        var grid = 120
        var duration = 22.0
        var hold = 3.0
        var tint: Float = 0.2
    }

    @Published private(set) var status = "Preparing tiles…"
    @Published private(set) var running = false
    var settings = Settings()
    var paused = false

    let library: PhotoLibrary
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private var atlasPipeline: MTLRenderPipelineState!
    private var singlePipeline: MTLRenderPipelineState!
    private let sampler: MTLSamplerState
    private var atlas: Atlas?
    private var cache: TextureCache?

    private var current: CyclePlan?
    private var pending: CyclePlan?
    private var planning = false
    private var elapsed = 0.0
    private var lastTime: CFTimeInterval = 0
    private var recent: [Int] = []

    private static let maxInstances = 200 * 200
    private var buffers: [MTLBuffer] = []
    private var bufferIndex = 0
    private let inFlight = DispatchSemaphore(value: 3)

    private let aspect: CGFloat = 16.0 / 9.0

    init(library: PhotoLibrary) {
        self.library = library
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)!
        super.init()
        for _ in 0..<3 {
            buffers.append(device.makeBuffer(length: Self.maxInstances * MemoryLayout<TileInstance>.stride,
                                             options: .storageModeShared)!)
        }
    }

    func configure(_ view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = self
        let lib = try! device.makeLibrary(source: Shaders.source, options: nil)
        func pipeline(_ fragment: String) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "tileVertex")
            d.fragmentFunction = lib.makeFunction(name: fragment)
            let c = d.colorAttachments[0]!
            c.pixelFormat = view.colorPixelFormat
            c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .sourceAlpha
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        atlasPipeline = pipeline("atlasFragment")
        singlePipeline = pipeline("singleFragment")
    }

    /* ---------- startup and cycles ---------- */

    func start() async {
        guard atlas == nil else { return }
        let micros = library.micros, device = device, queue = queue, aspect = aspect
        atlas = await Task.detached(priority: .userInitiated) {
            Atlas.build(micros: micros, aspect: aspect, device: device, queue: queue)
        }.value
        cache = TextureCache(device: device, queue: queue, library: library, aspect: aspect)

        status = "Building first mosaic…"
        let usable = library.usable
        guard let first = usable.randomElement() else { status = "No photos"; return }
        let dir: Direction = settings.direction == .zoomOut ? .zoomOut : .zoomIn
        let shown = dir == .zoomOut ? pickUpcoming(excluding: first) : nil
        let plan = await makePlan(dir: dir, mosaicPhoto: first, shown: shown)
        if let shown { await fetchHires(shown) }
        install(plan)
        status = ""
        running = true
    }

    /// Fetch photo i at full size (kept in the cache for drawing) and return it for analysis.
    @discardableResult
    private func fetchHires(_ i: Int) async -> CGImage? {
        guard let image = await library.large(i, size: TextureCache.sizes[.hires]!) else { return nil }
        await cache?.store(.hires, i, image: image)
        return image
    }

    private func makePlan(dir: Direction, mosaicPhoto: Int, shown: Int?) async -> CyclePlan {
        cache?.pinned.insert(mosaicPhoto)
        let image = await fetchHires(mosaicPhoto) ?? library.micros[mosaicPhoto]!
        let n = settings.grid, features = library.features, usable = library.usable
        let recentSet = Set(recent), aspect = aspect
        return await Task.detached(priority: .userInitiated) {
            Planner.plan(dir: dir, mosaicPhoto: mosaicPhoto, image: image, shown: shown, n: n,
                         features: features, usable: usable, recent: recentSet, aspect: aspect)
        }.value
    }

    private func install(_ plan: CyclePlan) {
        current = plan
        pending = nil
        elapsed = 0
        recent.append(plan.shown)
        if recent.count > 12 { recent.removeFirst(recent.count - 12) }

        // Full size for both photos and the tiles around the target cell.
        let n = plan.n, col = plan.cell % n, row = plan.cell / n
        var pins: Set<Int> = [plan.mosaicPhoto, plan.shown, plan.end]
        for r in max(0, row - 1)...min(n - 1, row + 1) {
            for c in max(0, col - 1)...min(n - 1, col + 1) { pins.insert(plan.assign[r * n + c]) }
        }
        cache?.pinned = pins
        for i in pins { cache?.request(.hires, i) }
        if plan.dir == .zoomOut { prefetchMid(plan) }
        planNext()
    }

    private func planNext() {
        guard let cur = current, !planning else { return }
        planning = true
        let dir: Direction
        switch settings.direction {
        case .zoomIn: dir = .zoomIn
        case .zoomOut: dir = .zoomOut
        case .alternate: dir = cur.dir == .zoomIn ? .zoomOut : .zoomIn
        }
        let shown = cur.end
        let mosaicPhoto = dir == .zoomIn ? shown : pickUpcoming(excluding: shown)
        Task {
            let plan = await makePlan(dir: dir, mosaicPhoto: mosaicPhoto, shown: dir == .zoomOut ? shown : nil)
            self.pending = plan
            self.planning = false
        }
    }

    private func pickUpcoming(excluding: Int) -> Int {
        let usable = library.usable
        for _ in 0..<50 {
            let i = usable.randomElement()!
            if i != excluding && !recent.contains(i) { return i }
        }
        return usable.first { $0 != excluding } ?? excluding
    }

    /// Zooming out, tiles first appear large: fetch their 480 px versions up front.
    private func prefetchMid(_ plan: CyclePlan) {
        let (W, H) = (Double(screen.width), Double(screen.height))
        let n = plan.n, cw = W / Double(n), ch = H / Double(n)
        let s = min(Double(n), max(1, midAt / cw))
        let (fx, fy) = fixedPoint(plan)
        let c0 = max(0, Int((fx - fx / s) / cw)), c1 = min(n - 1, Int((fx + (W - fx) / s) / cw))
        let r0 = max(0, Int((fy - fy / s) / ch)), r1 = min(n - 1, Int((fy + (H - fy) / s) / ch))
        for r in r0...r1 { for c in c0...c1 { cache?.request(.mid, plan.assign[r * n + c]) } }
    }

    func skip() {
        if let next = pending { install(next) }
    }

    /* ---------- camera ---------- */

    private var screen = CGSize(width: 3840, height: 2160)
    private var midAt: Double { max(120, Double(screen.width) / 24) }   // tile px worth a 480 px texture
    private var atlasMax: Double { Double(Atlas.slotW) * 1.3 }

    private func fixedPoint(_ plan: CyclePlan) -> (Double, Double) {
        let n = Double(plan.n)
        let tx = Double(plan.cell % plan.n) * Double(screen.width) / n
        let ty = Double(plan.cell / plan.n) * Double(screen.height) / n
        return (n * tx / (n - 1), n * ty / (n - 1))
    }

    /// Photo over its own mosaic: dissolves as tiles grow to ~40 pt, settles at the
    /// tint, and fades out as the target tile takes over the screen.
    private func overlayAlpha(p: Double, tilePt: Double, tilePt0: Double) -> Float {
        func smooth(_ t: Double) -> Double { let c = min(1, max(0, t)); return c * c * (3 - 2 * c) }
        let a0 = log(max(tilePt0, 2)), a1 = log(max(tilePt0 * 3, 40))
        let reveal = smooth((log(tilePt) - a0) / (a1 - a0))
        let handoff = 1 - smooth((p - 0.72) / 0.22)
        return Float((1 + (Double(settings.tint) - 1) * reveal) * handoff)
    }

    /* ---------- drawing ---------- */

    fileprivate func render(_ view: MTKView) {
        screen = view.drawableSize
        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? 0 : min(0.1, now - lastTime)
        lastTime = now

        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        inFlight.wait()
        let cb = queue.makeCommandBuffer()!
        cb.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        let enc = cb.makeRenderCommandEncoder(descriptor: pass)!

        if var plan = current, let atlas, let cache {
            if !paused { elapsed += dt }
            var u = elapsed > settings.hold ? (elapsed - settings.hold) / settings.duration : 0
            if u >= 1, let next = pending {   // otherwise hold on the end frame until it's ready
                install(next)
                plan = next
                u = 0
            }
            let e = (1 - cos(Double.pi * min(1, u))) / 2
            draw(plan, p: plan.dir == .zoomOut ? 1 - e : e, enc: enc, atlas: atlas, cache: cache)
        }

        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    private func draw(_ plan: CyclePlan, p: Double, enc: MTLRenderCommandEncoder, atlas: Atlas, cache: TextureCache) {
        let W = Double(screen.width), H = Double(screen.height), n = plan.n
        let s = pow(Double(n), p)
        let (fx, fy) = fixedPoint(plan)
        let X = { (wx: Double) in fx + s * (wx - fx) }
        let Y = { (wy: Double) in fy + s * (wy - fy) }
        let cw = W / Double(n), ch = H / Double(n)
        let tile = cw * s
        let points = W / 1920
        let alpha = overlayAlpha(p: p, tilePt: tile / points, tilePt0: cw / points)

        // World rectangle on screen, and its part inside the mosaic.
        let wx0 = fx - fx / s, wx1 = fx + (W - fx) / s
        let wy0 = fy - fy / s, wy1 = fy + (H - fy) / s
        let vx0 = max(0, wx0), vx1 = min(W, wx1), vy0 = max(0, wy0), vy1 = min(H, wy1)

        var viewport = SIMD2<Float>(Float(W), Float(H))
        enc.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        enc.setFragmentSamplerState(sampler, index: 0)

        if alpha < 1 {
            let c0 = max(0, Int(floor(wx0 / cw))), c1 = min(n - 1, Int(ceil(wx1 / cw)) - 1)
            let r0 = max(0, Int(floor(wy0 / ch))), r1 = min(n - 1, Int(ceil(wy1 / ch)) - 1)
            let buffer = buffers[bufferIndex]
            bufferIndex = (bufferIndex + 1) % buffers.count
            let instances = buffer.contents().bindMemory(to: TileInstance.self, capacity: Self.maxInstances)
            var count = 0
            var singles: [TileInstance] = []
            var singleTextures: [MTLTexture] = []
            let wantMid = tile > midAt

            if c0 <= c1 && r0 <= r1 {
                for r in r0...r1 {
                    // Edges snapped to whole pixels so neighbours meet exactly.
                    let y0 = Float(Y(Double(r) * ch).rounded()), y1 = Float(Y(Double(r + 1) * ch).rounded())
                    for c in c0...c1 {
                        let x0 = Float(X(Double(c) * cw).rounded()), x1 = Float(X(Double(c + 1) * cw).rounded())
                        let photo = plan.assign[r * n + c]
                        let rect = SIMD4(x0, y0, x1, y1)
                        if wantMid { cache.request(.mid, photo) }
                        if tile > atlasMax {
                            let big = tile > 400 ? cache.get(.hires, photo) : nil
                            if let t = big ?? cache.get(.mid, photo) {
                                singles.append(TileInstance(rect: rect, uv: t.uv, page: 0, alpha: 1))
                                singleTextures.append(t.texture)
                                continue
                            }
                        }
                        let slot = Atlas.slot(photo)
                        instances[count] = TileInstance(rect: rect, uv: slot.uv, page: slot.page, alpha: 1)
                        count += 1
                    }
                }
            }
            if count > 0 {
                enc.setRenderPipelineState(atlasPipeline)
                enc.setVertexBuffer(buffer, offset: 0, index: 0)
                enc.setFragmentTexture(atlas.texture, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
            }
            if !singles.isEmpty {
                enc.setRenderPipelineState(singlePipeline)
                for (k, var inst) in singles.enumerated() {
                    enc.setVertexBytes(&inst, length: MemoryLayout<TileInstance>.stride, index: 0)
                    enc.setFragmentTexture(singleTextures[k], index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
        }

        if alpha > 0 {
            // The mosaic's own photo over it: fully at first, then as a faint colour blend.
            let a = plan.mosaicPhoto
            let rect = SIMD4(Float(X(vx0)), Float(Y(vy0)), Float(X(vx1)), Float(Y(vy1)))
            func sub(_ uv: SIMD4<Float>) -> SIMD4<Float> {
                let du = uv.z - uv.x, dv = uv.w - uv.y
                return SIMD4(uv.x + Float(vx0 / W) * du, uv.y + Float(vy0 / H) * dv,
                             uv.x + Float(vx1 / W) * du, uv.y + Float(vy1 / H) * dv)
            }
            if let t = cache.get(.hires, a) ?? cache.get(.mid, a) {
                var inst = TileInstance(rect: rect, uv: sub(t.uv), page: 0, alpha: alpha)
                enc.setRenderPipelineState(singlePipeline)
                enc.setVertexBytes(&inst, length: MemoryLayout<TileInstance>.stride, index: 0)
                enc.setFragmentTexture(t.texture, index: 0)
            } else {
                let slot = Atlas.slot(a)
                var inst = TileInstance(rect: rect, uv: sub(slot.uv), page: slot.page, alpha: alpha)
                enc.setRenderPipelineState(atlasPipeline)
                enc.setVertexBytes(&inst, length: MemoryLayout<TileInstance>.stride, index: 0)
                enc.setFragmentTexture(atlas.texture, index: 0)
            }
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
}

extension Player: MTKViewDelegate {
    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { self.render(view) }
    }
}

/// The Metal view hosting the player.
struct PlayerView: UIViewRepresentable {
    let player: Player

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        player.configure(view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}
}
