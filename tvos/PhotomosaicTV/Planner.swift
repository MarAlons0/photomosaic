/*
 * Cycle planning — the mosaic and target cell for one zoom, built off the main
 * thread while the previous zoom plays.
 *
 *   in:  photo `mosaicPhoto` fills the screen, dissolves into its mosaic, and the
 *        camera dives into the tile at `cell` (photo `end`).
 *   out: photo `shown` fills the screen as the tile at `cell` of `mosaicPhoto`'s
 *        mosaic; the camera pulls back until the mosaic resolves into `mosaicPhoto`.
 */
import CoreGraphics
import Foundation

enum Direction { case zoomIn, zoomOut }

struct CyclePlan {
    let dir: Direction
    let mosaicPhoto: Int
    let n: Int
    let assign: [Int]
    let cell: Int

    var tilePhoto: Int { assign[cell] }
    /// Photo filling the screen when the cycle starts / ends.
    var shown: Int { dir == .zoomIn ? mosaicPhoto : tilePhoto }
    var end: Int { dir == .zoomIn ? tilePhoto : mosaicPhoto }
}

enum Planner {
    static let poolSize = 1500

    /// - shown: for zoom-out, the photo to place as the starting tile.
    static func plan(dir: Direction, mosaicPhoto: Int, image: CGImage, shown: Int?, n: Int,
                     features: [Float], usable: [Int], recent: Set<Int>, aspect: CGFloat) -> CyclePlan {
        let crop = Features.cover(width: image.width, height: image.height, aspect: aspect)
        let cells = Features.grid(image, crop: crop, n: n, px: 2)

        // Tiles come from a random sample of the library (bounded match cost).
        var pool = usable.filter { $0 != mosaicPhoto }
        if pool.count > poolSize { pool.shuffle(); pool = Array(pool.prefix(poolSize)) }
        var assign = Matcher.build(cells: cells, n: n, pool: pool, features: features,
                                   spacing: 3, penalty: 60)

        let lo = n / 5, hi = n - n / 5
        var central: [Int] = []
        for r in lo..<hi { for c in lo..<hi { central.append(r * n + c) } }

        let cell: Int
        if dir == .zoomOut, let shown {
            // The cell whose colours best suit the incoming photo (random among the best few).
            let F = Features.count
            let scored = central.map { i -> (Float, Int) in
                var d: Float = 0
                for j in 0..<F { let e = cells[i * F + j] - features[shown * F + j]; d += e * e }
                return (d, i)
            }.sorted { $0.0 < $1.0 }
            cell = scored[Int.random(in: 0..<min(5, scored.count))].1
            assign[cell] = shown
        } else {
            // A central tile whose photo hasn't been shown lately.
            let fresh = central.filter { !recent.contains(assign[$0]) && assign[$0] != mosaicPhoto }
            cell = (fresh.isEmpty ? central : fresh).randomElement()!
        }
        return CyclePlan(dir: dir, mosaicPhoto: mosaicPhoto, n: n, assign: assign, cell: cell)
    }
}
