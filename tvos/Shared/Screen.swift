/*
 * The shape of the screen the mosaic fills (width / height), fixed for the app's run:
 * 16:9 on the Apple TV; on a Mac, the display's shape when the app starts (most are 16:10).
 * Tiles are screen-shaped, so it sets the atlas slots, the photo crops and texture sizes.
 */
import CoreGraphics

enum Screen {
    private(set) static var aspect: CGFloat = 16.0 / 9.0

    /// Call once at launch, before the library loads.
    static func configure(aspect: CGFloat) {
        Self.aspect = min(3, max(1, aspect))
    }
}

import Foundation

enum AppFiles {
    /// Where the app keeps its framing results and memory log. On a Mac (not sandboxed)
    /// the Caches folder is shared by all apps, so it gets a folder of its own.
    static let caches: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Photomosaic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        return base
        #endif
    }()
}
