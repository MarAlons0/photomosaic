/*
 * Colour features — a port of js/core.js.
 *
 * Every image is described by 12 numbers: the mean CIELAB colour of its four
 * quadrants (2x2 grid x L,a,b), averaged in linear light.
 */
import CoreGraphics
import Foundation

enum Features {
    static let count = 12

    // sRGB byte -> linear light.
    private static let lin: [Float] = (0..<256).map { i in
        let c = Float(i) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    @inline(__always) private static func f(_ t: Float) -> Float {
        t > 0.008856 ? cbrtf(t) : 7.787 * t + 16 / 116
    }

    @inline(__always) private static func linToLab(_ r: Float, _ g: Float, _ b: Float,
                                                   _ out: UnsafeMutablePointer<Float>) {
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        let fx = f(x), fy = f(y), fz = f(z)
        out[0] = 116 * fy - 16
        out[1] = 500 * (fx - fy)
        out[2] = 200 * (fy - fz)
    }

    /// Centred "aspect fill" crop of a w x h image to `aspect` (width / height), in pixels.
    static func cover(width w: Int, height h: Int, aspect: CGFloat) -> CGRect {
        let W = CGFloat(w), H = CGFloat(h)
        if W / H > aspect {
            let sw = H * aspect
            return CGRect(x: (W - sw) / 2, y: 0, width: sw, height: H).integral
        }
        let sh = W / aspect
        return CGRect(x: 0, y: (H - sh) / 2, width: W, height: sh).integral
    }

    /// Features of an n x n grid laid over `crop` of `image`: n*n*12 floats, row-major
    /// from the top. Each quadrant is averaged over px*px samples; n = 1 describes a tile.
    static func grid(_ image: CGImage, crop: CGRect, n: Int, px: Int) -> [Float] {
        let size = n * 2 * px
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let source = image.cropping(to: crop) ?? image
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            ctx.interpolationQuality = .high
            // Bitmap memory starts at the top row, so the buffer reads top-down.
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
        }

        var out = [Float](repeating: 0, count: n * n * count)
        let inv = 1 / Float(px * px)
        pixels.withUnsafeBufferPointer { d in
            out.withUnsafeMutableBufferPointer { o in
                for cy in 0..<n {
                    for cx in 0..<n {
                        for q in 0..<4 {
                            let x0 = (cx * 2 + (q & 1)) * px
                            let y0 = (cy * 2 + (q >> 1)) * px
                            var r: Float = 0, g: Float = 0, b: Float = 0
                            for y in y0..<(y0 + px) {
                                var i = (y * size + x0) * 4
                                for _ in 0..<px {
                                    r += lin[Int(d[i])]; g += lin[Int(d[i + 1])]; b += lin[Int(d[i + 2])]
                                    i += 4
                                }
                            }
                            linToLab(r * inv, g * inv, b * inv,
                                     o.baseAddress! + (cy * n + cx) * count + q * 3)
                        }
                    }
                }
            }
        }
        return out
    }
}
