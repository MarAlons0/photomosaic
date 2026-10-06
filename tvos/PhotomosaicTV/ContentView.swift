/*
 * Milestone 2: a still mosaic of the album, full screen.
 * Play/Pause or Select builds the next one from a tile near the middle —
 * the photo the zoom player (milestone 3) will dive into.
 */
import SwiftUI

struct ContentView: View {
    @StateObject private var library = PhotoLibrary()
    @State private var mosaic: Mosaic?
    @State private var busy = false
    @State private var note = ""

    private let gridSize = 100
    private let screen = CGSize(width: 3840, height: 2160)
    private let tint: CGFloat = 0.2

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let mosaic {
                Image(decorative: mosaic.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            Text(caption)
                .font(.caption)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .padding(80)
        }
        .ignoresSafeArea()
        .focusable()
        .onPlayPauseCommand { next() }
        .onTapGesture { next() }
        .onAppear { library.start(aspect: screen.width / screen.height) }
        .onChange(of: library.phase) { _, phase in
            if phase == .ready && mosaic == nil { next() }
        }
    }

    private var caption: String {
        switch library.phase {
        case .requestingAccess: return "Requesting Photos access…"
        case .denied: return "Photos access denied — allow it in Settings → Apps → Photomosaic."
        case .noAlbum: return "No shared album found."
        case let .loading(done, total): return "Loading \(library.albumTitle)… \(done) / \(total)"
        case .ready:
            let count = library.usable.count
            guard let mosaic else { return "\(library.albumTitle) · \(count) photos · building…" }
            let built = String(format: "%.1f s", mosaic.buildSeconds)
            return "\(library.albumTitle) · \(count) photos · \(mosaic.n)×\(mosaic.n) mosaic built in \(built)"
                + (busy ? " · building next…" : " · ▶︎❚❚ next") + note
        }
    }

    private func next() {
        guard library.phase == .ready, !busy else { return }
        let usable = library.usable
        guard usable.count > 1 else { return }
        busy = true

        // Next target: a tile near the middle of the current mosaic, else random.
        var target = usable.randomElement()!
        if let m = mosaic {
            let lo = m.n / 5, hi = m.n - m.n / 5
            for _ in 0..<20 {
                let pick = m.assign[Int.random(in: lo..<hi) * m.n + Int.random(in: lo..<hi)]
                if pick != m.target { target = pick; break }
            }
        }

        Task {
            guard let big = await library.large(target, size: screen) else {
                note = " · couldn't load a photo"
                busy = false
                return
            }
            let micros = library.micros, features = library.features
            let n = gridSize, size = screen, tint = tint
            let aspect = screen.width / screen.height
            let made = await Task.detached(priority: .userInitiated) {
                MosaicBuilder.make(target: target, targetImage: big, n: n, micros: micros,
                                   features: features, usable: usable, aspect: aspect,
                                   size: size, tint: tint)
            }.value
            if let made { mosaic = made; note = "" }
            busy = false
        }
    }
}
