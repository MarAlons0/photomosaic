// Reverse-geocode coordinates with Apple's map service (CLGeocoder), for build_library.py.
//
// Input (stdin):  one "key<TAB>latitude<TAB>longitude" per line.
// Output (stdout): one "key<TAB>place" per line as each answer arrives; place is empty when
//                  the service has no name for the spot, and "!" when the lookup failed.
//
// Names follow the Apple TV app's Captions.swift: town, else park or natural feature, then
// state/region, plus the country when it isn't this Mac's region.
//
//     swift tools/geocode.swift < coords.tsv
import CoreLocation
import Foundation

func describe(_ p: CLPlacemark) -> String {
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

let geocoder = CLGeocoder()

while let line = readLine() {
    let f = line.split(separator: "\t", omittingEmptySubsequences: false)
    guard f.count == 3, let lat = Double(f[1]), let lon = Double(f[2]) else { continue }
    let key = String(f[0])
    var answer = "!"
    // Apple rate-limits lookups; on failure wait and try again a couple of times.
    for attempt in 0..<3 {
        do {
            let marks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
            answer = marks.first.map(describe) ?? ""
            break
        } catch {
            FileHandle.standardError.write("\(key): \(error.localizedDescription) (attempt \(attempt + 1))\n".data(using: .utf8)!)
            try? await Task.sleep(for: .seconds(attempt == 0 ? 15 : 60))
        }
    }
    print("\(key)\t\(answer)")
    fflush(stdout)
    try? await Task.sleep(for: .milliseconds(700))   // stay under the rate limit
}
