/*
 * Settings sheet (S or ⌘,): the same choices as on the Apple TV.
 */
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let albums: [PhotoLibrary.AlbumChoice]
    let currentAlbum: String
    let located: Int
    let total: Int
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Album", selection: $settings.albumID) {
                        if !albums.contains(where: { $0.id == settings.albumID }) {
                            Text(currentAlbum.isEmpty ? "Automatic" : currentAlbum).tag(settings.albumID)
                        }
                        ForEach(albums) { a in
                            Text("\(a.title) (\(a.count.formatted()))\(a.shared ? " · shared" : "")").tag(a.id)
                        }
                    }
                    Picker("Photo framing", selection: $settings.framing) {
                        Text("Smart").tag("smart")
                        Text("Centre").tag("centre")
                    }
                    Picker("Photo caption", selection: $settings.caption) {
                        Text("Off").tag("off")
                        Text("Date").tag("date")
                        Text("Date & place").tag("place")
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Albums with 100 or more photos are listed. Smart framing moves each crop to keep the photo's subject in view. Captions show while a photo fills the screen; \(located) of \(total) photos here have a location.")
                        .foregroundStyle(.secondary)
                }
                Section {
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
                } header: {
                    Text("Animation")
                } footer: {
                    Text("Keys: F full screen · Space pause · N or → next photo · S settings")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
