import AVFoundation
import CoreGraphics

final class FrameSamplerService {

    /// Samples frames from `asset` at every `kPoseSampleStride`-th frame position.
    /// Returns frames in presentation order. Tolerances are set to zero so the
    /// generator returns the exact frame closest to each requested time.
    func sampleFrames(from asset: AVAsset) async throws -> [(time: CMTime, image: CGImage)] {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw FrameSamplerError.noVideoTrack
        }

        let frameRate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let totalFrames = Int(durationSeconds * Double(frameRate))

        let sampleTimes: [CMTime] = stride(
            from: 0,
            to: totalFrames,
            by: PoseConstants.kPoseSampleStride
        ).map { frameIndex in
            CMTimeMakeWithSeconds(Double(frameIndex) / Double(frameRate), preferredTimescale: 600)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var results: [(time: CMTime, image: CGImage)] = []
        results.reserveCapacity(sampleTimes.count)
        for requestedTime in sampleTimes {
            let (cgImage, actualTime) = try await generator.image(at: requestedTime)
            results.append((time: actualTime, image: cgImage))
        }
        return results
    }
}

enum FrameSamplerError: Error {
    case noVideoTrack
}
