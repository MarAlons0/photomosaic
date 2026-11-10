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
                    NavigationLink {
                        AlbumList(settings: settings, albums: albums, currentAlbum: currentAlbum)
                    } label: {
                        HStack {
                            Text("Album")
                            Spacer()
                            Text(albums.first { $0.id == settings.albumID }?.title ?? currentAlbum)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Choice("Photo framing", $settings.framing,
                           [("Smart", "smart"), ("Centre", "centre")])
                } footer: {
                    Text("Photos are cropped to fit the screen. Smart moves the crop to keep each photo's subject in view; Centre always crops evenly.")
                }
                Section {
                    Choice("Photo caption", $settings.caption,
                           [("Off", "off"), ("Date", "date"), ("Date & place", "place")])
                } footer: {
                    Text("Shown while a photo fills the screen. \(located) of \(total) photos in this album have a location.")
                }
                Section("Animation") {
                    Choice("Direction", $settings.direction,
                           [("Zoom in", "in"), ("Zoom out", "out"), ("Alternate", "alternate")])
                    Choice("Grid size", $settings.grid, AppSettings.grids.map { ("\($0) × \($0)", $0) })
                    Choice("Zoom duration", $settings.duration, AppSettings.durations.map { ("\($0) s", $0) })
                    Choice("Pause on each photo", $settings.hold,
                           AppSettings.holds.map { ($0 == 0 ? "None" : "\($0) s", $0) })
                    Choice("Colour blend", $settings.tint,
                           AppSettings.tints.map { ($0 == 0 ? "Off" : "\($0) %", $0) })
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

/// A setting row that opens its own list of choices. Pickers inside a Form don't open on
/// tvOS 27, so every choice is a plain button (✓ on the current one); choosing goes back.
private struct Choice<Value: Hashable>: View {
    let title: String
    @Binding var value: Value
    let options: [(label: String, value: Value)]

    init(_ title: String, _ value: Binding<Value>, _ options: [(String, Value)]) {
        self.title = title
        _value = value
        self.options = options.map { (label: $0.0, value: $0.1) }
    }

    var body: some View {
        NavigationLink {
            ChoiceList(title: title, value: $value, options: options)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(options.first { $0.value == value }?.label ?? "").foregroundStyle(.secondary)
            }
        }
    }
}

private struct ChoiceList<Value: Hashable>: View {
    let title: String
    @Binding var value: Value
    let options: [(label: String, value: Value)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(options.indices, id: \.self) { k in
                let option = options[k]
                Button {
                    value = option.value
                    dismiss()
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if option.value == value { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

/// Album chooser: every album is a plain button (pickers with grouped entries don't take
/// focus reliably on tvOS). Choosing one goes back to the settings screen.
private struct AlbumList: View {
    @ObservedObject var settings: AppSettings
    let albums: [PhotoLibrary.AlbumChoice]
    let currentAlbum: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if !albums.contains(where: { $0.id == settings.albumID }) {
                Section("Playing now") {
                    row(title: currentAlbum, count: nil, id: settings.albumID)
                }
            }
            let shared = albums.filter(\.shared), mine = albums.filter { !$0.shared }
            if !shared.isEmpty {
                Section("Shared albums") {
                    ForEach(shared) { row(title: $0.title, count: $0.count, id: $0.id) }
                }
            }
            if !mine.isEmpty {
                Section("My albums") {
                    ForEach(mine) { row(title: $0.title, count: $0.count, id: $0.id) }
                }
            }
        }
        .navigationTitle("Album")
    }

    private func row(title: String, count: Int?, id: String) -> some View {
        Button {
            settings.albumID = id
            dismiss()
        } label: {
            HStack {
                Text(title)
                Spacer()
                if let count { Text("\(count)").foregroundStyle(.secondary) }
                if id == settings.albumID { Image(systemName: "checkmark") }
            }
        }
    }
}
