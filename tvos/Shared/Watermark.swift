/*
 * Credit in the bottom-right corner of the mosaic: small, faint, readable over any photo.
 */
import SwiftUI

struct Watermark: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Created by Mario Alonso with Claude Code")
            #if os(macOS)
            Link("www.looking4nature.com", destination: URL(string: "https://www.looking4nature.com")!)
            #else
            Text("www.looking4nature.com")   // no browser on the Apple TV
            #endif
        }
        #if os(tvOS)
        .font(.system(size: 17))   // tvOS's caption style is far larger than the Mac's
        #else
        .font(.caption)
        #endif
        .foregroundStyle(.white.opacity(0.55))
        .tint(.white.opacity(0.55))
        .shadow(color: .black.opacity(0.7), radius: 3)
        #if os(tvOS)
        .padding(60)   // clear of the edges TVs may crop
        #else
        .padding(20)
        #endif
    }
}
