import AVFoundation
import UIKit

enum ProPoseConstants {
    /// P4b validated stride 2 against real footage for the off-device pose+detection pipeline —
    /// denser than Lite's Vision-tuned PoseConstants.kPoseSampleStride (3), specifically so a
    /// fast swing's Cocking->Contact motion can't fall entirely between two sampled frames.
    static let kStride: Int = 2

    /// JPEG quality for uploaded frames. A real-device smoke test on a 3-serve clip found that
    /// 0.85 introduces enough compression noise into RTMPose's keypoints during quiet (rest)
    /// periods to keep `_frame_velocity` above `segment_serves`'s rest-gap threshold, silently
    /// merging two serves into one segment (confirmed via a diagnostic sweep: quality 0.85 → 2
    /// segments instead of 3; 0.92/0.95/0.98 all correctly produced 3, matching the uncompressed
    /// baseline almost exactly). 0.95 keeps a comfortable margin above the observed 0.92 minimum.
    static let kJPEGQuality: CGFloat = 0.95
}

struct AssessmentServeResult: Sendable {
    let serveIndex: Int
    let coaching: CoachingResult
}

protocol ProServeAnalyzing: Sendable {
    func analyze(videoURL: URL) async throws -> [AssessmentServeResult]
}

enum ProServeAnalysisError: Error, Equatable {
    case noSegmentsDetected
}

/// Off-device Pro 2D pipeline: samples a clip's frames, uploads them for pose+object-detection
/// inference, splits the result into per-serve segments, and analyzes each segment — the Pro
/// counterpart to Lite's on-device `PoseAnalysisPipeline`. First built in Phase P6.
actor ProServeAnalysisPipeline: ProServeAnalyzing {
    private let sampler: FrameSamplerService
    private let poseUploader: any PoseUploadServiceProtocol
    private let detectionUploader: any ObjectDetectionUploadServiceProtocol
    private let segmentationUploader: any ServeSegmentationUploadServiceProtocol
    private let coachingService: any CoachingServiceProtocol

    init(
        sampler: FrameSamplerService = FrameSamplerService(),
        poseUploader: any PoseUploadServiceProtocol = LivePoseUploadService(),
        detectionUploader: any ObjectDetectionUploadServiceProtocol = LiveObjectDetectionUploadService(),
        segmentationUploader: any ServeSegmentationUploadServiceProtocol = LiveServeSegmentationUploadService(),
        coachingService: any CoachingServiceProtocol = LiveCoachingService()
    ) {
        self.sampler = sampler
        self.poseUploader = poseUploader
        self.detectionUploader = detectionUploader
        self.segmentationUploader = segmentationUploader
        self.coachingService = coachingService
    }

    func analyze(videoURL: URL) async throws -> [AssessmentServeResult] {
        let asset = AVURLAsset(url: videoURL)
        let (generator, sampleTimes) = try await sampler.makeSampler(for: asset, stride: ProPoseConstants.kStride)

        // Process one frame at a time so each CGImage is released immediately after JPEG
        // encoding, rather than holding every sampled frame of the whole clip in memory at
        // once (a real OOM risk on-device for longer, multi-serve continuous recordings — see
        // FrameSamplerService.sampleFrames's own warning; mirrors PoseAnalysisPipeline's
        // equivalent streaming loop for the Lite pipeline).
        var jpegFrames: [(timestamp: Double, jpegData: Data)] = []
        jpegFrames.reserveCapacity(sampleTimes.count)
        for requestedTime in sampleTimes {
            guard let (image, actualTime) = try? await generator.image(at: requestedTime) else { continue }
            jpegFrames.append((timestamp: CMTimeGetSeconds(actualTime), jpegData: Self.jpegData(from: image)))
        }

        async let poseFramesTask = poseUploader.infer(frames: jpegFrames, sessionId: nil)
        async let detectionFramesTask = detectionUploader.infer(frames: jpegFrames, sessionId: nil)
        let (frames, detectionFrames) = try await (poseFramesTask, detectionFramesTask)

        let detectionsByTimestamp = Dictionary(
            detectionFrames.map { ($0.timestamp, $0.detections) },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedDetections = frames.map { detectionsByTimestamp[$0.timestamp] ?? [] }

        let segments = try await segmentationUploader.segment(
            frames: frames, detections: orderedDetections, sessionId: nil
        )
        guard !segments.isEmpty else {
            throw ProServeAnalysisError.noSegmentsDetected
        }

        var results: [AssessmentServeResult] = []
        results.reserveCapacity(segments.count)
        for (index, segment) in segments.enumerated() {
            let coaching = try await coachingService.analyze(
                frames: segment.frames, detections: segment.detections, sessionId: nil
            )
            results.append(AssessmentServeResult(serveIndex: index, coaching: coaching))
        }
        return results
    }

    private static func jpegData(from image: CGImage) -> Data {
        UIImage(cgImage: image).jpegData(compressionQuality: ProPoseConstants.kJPEGQuality) ?? Data()
    }
}
