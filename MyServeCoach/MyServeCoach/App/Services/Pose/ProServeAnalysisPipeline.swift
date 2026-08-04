import Foundation

struct AssessmentServeResult: Sendable {
    let serveIndex: Int
    let coaching: CoachingResult
    /// The four coaching-relevant phase frames for this serve (P6c), in
    /// `AssessmentPhaseConstants.displayedPhases` order. Empty when frame extraction failed —
    /// cues are still valid without imagery.
    let phaseFrames: [AssessmentPhaseFrame]

    init(serveIndex: Int, coaching: CoachingResult, phaseFrames: [AssessmentPhaseFrame] = []) {
        self.serveIndex = serveIndex
        self.coaching = coaching
        self.phaseFrames = phaseFrames
    }
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
    private let imageProvider: any PhaseFrameImageProviding

    init(
        videoSegmentationService: any VideoSegmentationServiceProtocol = LiveVideoSegmentationService(),
        coachingService: any CoachingServiceProtocol = LiveCoachingService(),
        imageProvider: any PhaseFrameImageProviding = PhaseFrameImageExtractor()
    ) {
        self.videoSegmentationService = videoSegmentationService
        self.coachingService = coachingService
        self.imageProvider = imageProvider
    }

    /// A phase frame resolved from the backend's response, before its image has been extracted.
    private struct PendingPhaseFrame {
        let serveIndex: Int
        let phase: String
        let timestamp: Double
        let frame: BackendFrame
        let detections: [BackendDetection]
    }

    func analyze(videoURL: URL) async throws -> [AssessmentServeResult] {
        let segments = try await videoSegmentationService.segmentVideo(at: videoURL, sessionId: nil)
        guard !segments.isEmpty else {
            throw ProServeAnalysisError.noSegmentsDetected
        }

        var coachingResults: [CoachingResult] = []
        var pending: [PendingPhaseFrame] = []
        coachingResults.reserveCapacity(segments.count)

        for (index, segment) in segments.enumerated() {
            let coaching = try await coachingService.analyze(
                frames: segment.frames, detections: segment.detections, sessionId: nil
            )
            coachingResults.append(coaching)
            pending += resolvePhaseFrames(from: coaching, in: segment, serveIndex: index)
        }

        // One batched extraction for the whole clip rather than one per phase per serve.
        // Best-effort: a failure here costs imagery, never the cues.
        var imagesByTimestamp: [Double: Data] = [:]
        if !pending.isEmpty {
            do {
                // Deduplicated: two serves reporting the same timestamp should cost one extraction.
                imagesByTimestamp = try await imageProvider.imageData(
                    at: Array(Set(pending.map(\.timestamp))), from: videoURL
                )
            } catch {
                print("[ProServeAnalysis] frame extraction failed: \(error)")
            }
        }

        return coachingResults.enumerated().map { index, coaching in
            let frames = pending
                .filter { $0.serveIndex == index }
                .compactMap { candidate -> AssessmentPhaseFrame? in
                    guard let imageData = imagesByTimestamp[candidate.timestamp] else { return nil }
                    return AssessmentPhaseFrame(
                        phase: candidate.phase,
                        timestamp: candidate.timestamp,
                        imageData: imageData,
                        frame: candidate.frame,
                        detections: candidate.detections
                    )
                }
            return AssessmentServeResult(serveIndex: index, coaching: coaching, phaseFrames: frames)
        }
    }

    /// Picks out the displayed phases the backend detected and joins each back to its keypoints
    /// and detections via the reported frame index.
    private func resolvePhaseFrames(
        from coaching: CoachingResult, in segment: ProServeSegment, serveIndex: Int
    ) -> [PendingPhaseFrame] {
        AssessmentPhaseConstants.displayedPhases.compactMap { phase in
            guard let detection = coaching.phases.first(where: { $0.phase == phase }) else { return nil }
            // A frame index outside the segment means the backend and client disagree about the
            // frame list — drop that phase rather than trapping on the subscript.
            guard segment.frames.indices.contains(detection.frameIndex) else {
                print("[ProServeAnalysis] phase \(phase) reported out-of-range index \(detection.frameIndex)")
                return nil
            }
            let detections = segment.detections.flatMap {
                $0.indices.contains(detection.frameIndex) ? $0[detection.frameIndex] : nil
            }
            let frame = segment.frames[detection.frameIndex]
            return PendingPhaseFrame(
                serveIndex: serveIndex,
                phase: phase,
                // Taken from the frame we're about to attach, not the echoed wire value, so the
                // image and its keypoints are joined by construction rather than by trusting the
                // backend to round-trip a float identically.
                timestamp: frame.timestamp,
                frame: frame,
                detections: detections ?? []
            )
        }
    }
}
