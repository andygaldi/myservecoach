import Foundation

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

/// Off-device Pro 2D pipeline: uploads the clip's raw video file for server-side frame
/// extraction + pose + object-detection + segmentation, then analyzes each returned segment —
/// the Pro counterpart to Lite's on-device `PoseAnalysisPipeline`. First built in Phase P6;
/// revised from an on-device frame-sampling + per-frame-upload design to server-side video
/// extraction after real-device testing found the on-device AVFoundation/UIKit JPEG pipeline
/// wasn't pixel-equivalent enough to reliably match `segment_serves`'s tuning (see
/// requirements.md's "server-side extraction pivot" Key Decision).
actor ProServeAnalysisPipeline: ProServeAnalyzing {
    private let videoSegmentationService: any VideoSegmentationServiceProtocol
    private let coachingService: any CoachingServiceProtocol

    init(
        videoSegmentationService: any VideoSegmentationServiceProtocol = LiveVideoSegmentationService(),
        coachingService: any CoachingServiceProtocol = LiveCoachingService()
    ) {
        self.videoSegmentationService = videoSegmentationService
        self.coachingService = coachingService
    }

    func analyze(videoURL: URL) async throws -> [AssessmentServeResult] {
        let segments = try await videoSegmentationService.segmentVideo(at: videoURL, sessionId: nil)
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
}
