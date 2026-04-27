import AVFoundation
import CoreGraphics

final class FrameSamplerService {

    /// Returns a configured image generator and the ordered list of sample times for `asset`.
    /// Callers that need all frames at once should use `sampleFrames(from:)` instead; callers
    /// that process frames one at a time (to avoid holding all CGImages in memory) should call
    /// this and drive the generator loop themselves.
    func makeSampler(for asset: AVAsset) async throws -> (generator: AVAssetImageGenerator, times: [CMTime]) {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw FrameSamplerError.noVideoTrack
        }

        let frameRate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let totalFrames = Int(durationSeconds * Double(frameRate))

        let times: [CMTime] = stride(from: 0, to: totalFrames, by: PoseConstants.kPoseSampleStride)
            .map { CMTimeMakeWithSeconds(Double($0) / Double(frameRate), preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        return (generator, times)
    }

    /// Samples frames from `asset` at every `kPoseSampleStride`-th frame position.
    /// Returns frames in presentation order. Only use this when all images must be in
    /// memory simultaneously — for long recordings prefer `makeSampler(for:)` with a
    /// streaming loop so each CGImage is released after use.
    func sampleFrames(from asset: AVAsset) async throws -> [(time: CMTime, image: CGImage)] {
        let (generator, times) = try await makeSampler(for: asset)
        var results: [(time: CMTime, image: CGImage)] = []
        results.reserveCapacity(times.count)
        for requestedTime in times {
            let (cgImage, actualTime) = try await generator.image(at: requestedTime)
            results.append((time: actualTime, image: cgImage))
        }
        return results
    }
}

enum FrameSamplerError: Error {
    case noVideoTrack
}
