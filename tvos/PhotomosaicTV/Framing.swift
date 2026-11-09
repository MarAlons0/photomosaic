/*
 * Smart framing: where to place the 16:9 crop of a photo so its subject stays in view.
 *
 * A 3:2 photo loses 1/6 of its height to the crop, a portrait one far more. Vision finds
 * the subject: faces, attention-based saliency (where the eye goes) and objectness;
 * the crop moves from the centre only as far as needed to keep it inside, so ordinary
 * compositions stay as they were.
 *
 * The result is a crop *position* along the trimmed axis — 0 = keep the top (or left)
 * edge, 1 = the bottom (or right), 0.5 = centred — which applies to every size of the
 * photo (atlas micro, 480 px, full size), so a tile and its full-screen photo match.
 */
import CoreGraphics
import Foundation
import Vision

enum Framing {
    static func position(of image: CGImage, aspect: CGFloat) -> CGFloat {
        let W = CGFloat(image.width), H = CGFloat(image.height)
        guard W > 0, H > 0, abs(W / H - aspect) > 0.01 else { return 0.5 }
        let vertical = W / H < aspect          // the crop trims top and bottom
        let keep = vertical ? (W / aspect) / H : (H * aspect) / W   // share of the axis kept

        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([attention, objects, faces])

        // Vision boxes are normalised with the origin at the bottom left; turn each into an
        // interval along the trimmed axis, measured from the top (or left).
        typealias Span = (lo: CGFloat, hi: CGFloat)
        func span(_ b: CGRect) -> Span { vertical ? (1 - b.maxY, 1 - b.minY) : (b.minX, b.maxX) }
        func regions(_ o: VNSaliencyImageObservation?) -> [VNRectangleObservation] {
            (o?.salientObjects ?? [])
                .filter { $0.confidence > 0.1 }.sorted { $0.confidence > $1.confidence }
        }
        func union(_ s: [Span]) -> Span? {
            s.isEmpty ? nil : (s.map(\.lo).min()!, s.map(\.hi).max()!)
        }
        let faceBoxes = (faces.results ?? []).map(\.boundingBox)
        let eyeBoxes = regions(attention.results?.first).map(\.boundingBox)
        let wholeBoxes = regions(objects.results?.first).map(\.boundingBox)
        let faceSpans = faceBoxes.map(span), eye = eyeBoxes.map(span), whole = wholeBoxes.map(span)

        // What to keep, best first: faces; where the eye goes plus whole objects (attention
        // alone often stops short — a second animal, an owl's talons); where the eye goes.
        // If none fits, the strongest region is placed below.
        let fits = { (s: Span) in s.hi - s.lo <= keep }
        var subject: Span? = union(faceSpans).flatMap { fits($0) ? $0 : nil }
        if subject == nil, let s = union(eye + whole), fits(s) { subject = s }
        if subject == nil, let s = union(eye), fits(s) { subject = s }

        // The crop leaves the centre only as far as needed to keep (lo, hi) in, with a margin.
        let margin: CGFloat = 0.03
        func place(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            var start = (1 - keep) / 2
            if lo - margin < start { start = lo - margin }               // move up…
            if hi + margin > start + keep { start = hi + margin - keep }   // …or down
            return start
        }
        let start: CGFloat
        if let (lo, hi) = subject {
            start = place(lo, hi)
        } else if let box = faceBoxes.isEmpty ? (eyeBoxes.first ?? wholeBoxes.first)
                                              : faceBoxes.dropFirst().reduce(faceBoxes[0], { $0.union($1) }) {
            // The subject can't fit. A narrow one that's too tall (an animal sitting up in a
            // square photo) keeps its top, where the head usually is; a scene spanning the
            // frame (a waterfall), or a subject too wide, keeps its middle.
            let main = span(box)
            if vertical && box.width < 0.75 {
                start = main.lo - margin
            } else {
                let c = (main.lo + main.hi) / 2
                start = place(c - keep / 2, c + keep / 2)
            }
        } else {
            return 0.5
        }
        return min(1, max(0, start / (1 - keep)))
    }
}
