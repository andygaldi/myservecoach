import Foundation
import Testing
import SwiftData
@testable import MyServeCoach

// MARK: - Serve Model Tests

@Suite("Serve Model Tests")
struct ServeModelTests {

    @Test("Serve initializes with default values")
    func serveDefaultInit() throws {
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        let serve = Serve(videoURL: url)

        #expect(serve.coachingCues.isEmpty)
        #expect(serve.analysisStatus == .pending)
        #expect(serve.keypointsJSON == nil)
    }
}

// MARK: - RecordServeViewModel Tests

@Suite("RecordServeViewModel Tests")
struct RecordServeViewModelTests {

    @Test("ViewModel starts not recording")
    func initialState() {
        let vm = RecordServeViewModel(
            videoService: MockVideoService(),
            poseService: MockPoseService(),
            coachingService: MockCoachingService()
        )
        #expect(vm.isRecording == false)
        #expect(vm.isProcessing == false)
        #expect(vm.recordingError == nil)
    }
}

// MARK: - Mocks

final class MockVideoService: VideoServiceProtocol {
    private(set) var isRecording: Bool = false
    func startRecording() throws { isRecording = true }
    func stopRecording() async throws -> URL { URL(fileURLWithPath: "/tmp/mock.mp4") }
}

final class MockPoseService: PoseServiceProtocol {
    func extractPoses(from videoURL: URL, confidenceThreshold: Float) async throws -> [PoseFrame] { [] }
}

final class MockCoachingService: CoachingServiceProtocol {
    func analyze(keypointsJSON: String) async throws -> CoachingResult {
        CoachingResult(cues: ["Good trophy pose"], keyframeTimestamps: [:])
    }
}
