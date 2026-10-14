/*
 * Photo captions: date, plus place name when the photo has a location.
 * Place names come from reverse geocoding (Apple's map service; no location
 * permission needed). Lookups are shared between photos taken within ~1 km of
 * each other, run one at a time, and are retried when the service fails — only
 * real answers are cached.
 */
import CoreLocation
import os
import Photos

@MainActor
final class Captions {
    private static let log = Logger(subsystem: "com.marioalonso.PhotomosaicTV", category: "captions")

    private var places: [String: String] = [:]      // area key -> place ("" = the service had no name)
    private var lookups: [String: Task<String?, Never>] = [:]
    private var retryAfter: [String: Date] = [:]    // area key -> don't ask again before this
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
        let place = await placeName(location) ?? ""
        return [date, place.isEmpty ? nil : place].compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// Start looking up the place for `asset` ahead of time.
    func prefetch(_ asset: PHAsset, mode: String) {
        guard mode == "place", let location = asset.location else { return }
        _ = lookup(location)
    }

    /// Photos within roughly a kilometre share one lookup (and one name).
    private static func areaKey(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.2f,%.2f", c.latitude, c.longitude)
    }

    private func placeName(_ location: CLLocation) async -> String? {
        if let known = places[Self.areaKey(location.coordinate)] { return known }
        return await lookup(location)?.value
    }

    private func lookup(_ location: CLLocation) -> Task<String?, Never>? {
        let key = Self.areaKey(location.coordinate)
        if places[key] != nil { return nil }
        if let running = lookups[key] { return running }
        if let wait = retryAfter[key], wait > Date() { return nil }
        let previous = geocoding
        let task = Task { () -> String? in
            await previous?.value                      // queue behind the last lookup
            var name: String?
            for attempt in 1...2 {
                do {
                    let marks = try await geocoder.reverseGeocodeLocation(location)
                    name = marks.first.map(Self.describe) ?? ""
                    Self.log.info("place \(key, privacy: .public) -> \(name ?? "", privacy: .public)")
                    print("[captions] \(key) -> \(name ?? "")")
                    break
                } catch {
                    Self.log.error("place \(key, privacy: .public) failed (attempt \(attempt)): \(error.localizedDescription, privacy: .public)")
                    print("[captions] \(key) failed (attempt \(attempt)): \(error)")
                    if attempt == 1 { try? await Task.sleep(for: .seconds(3)) }
                }
            }
            if let name {
                places[key] = name
            } else {
                retryAfter[key] = Date().addingTimeInterval(60)   // try again on a later showing
            }
            lookups[key] = nil
            return name
        }
        lookups[key] = task
        geocoding = Task { _ = await task.value }
        return task
    }

    /// "Ohiopyle, Pennsylvania"; where there's no town, the park or natural feature
    /// ("Yellowstone National Park, Wyoming") — plus the country when it isn't the viewer's own.
    private static func describe(_ p: CLPlacemark) -> String {
        let spot = p.locality ?? p.areasOfInterest?.first ?? p.subLocality ?? p.inlandWater
            ?? p.ocean ?? p.subAdministrativeArea ?? p.name
        // A city-state (Singapore, Monaco) is just its name, not "Singapore, SG, Singapore".
        if let spot, spot == p.country { return spot }
        var parts = [spot, p.administrativeArea].compactMap { $0 }
        if parts.count == 2 && parts[0] == parts[1] { parts.removeLast() }
        if let country = p.country, p.isoCountryCode != Locale.current.region?.identifier {
            parts.append(country)
        }
        return parts.joined(separator: ", ")
    }
}
