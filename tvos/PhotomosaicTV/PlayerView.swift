import MetalKit
import SwiftUI

/// The Metal view hosting the player.
struct PlayerView: UIViewRepresentable {
    let player: Player

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        player.configure(view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}
}
