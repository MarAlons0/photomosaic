/*
 * User settings, persisted in UserDefaults.
 */
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private let store = UserDefaults.standard

    /// "in", "out" or "alternate".
    @Published var direction: String { didSet { store.set(direction, forKey: "direction") } }
    @Published var grid: Int { didSet { store.set(grid, forKey: "grid") } }
    /// Seconds.
    @Published var duration: Int { didSet { store.set(duration, forKey: "duration") } }
    @Published var hold: Int { didSet { store.set(hold, forKey: "hold") } }
    /// Colour blend, percent.
    @Published var tint: Int { didSet { store.set(tint, forKey: "tint") } }
    /// Photo caption: "off", "date" or "place" (date and place).
    @Published var caption: String { didSet { store.set(caption, forKey: "caption") } }
    /// PhotoKit album identifier; empty = "Nature", else the largest shared album.
    @Published var albumID: String { didSet { store.set(albumID, forKey: "albumID") } }

    static let grids = [60, 80, 100, 120, 150]
    static let durations = [12, 18, 22, 30, 45]
    static let holds = [0, 2, 3, 5, 8]
    static let tints = [0, 10, 20, 30]

    init() {
        direction = store.string(forKey: "direction") ?? "alternate"
        grid = store.object(forKey: "grid") as? Int ?? 120
        duration = store.object(forKey: "duration") as? Int ?? 22
        hold = store.object(forKey: "hold") as? Int ?? 3
        tint = store.object(forKey: "tint") as? Int ?? 20
        albumID = store.string(forKey: "albumID") ?? ""
        caption = store.string(forKey: "caption") ?? "place"
    }
}
