// Subject regions for smart framing, found with Apple's Vision framework (macOS).
//
// Used by build_library.py. Reads "id<TAB>path" lines on stdin and writes one
// "id<TAB>json" line per photo: [F, U, E, M], each a box [x0, y0, x1, y1] normalised
// to the photo with the origin at the top left, or 0 when there is none —
//   F  all faces
//   U  where the eye goes (attention saliency) together with whole objects (objectness)
//   E  where the eye goes
//   M  the strongest single region (faces, else the top attention region, else object)
// The player keeps the first of F, U, E that fits its crop in view; else the top of M when
// it's a narrow, tall object (an animal sitting up), or its middle. Same rules as the Apple
// TV app (tvos/PhotomosaicTV/Framing.swift), resolved per screen shape.
// A photo that can't be read gets "!" instead of json.
//
//     swift tools/framing.swift < photos.tsv
import Foundation
import ImageIO
import Vision

func box(_ r: CGRect) -> [Double] {
    [r.minX, 1 - r.maxY, r.maxX, 1 - r.minY].map { (Double($0) * 1000).rounded() / 1000 }
}

func union(_ rs: [CGRect]) -> CGRect? {
    rs.isEmpty ? nil : rs.dropFirst().reduce(rs[0]) { $0.union($1) }
}

func regions(_ o: VNSaliencyImageObservation?) -> [CGRect] {
    (o?.salientObjects ?? []).filter { $0.confidence > 0.1 }
        .sorted { $0.confidence > $1.confidence }.map(\.boundingBox)
}

func analyse(_ path: String) -> String {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 1600,
              kCGImageSourceCreateThumbnailWithTransform: true,
          ] as CFDictionary) else { return "!" }
    let attention = VNGenerateAttentionBasedSaliencyImageRequest()
    let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
    let faces = VNDetectFaceRectanglesRequest()
    do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([attention, objects, faces]) }
    catch { return "!" }

    let faceBoxes = (faces.results ?? []).map(\.boundingBox)
    let eye = regions(attention.results?.first)
    let whole = regions(objects.results?.first)
    let found: [CGRect?] = [union(faceBoxes), union(eye + whole), union(eye),
                            union(faceBoxes) ?? eye.first ?? whole.first]
    let parts = found.map { r -> String in
        guard let r else { return "0" }
        return "[" + box(r).map { String($0) }.joined(separator: ",") + "]"
    }
    return "[" + parts.joined(separator: ",") + "]"
}

while let line = readLine() {
    let cols = line.split(separator: "\t", maxSplits: 1).map(String.init)
    guard cols.count == 2 else { continue }
    print("\(cols[0])\t\(analyse(cols[1]))")
    fflush(stdout)
}
