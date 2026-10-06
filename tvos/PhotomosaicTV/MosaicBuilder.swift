/*
 * Builds one still mosaic: analyse the target photo, match tiles, and render
 * the result as a single screen-sized image with the target faintly blended
 * over it (the classic photomosaic "colour blend").
 */
import CoreGraphics
import Foundation

struct Mosaic {
    let target: Int
    let n: Int
    let assign: [Int]       // n*n photo indices, row-major from the top
    let image: CGImage
    let buildSeconds: Double
}

enum MosaicBuilder {
    static let poolSize = 1500

    static func make(target: Int, targetImage: CGImage, n: Int, micros: [CGImage?], features: [Float],
                     usable: [Int], aspect: CGFloat, size: CGSize, tint: CGFloat) -> Mosaic? {
        let start = Date()
        let crop = Features.cover(width: targetImage.width, height: targetImage.height, aspect: aspect)
        let cells = Features.grid(targetImage, crop: crop, n: n, px: 2)

        // Tiles come from a random sample of the library (bounded match cost).
        var pool = usable.filter { $0 != target }
        if pool.count > poolSize { pool.shuffle(); pool = Array(pool.prefix(poolSize)) }
        guard !pool.isEmpty else { return nil }
        let assign = Matcher.build(cells: cells, n: n, pool: pool, features: features,
                                   spacing: 3, penalty: 60)

        let W = Int(size.width), H = Int(size.height)
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Tile edges snapped to whole pixels so neighbours meet exactly.
        let xs = (0...n).map { Int((Double($0) * Double(W) / Double(n)).rounded()) }
        let ys = (0...n).map { Int((Double($0) * Double(H) / Double(n)).rounded()) }
        for r in 0..<n {
            for c in 0..<n {
                guard let micro = micros[assign[r * n + c]] else { continue }
                let mc = Features.cover(width: micro.width, height: micro.height, aspect: aspect)
                guard let tile = micro.cropping(to: mc) else { continue }
                // Core Graphics' origin is bottom-left; rows count from the top.
                ctx.draw(tile, in: CGRect(x: xs[c], y: H - ys[r + 1],
                                          width: xs[c + 1] - xs[c], height: ys[r + 1] - ys[r]))
            }
        }

        if tint > 0, let whole = targetImage.cropping(to: crop) {
            ctx.setAlpha(tint)
            ctx.draw(whole, in: CGRect(x: 0, y: 0, width: W, height: H))
        }
        guard let image = ctx.makeImage() else { return nil }
        return Mosaic(target: target, n: n, assign: assign, image: image,
                      buildSeconds: Date().timeIntervalSince(start))
    }
}
