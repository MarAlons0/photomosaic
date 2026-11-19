/*
 * Photomosaic for the Mac: the Apple TV app's mosaic in a window, reading an album (or the
 * newest photos) straight from the Photos library. Keys as in the browser version:
 * F full screen, Space pause, N or → next photo, S settings.
 */
import AppKit
import SwiftUI

@main
struct PhotomosaicApp: App {
    @StateObject private var mosaic: Mosaic

    init() {
        // Tiles take the shape of the display the app starts on (most Macs are 16:10).
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame
        Screen.configure(aspect: frame.map { $0.width / max(1, $0.height) } ?? 16.0 / 10.0)
        _mosaic = StateObject(wrappedValue: Mosaic())
    }

    var body: some Scene {
        Window("Photomosaic", id: "main") {
            MosaicView(mosaic: mosaic)
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 1280, height: 1280 / Screen.aspect)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { mosaic.openSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Mosaic") {
                Button("Pause or Resume") { mosaic.togglePause() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(mosaic.showSettings)
                Button("Next Photo") { mosaic.skip() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(mosaic.showSettings)
            }
        }
    }
}
