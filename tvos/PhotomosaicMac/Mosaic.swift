/*
 * The Mac app's state: the photo library, settings and the running player, shared by the
 * window and the menu commands.
 */
import AppKit
import Combine
import SwiftUI

@MainActor
final class Mosaic: ObservableObject {
    let library = PhotoLibrary()
    let settings = AppSettings()
    @Published private(set) var player: Player?
    @Published var showSettings = false
    @Published private(set) var albums: [PhotoLibrary.AlbumChoice] = []

    private var before: (album: String, direction: String, grid: Int, framing: String)?
    private var wasPaused = false
    private var watching: Set<AnyCancellable> = []
    private var pauseWatch: AnyCancellable?
    private var awake: NSObjectProtocol?

    init() {
        library.smartFraming = settings.framing == "smart"
        library.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self, phase == .ready, self.player == nil else { return }
                self.startPlayer()
            }
            .store(in: &watching)
        library.start(aspect: Screen.aspect, albumID: settings.albumID)
    }

    private func startPlayer() {
        let p = Player(library: library, settings: settings)
        player = p
        // Keep the display awake while the mosaic plays (not while it's paused).
        pauseWatch = p.$paused.sink { [weak self] paused in self?.keepAwake(!paused) }
        Task { await p.start() }
    }

    private func keepAwake(_ on: Bool) {
        if on, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Playing the mosaic")
        } else if !on, let a = awake {
            ProcessInfo.processInfo.endActivity(a)
            awake = nil
        }
    }

    func togglePause() { player?.paused.toggle() }
    func skip() { player?.skip() }

    func openSettings() {
        guard !showSettings else { return }
        albums = library.albumChoices()
        before = (settings.albumID, settings.direction, settings.grid, settings.framing)
        wasPaused = player?.paused ?? false
        player?.paused = true
        showSettings = true
    }

    /// Apply what changed in the settings sheet (same rules as on the Apple TV).
    func closeSettings() {
        showSettings = false
        guard let before else { return }
        self.before = nil
        if settings.albumID != before.album {
            player = nil                       // a new player starts once the album has loaded
            keepAwake(false)
            library.start(aspect: Screen.aspect, albumID: settings.albumID)
            return
        }
        if settings.framing != before.framing {
            // Every crop changes: start a fresh player (it rebuilds the tile atlas).
            library.smartFraming = settings.framing == "smart"
            library.refreshFeatures()
            startPlayer()
            return
        }
        player?.paused = wasPaused
        if settings.direction != before.direction || settings.grid != before.grid {
            player?.settingsChanged()
        }
    }
}
