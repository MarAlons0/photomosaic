/*
 * Milestone 1 probe (see docs/appletv.md): can a third-party tvOS app see the
 * iCloud Photos library and shared albums through PhotoKit, and how quickly
 * does it deliver tile-sized images?
 *
 * Lists every album the app can see with its photo count; selecting one loads
 * 60 thumbnails and reports how long that took.
 */
import Photos
import SwiftUI

struct AlbumInfo: Identifiable {
    let id: String
    let title: String
    let kind: String
    let count: Int
    let collection: PHAssetCollection
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var status = "Requesting Photos access…"
    @Published var libraryCount: Int?
    @Published var albums: [AlbumInfo] = []
    @Published var thumbs: [UIImage] = []
    @Published var timing = "Select an album to time loading 60 thumbnails."

    private var requested = 0
    private var finished = 0
    private var failed = 0
    private var started = Date()
    private var batch = 0

    private static var imagesOnly: PHFetchOptions {
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return o
    }

    func start() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
            Task { @MainActor in self.handle(s) }
        }
    }

    private func handle(_ s: PHAuthorizationStatus) {
        switch s {
        case .authorized:
            status = "Photos access: granted"
            load()
        case .limited:
            status = "Photos access: limited (only selected photos)"
            load()
        case .denied, .restricted:
            status = "Photos access denied — allow it in Settings → Apps → Photomosaic."
        case .notDetermined:
            status = "Photos access not decided yet."
        @unknown default:
            status = "Unknown Photos access status."
        }
    }

    private func load() {
        libraryCount = PHAsset.fetchAssets(with: Self.imagesOnly).count
        var found: [AlbumInfo] = []
        let kinds: [(PHAssetCollectionSubtype, String)] = [
            (.albumCloudShared, "Shared album"),
            (.albumRegular, "Album"),
        ]
        for (subtype, label) in kinds {
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: subtype, options: nil)
            collections.enumerateObjects { c, _, _ in
                let n = PHAsset.fetchAssets(in: c, options: Self.imagesOnly).count
                found.append(AlbumInfo(id: c.localIdentifier, title: c.localizedTitle ?? "(untitled)",
                                       kind: label, count: n, collection: c))
            }
        }
        albums = found
        if found.isEmpty { status += " · no albums visible to this app" }
    }

    func sample(_ album: AlbumInfo) {
        batch += 1
        let thisBatch = batch
        thumbs = []
        let assets = PHAsset.fetchAssets(in: album.collection, options: Self.imagesOnly)
        requested = min(60, assets.count)
        finished = 0
        failed = 0
        started = Date()
        guard requested > 0 else { timing = "\(album.title) has no photos."; return }
        timing = "Loading \(requested) thumbnails from \(album.title)…"

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true          // fetch from iCloud if not on the device
        opts.deliveryMode = .highQualityFormat      // one callback per image
        opts.resizeMode = .fast
        for i in 0..<requested {
            PHImageManager.default().requestImage(
                for: assets[i], targetSize: CGSize(width: 320, height: 320),
                contentMode: .aspectFill, options: opts
            ) { image, _ in
                Task { @MainActor in
                    guard thisBatch == self.batch else { return }
                    if let image { self.thumbs.append(image) } else { self.failed += 1 }
                    self.finished += 1
                    if self.finished == self.requested {
                        let secs = Date().timeIntervalSince(self.started)
                        self.timing = String(format: "%@: %d thumbnails in %.1f s (%d failed)",
                                             album.title, self.requested - self.failed, secs, self.failed)
                    }
                }
            }
        }
    }
}

struct ProbeView: View {
    @StateObject private var model = ProbeModel()

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Photomosaic — Photos probe").font(.title2).bold()
                Text(model.status)
                if let n = model.libraryCount { Text("Library: \(n) photos visible") }
                List(model.albums) { album in
                    Button {
                        model.sample(album)
                    } label: {
                        HStack {
                            Text(album.title).bold(album.title == "Nature")
                            Spacer()
                            Text("\(album.count)")
                            Text(album.kind).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 900)

            VStack(alignment: .leading, spacing: 16) {
                Text(model.timing)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 8), count: 6), spacing: 8) {
                    ForEach(model.thumbs.indices, id: \.self) { i in
                        Image(uiImage: model.thumbs[i])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 150, height: 100)
                            .clipped()
                    }
                }
            }
        }
        .padding(60)
        .onAppear { model.start() }
    }
}
