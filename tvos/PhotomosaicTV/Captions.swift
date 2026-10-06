/*
 * Photo captions: date, plus place name when the photo has a location.
 * Place names come from reverse geocoding (Apple's map service; no location
 * permission needed), looked up once per photo and cached.
 */
import CoreLocation
import Photos

@MainActor
final class Captions {
    private var places: [String: String] = [:]      // asset id -> place ("" = none found)
    private var lookups: [String: Task<String, Never>] = [:]
    private let geocoder = CLGeocoder()
    private var geocoding: Task<Void, Never>?       // CLGeocoder handles one request at a time

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    /// Caption text for `asset` under setting `mode` ("off", "date", "place"); nil = nothing to show.
    func text(for asset: PHAsset, mode: String) async -> String? {
        guard mode != "off" else { return nil }
        let date = asset.creationDate.map { Self.dateFormat.string(from: $0) }
        guard mode == "place", let location = asset.location else { return date }
        let place = await placeName(asset.localIdentifier, location)
        return [date, place.isEmpty ? nil : place].compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// Start looking up the place for `asset` ahead of time.
    func prefetch(_ asset: PHAsset, mode: String) {
        guard mode == "place", let location = asset.location else { return }
        _ = placeLookup(asset.localIdentifier, location)
    }

    private func placeName(_ id: String, _ location: CLLocation) async -> String {
        if let known = places[id] { return known }
        return await placeLookup(id, location).value
    }

    private func placeLookup(_ id: String, _ location: CLLocation) -> Task<String, Never> {
        if let running = lookups[id] { return running }
        let previous = geocoding
        let task = Task { () -> String in
            await previous?.value                      // queue behind the last lookup
            let marks = try? await geocoder.reverseGeocodeLocation(location)
            let name = marks?.first.map(Self.describe) ?? ""
            places[id] = name
            lookups[id] = nil
            return name
        }
        lookups[id] = task
        geocoding = Task { _ = await task.value }
        return task
    }

    /// "Ohiopyle, Pennsylvania" — plus the country when it isn't the viewer's own.
    private static func describe(_ p: CLPlacemark) -> String {
        var parts = [p.locality ?? p.name, p.administrativeArea].compactMap { $0 }
        if let country = p.country, p.isoCountryCode != Locale.current.region?.identifier {
            parts.append(country)
        }
        return parts.joined(separator: ", ")
    }
}
