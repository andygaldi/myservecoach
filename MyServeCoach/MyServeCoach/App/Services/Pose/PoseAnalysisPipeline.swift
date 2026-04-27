import AVFoundation
import Foundation

actor PoseAnalysisPipeline {
    private let sampler: FrameSamplerService
    private let estimator: PoseEstimationService
    private let segmenter: ServeSegmentationService
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    init(
        sampler: FrameSamplerService = FrameSamplerService(),
        estimator: PoseEstimationService = PoseEstimationService(),
        segmenter: ServeSegmentationService = ServeSegmentationService()
    ) {
        self.sampler = sampler
        self.estimator = estimator
        self.segmenter = segmenter
    }

    func analyze(videoURL: URL) async throws -> [[PoseFrame]] {
        let asset = AVURLAsset(url: videoURL)
        let (generator, sampleTimes) = try await sampler.makeSampler(for: asset)

        // Process one frame at a time so each CGImage is released immediately after
        // pose estimation rather than holding the full video in memory.
        var poses = [PoseFrame]()
        poses.reserveCapacity(sampleTimes.count)
        for requestedTime in sampleTimes {
            guard let (image, actualTime) = try? await generator.image(at: requestedTime) else { continue }
            if let frame = estimator.detectPose(at: actualTime, in: image) {
                poses.append(frame)
            }
        }

        let segments = segmenter.segment(frames: poses)
        logSegments(segments)
        return segments
    }

    private func logSegments(_ segments: [[PoseFrame]]) {
        for (i, segment) in segments.enumerated() {
            print("[MyServeCoach] Serve \(i + 1)/\(segments.count) \u{2014} \(segment.count) frames")
            for frame in segment {
                if let data = try? encoder.encode(frame),
                   let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
            }
        }
    }
}
