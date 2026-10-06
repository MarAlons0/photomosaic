/*
 * The app's one screen: load the album, then run the zoom player full screen.
 * Siri Remote: Play/Pause pauses, clicking skips to the next photo, Back opens
 * settings (the TV/Home button leaves the app).
 */
import SwiftUI

struct ContentView: View {
    @StateObject private var library = PhotoLibrary()
    @StateObject private var settings = AppSettings()
    @State private var player: Player?
    @State private var showSettings = false
    @State private var albums: [PhotoLibrary.AlbumChoice] = []
    @State private var before: (album: String, direction: String, grid: Int)?
    @State private var wasPaused = false
    @Environment(\.scenePhase) private var scenePhase

    private let aspect: CGFloat = 16.0 / 9.0

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
        .onExitCommand { openSettings() }
        .fullScreenCover(isPresented: $showSettings, onDismiss: closeSettings) {
            SettingsView(settings: settings, albums: albums, currentAlbum: library.albumTitle,
                         located: library.locatedCount, total: library.assets.count)
        }
        .onAppear {
            keepAwake()
            library.start(aspect: aspect, albumID: settings.albumID)
        }
        // tvOS can drop the "no screen saver" request (e.g. when the app returns to the
        // foreground), so re-assert it whenever we become active and every minute.
        .onChange(of: scenePhase) { _, phase in if phase == .active { keepAwake() } }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in keepAwake() }
        .onChange(of: library.phase) { _, phase in
            guard phase == .ready, player == nil else { return }
            let p = Player(library: library, settings: settings)
            player = p
            Task { await p.start() }
        }
    }

    /// Keep the Apple TV's own screen saver from starting while the mosaic plays.
    private func keepAwake() {
        let app = UIApplication.shared
        app.isIdleTimerDisabled = false
        app.isIdleTimerDisabled = true
    }

    private func openSettings() {
        albums = library.albumChoices()
        before = (settings.albumID, settings.direction, settings.grid)
        wasPaused = player?.paused ?? false
        player?.paused = true
        showSettings = true
    }

    private func closeSettings() {
        guard let before else { return }
        if settings.albumID != before.album {
            player = nil                       // a new player starts once the album has loaded
            library.start(aspect: aspect, albumID: settings.albumID)
            return
        }
        player?.paused = wasPaused
        if settings.direction != before.direction || settings.grid != before.grid {
            player?.settingsChanged()
        }
    }

    private var loadingCaption: String? {
        switch library.phase {
        case .requestingAccess: return "Requesting Photos access…"
        case .denied: return "Photos access denied — allow it in Settings → Apps → Photomosaic."
        case .noAlbum: return "That album has no photos — press Back to choose another."
        case let .loading(done, total): return "Loading \(library.albumTitle)… \(done) / \(total)"
        case .ready: return nil
        }
    }
}

/// Player status while it prepares; while playing, the photo caption and a pause badge.
private struct PlayerStatus: View {
    @ObservedObject var player: Player

    var body: some View {
        if !player.running {
            Caption(text: player.status)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if let text = player.caption {
                    Text(text)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 6)
                        .transition(.opacity)
                }
                if player.paused {
                    Text("❚❚  Paused")
                        .font(.caption)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(80)
            .animation(.easeInOut(duration: 0.8), value: player.caption)
        }
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
