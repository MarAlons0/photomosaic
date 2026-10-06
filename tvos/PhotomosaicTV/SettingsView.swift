/*
 * Settings, opened with the remote's Back button and closed with it again.
 */
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let albums: [PhotoLibrary.AlbumChoice]
    let currentAlbum: String
    let located: Int
    let total: Int

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    Picker("Album", selection: $settings.albumID) {
                        if !albums.contains(where: { $0.id == settings.albumID }) {
                            Text(currentAlbum).tag(settings.albumID)
                        }
                        ForEach(albums) { album in
                            Text("\(album.title) · \(album.count)\(album.shared ? " · shared" : "")")
                                .tag(album.id)
                        }
                    }
                }
                Section {
                    Picker("Photo caption", selection: $settings.caption) {
                        Text("Off").tag("off")
                        Text("Date").tag("date")
                        Text("Date & place").tag("place")
                    }
                } footer: {
                    Text("Shown while a photo fills the screen. \(located) of \(total) photos in this album have a location.")
                }
                Section("Animation") {
                    Picker("Direction", selection: $settings.direction) {
                        Text("Zoom in").tag("in")
                        Text("Zoom out").tag("out")
                        Text("Alternate").tag("alternate")
                    }
                    Picker("Grid size", selection: $settings.grid) {
                        ForEach(AppSettings.grids, id: \.self) { Text("\($0) × \($0)").tag($0) }
                    }
                    Picker("Zoom duration", selection: $settings.duration) {
                        ForEach(AppSettings.durations, id: \.self) { Text("\($0) s").tag($0) }
                    }
                    Picker("Pause on each photo", selection: $settings.hold) {
                        ForEach(AppSettings.holds, id: \.self) { Text($0 == 0 ? "None" : "\($0) s").tag($0) }
                    }
                    Picker("Colour blend", selection: $settings.tint) {
                        ForEach(AppSettings.tints, id: \.self) { Text($0 == 0 ? "Off" : "\($0) %").tag($0) }
                    }
                }
                Section {
                    Text("Click pauses · swipe right skips to the next photo · Back opens and closes settings · Play/Pause controls music")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Photomosaic")
        }
    }
}
