/*
 * Tile matching — a port of PM.buildMosaic in js/core.js.
 *
 * Nearest-neighbour search over 12-float features, filling cells in random
 * order, with two anti-repetition rules: a photo can't reappear within
 * `spacing` cells of itself, and every reuse adds `penalty` to its cost.
 */
import Foundation

enum Matcher {
    /// Assign a photo to every cell of an n x n mosaic.
    /// - cells: n*n*12 target features
    /// - pool: photo indices allowed as tiles
    /// - features: all photos' features, 12 floats per photo index
    /// Returns n*n photo indices, row-major from the top.
    static func build(cells: [Float], n: Int, pool: [Int], features: [Float],
                      spacing: Int, penalty: Float) -> [Int] {
        let total = n * n, P = pool.count, F = Features.count
        var poolFeatures = [Float](repeating: 0, count: P * F)
        for (k, photo) in pool.enumerated() {
            for j in 0..<F { poolFeatures[k * F + j] = features[photo * F + j] }
        }
        var local = [Int](repeating: -1, count: total)
        var uses = [Float](repeating: 0, count: P)
        var stamp = [Int](repeating: -1, count: P)
        var order = Array(0..<total)
        order.shuffle()

        poolFeatures.withUnsafeBufferPointer { pf in
            cells.withUnsafeBufferPointer { cf in
                for (it, cell) in order.enumerated() {
                    let cx = cell % n, cy = cell / n
                    if spacing > 0 {
                        for y in max(0, cy - spacing)...min(n - 1, cy + spacing) {
                            for x in max(0, cx - spacing)...min(n - 1, cx + spacing) {
                                let a = local[y * n + x]
                                if a >= 0 { stamp[a] = it }
                            }
                        }
                    }
                    let co = cell * F
                    var best = -1
                    var bestCost = Float.infinity
                    for k in 0..<P where stamp[k] != it {
                        var d = uses[k] * penalty
                        if d >= bestCost { continue }
                        let ko = k * F
                        for j in 0..<F {
                            let e = cf[co + j] - pf[ko + j]
                            d += e * e
                        }
                        if d < bestCost { bestCost = d; best = k }
                    }
                    // Library smaller than the no-repeat neighbourhood: take anything.
                    if best < 0 { best = Int.random(in: 0..<P) }
                    local[cell] = best
                    uses[best] += 1
                }
            }
        }
        return local.map { pool[$0] }
    }
}
