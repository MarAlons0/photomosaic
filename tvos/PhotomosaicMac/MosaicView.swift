/*
 * The window: the mosaic, kept at the display's shape (black bars if the window isn't),
 * with the loading status, caption and pause badge over it.
 */
import AppKit
import MetalKit
import SwiftUI

struct MosaicView: View {
    @ObservedObject var mosaic: Mosaic
    @ObservedObject private var library: PhotoLibrary
    @FocusState private var focused: Bool

    init(mosaic: Mosaic) {
        self.mosaic = mosaic
        library = mosaic.library
    }

    var body: some View {
        ZStack {
            Color.black
            ZStack(alignment: .bottomLeading) {
                Color.black
                if let player = mosaic.player {
                    PlayerView(player: player)
                    PlayerStatus(player: player)
                }
                if mosaic.player?.running != true, let text = loadingCaption {
                    Badge(text: text)
                }
            }
            .overlay(alignment: .bottomTrailing) { Watermark() }
            .aspectRatio(Screen.aspect, contentMode: .fit)
        }
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onTapGesture { mosaic.togglePause() }
        .onKeyPress(characters: .init(charactersIn: "fFnNsS"), phases: .down) { press in
            switch press.characters.lowercased() {
            case "f": toggleFullScreen()
            case "n": mosaic.skip()
            default: mosaic.openSettings()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            guard let w = NSApp.keyWindow, w.styleMask.contains(.fullScreen) else { return .ignored }
            w.toggleFullScreen(nil)
            return .handled
        }
        // Hide the pointer over the mosaic until the mouse moves.
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            if NSApp.isActive, !mosaic.showSettings { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        .sheet(isPresented: Binding(get: { mosaic.showSettings },
                                    set: { if !$0 { mosaic.closeSettings() } })) {
            SettingsView(settings: mosaic.settings, albums: mosaic.albums,
                         currentAlbum: library.albumTitle, located: library.locatedCount,
                         total: library.assets.count) { mosaic.closeSettings() }
        }
        .onChange(of: mosaic.showSettings) { _, open in if !open { focused = true } }
    }

    private func toggleFullScreen() {
        (NSApp.keyWindow ?? NSApp.windows.first)?.toggleFullScreen(nil)
    }

    private var loadingCaption: String? {
        switch library.phase {
        case .requestingAccess: return "Requesting access to Photos…"
        case .denied: return "Photos access is off. Turn it on in System Settings → Privacy & Security → Photos, then reopen Photomosaic."
        case .noAlbum: return "No photos found. Press S to choose an album."
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
            Badge(text: player.status)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let text = player.caption {
                    Text(text)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 6)
                        .transition(.opacity)
                }
                if player.paused {
                    Text("❚❚  Paused")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(36)
            .animation(.easeInOut(duration: 0.8), value: player.caption)
        }
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .padding(36)
    }
}

/// The Metal view hosting the player.
struct PlayerView: NSViewRepresentable {
    let player: Player

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        player.configure(view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}
}
