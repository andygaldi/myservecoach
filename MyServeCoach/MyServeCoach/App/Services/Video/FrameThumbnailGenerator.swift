import AVFoundation
import UIKit

struct FrameThumbnailGenerator {
    func thumbnail(at time: CMTime, for asset: AVAsset) async throws -> UIImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)

        let (cgImage, _) = try await generator.image(at: time)
        return UIImage(cgImage: cgImage)
    }
}
