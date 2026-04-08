import Foundation
import Observation
import SwiftData

@Observable
final class RecordServeViewModel {
    // MARK: - State

    var isRecording: Bool = false
    var isProcessing: Bool = false
    var recordingError: String?

    // MARK: - Dependencies

    private let videoService: VideoServiceProtocol
    private let poseService: PoseServiceProtocol
    private let coachingService: CoachingServiceProtocol

    // MARK: - Init

    init(
        videoService: VideoServiceProtocol = LiveVideoService(),
        poseService: PoseServiceProtocol = LivePoseService(),
        coachingService: CoachingServiceProtocol = LiveCoachingService()
    ) {
        self.videoService = videoService
        self.poseService = poseService
        self.coachingService = coachingService
    }

    // MARK: - Actions

    func startRecording() {
        recordingError = nil
        do {
            try videoService.startRecording()
            isRecording = true
        } catch {
            recordingError = error.localizedDescription
        }
    }

    /// Stops recording, runs the full analysis pipeline, and persists the result.
    /// ModelContext is passed per-call rather than stored to avoid threading issues.
    func stopRecording(context: ModelContext) {
        isRecording = false
        isProcessing = true
        Task {
            do {
                let videoURL = try await videoService.stopRecording()
                let frames = try await poseService.extractPoses(
                    from: videoURL,
                    confidenceThreshold: 0.75
                )
                let keypointsData = try JSONEncoder().encode(frames)
                let keypointsJSON = String(data: keypointsData, encoding: .utf8) ?? ""
                let result = try await coachingService.analyze(keypointsJSON: keypointsJSON)
                let serve = Serve(
                    videoURL: videoURL,
                    keypointsJSON: keypointsJSON,
                    coachingCues: result.cues,
                    analysisStatus: .complete
                )
                context.insert(serve)
                try context.save()
            } catch {
                recordingError = error.localizedDescription
            }
            isProcessing = false
        }
    }
}
