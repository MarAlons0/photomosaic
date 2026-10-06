/*
 * The photo source: one album from iCloud Photos via PhotoKit.
 *
 * Every photo gets a "micro" covering 96x54 px (kept in memory: the tile atlas and
 * colour features). Larger versions are requested on demand.
 */
import Photos
import UIKit

@MainActor
final class PhotoLibrary: ObservableObject {
    enum Phase: Equatable {
        case requestingAccess
        case denied
        case noAlbum
        case loading(done: Int, total: Int)
        case ready
    }

    static let preferredAlbum = "Nature"
    static let microSize = CGSize(width: 96, height: 54)   // one 16:9 atlas slot

    @Published private(set) var phase: Phase = .requestingAccess
    @Published private(set) var albumTitle = ""

    private(set) var assets: [PHAsset] = []
    private(set) var micros: [CGImage?] = []
    /// 12 floats per photo (Features.count), for the current screen aspect.
    private(set) var features: [Float] = []
    private(set) var aspect: CGFloat = 16.0 / 9.0
    private var loaded = 0

    private var generation = 0

    /// Load album `albumID` ("" = the preferred album, else the largest shared album).
    /// Safe to call again to switch albums.
    func start(aspect: CGFloat, albumID: String) {
        self.aspect = aspect
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            Task { @MainActor in
                switch status {
                case .authorized, .limited: self.loadAlbum(id: albumID)
                default: self.phase = .denied
                }
            }
        }
    }

    private static var imagesOnly: PHFetchOptions {
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return o
    }

    struct AlbumChoice: Identifiable {
        let id: String
        let title: String
        let count: Int
        let shared: Bool
    }

    /// Albums with photos, for the settings picker: shared albums first.
    func albumChoices() -> [AlbumChoice] {
        var out: [AlbumChoice] = []
        for subtype in [PHAssetCollectionSubtype.albumCloudShared, .albumRegular] {
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: subtype, options: nil)
                .enumerateObjects { c, _, _ in
                    let n = PHAsset.fetchAssets(in: c, options: Self.imagesOnly).count
                    guard n > 1 else { return }
                    out.append(AlbumChoice(id: c.localIdentifier, title: c.localizedTitle ?? "Album",
                                           count: n, shared: subtype == .albumCloudShared))
                }
        }
        return out
    }

    private func pickAlbum(id: String) -> PHAssetCollection? {
        if !id.isEmpty,
           let c = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return c
        }
        var best: (PHAssetCollection, Int)?
        for subtype in [PHAssetCollectionSubtype.albumCloudShared, .albumRegular] {
            let found = PHAssetCollection.fetchAssetCollections(with: .album, subtype: subtype, options: nil)
            var match: PHAssetCollection?
            found.enumerateObjects { c, _, stop in
                if c.localizedTitle == Self.preferredAlbum { match = c; stop.pointee = true; return }
                let n = PHAsset.fetchAssets(in: c, options: Self.imagesOnly).count
                if subtype == .albumCloudShared, n > (best?.1 ?? 0) { best = (c, n) }
            }
            if let match { return match }
        }
        return best?.0
    }

    private func loadAlbum(id: String) {
        generation += 1
        let gen = generation
        guard let album = pickAlbum(id: id) else { phase = .noAlbum; return }
        albumTitle = album.localizedTitle ?? "Album"
        let fetched = PHAsset.fetchAssets(in: album, options: Self.imagesOnly)
        var list: [PHAsset] = []
        list.reserveCapacity(fetched.count)
        fetched.enumerateObjects { a, _, _ in list.append(a) }
        guard list.count > 1 else { phase = .noAlbum; return }
        assets = list
        micros = Array(repeating: nil, count: list.count)
        features = Array(repeating: 0, count: list.count * Features.count)
        phase = .loading(done: 0, total: list.count)

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat   // exactly one callback per request
        opts.resizeMode = .fast
        loaded = 0
        for (i, asset) in list.enumerated() {
            // aspectFill: even portrait photos keep 96x54 px after the 16:9 crop.
            PHImageManager.default().requestImage(for: asset, targetSize: Self.microSize,
                                                  contentMode: .aspectFill, options: opts) { image, _ in
                Task { @MainActor in
                    guard gen == self.generation else { return }   // an older album's late reply
                    if let cg = image.flatMap(upright) {
                        self.micros[i] = cg
                        let crop = Features.cover(width: cg.width, height: cg.height, aspect: self.aspect)
                        let f = Features.grid(cg, crop: crop, n: 1, px: 8)
                        for j in 0..<Features.count { self.features[i * Features.count + j] = f[j] }
                    }
                    self.loaded += 1
                    if self.loaded == list.count {
                        self.phase = .ready
                    } else if self.loaded % 50 == 0 {
                        self.phase = .loading(done: self.loaded, total: list.count)
                    }
                }
            }
        }
    }

    /// Indices of photos whose micro loaded (only these can be tiles).
    var usable: [Int] { micros.indices.filter { micros[$0] != nil } }

    /// A version of photo i big enough to fill `size` pixels.
    func large(_ i: Int, size: CGSize) async -> CGImage? {
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .exact
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: assets[i], targetSize: size,
                                                  contentMode: .aspectFill, options: opts) { image, _ in
                cont.resume(returning: image.flatMap(upright))
            }
        }
    }
}

/// CGImage with the UIImage's orientation applied (PhotoKit may return rotated images).
func upright(_ image: UIImage) -> CGImage? {
    if image.imageOrientation == .up, let cg = image.cgImage { return cg }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: image.size, format: format)
        .image { _ in image.draw(at: .zero) }
        .cgImage
}
