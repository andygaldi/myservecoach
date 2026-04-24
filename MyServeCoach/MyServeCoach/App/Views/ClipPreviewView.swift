import SwiftUI
import AVKit

struct ClipPreviewView: View {
    let url: URL
    let onUseClip: () -> Void
    let onRetake: () -> Void

    @State private var player: AVPlayer

    init(url: URL, onUseClip: @escaping () -> Void, onRetake: @escaping () -> Void) {
        self.url = url
        self.onUseClip = onUseClip
        self.onRetake = onRetake
        self._player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .top)
                .onAppear { player.play() }
                .navigationTitle("Review Clip")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Retake", action: onRetake)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use This Clip", action: onUseClip)
                    }
                }
        }
    }
}
