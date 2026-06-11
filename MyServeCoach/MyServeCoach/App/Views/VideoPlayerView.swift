import AVFoundation
import AVKit
import CoreMedia
import SwiftUI

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var currentTime: CMTime

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $currentTime)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        context.coordinator.startObserving(player: player)
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    final class Coordinator {
        private let binding: Binding<CMTime>
        private weak var player: AVPlayer?
        private var observerToken: Any?

        init(binding: Binding<CMTime>) {
            self.binding = binding
        }

        func startObserving(player: AVPlayer) {
            self.player = player
            let interval = CMTime(value: 1, timescale: 30)
            observerToken = player.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { [weak self] time in
                self?.binding.wrappedValue = time
            }
        }

        deinit {
            if let token = observerToken {
                player?.removeTimeObserver(token)
            }
        }
    }
}
