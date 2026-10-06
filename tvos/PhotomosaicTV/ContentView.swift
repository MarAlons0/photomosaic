/*
 * The app's one screen: load the album, then run the zoom player full screen.
 * Siri Remote: Play/Pause pauses, clicking skips to the next photo.
 */
import SwiftUI

struct ContentView: View {
    @StateObject private var library = PhotoLibrary()
    @State private var player: Player?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let player {
                PlayerView(player: player)
                PlayerStatus(player: player)
            }
            if player?.running != true, let caption = loadingCaption {
                Caption(text: caption)
            }
        }
        .ignoresSafeArea()
        .focusable()
        .onPlayPauseCommand { player?.paused.toggle() }
        .onTapGesture { player?.skip() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // keep the TV's own screen saver away
            library.start(aspect: 16.0 / 9.0)
        }
        .onChange(of: library.phase) { _, phase in
            guard phase == .ready, player == nil else { return }
            let p = Player(library: library)
            player = p
            Task { await p.start() }
        }
    }

    private var loadingCaption: String? {
        switch library.phase {
        case .requestingAccess: return "Requesting Photos access…"
        case .denied: return "Photos access denied — allow it in Settings → Apps → Photomosaic."
        case .noAlbum: return "No shared album found."
        case let .loading(done, total): return "Loading \(library.albumTitle)… \(done) / \(total)"
        case .ready: return nil
        }
    }
}

/// Player status while it prepares (hidden once running).
private struct PlayerStatus: View {
    @ObservedObject var player: Player

    var body: some View {
        if !player.running { Caption(text: player.status) }
    }
}

private struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .padding(80)
    }
}
