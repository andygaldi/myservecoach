import Foundation
import Testing
@testable import MyServeCoach

@Suite("ProServeAnalysisPipeline Tests")
struct ProServeAnalysisPipelineTests {

    // MARK: - Mocks

    private final class MockVideoSegmentationService: VideoSegmentationServiceProtocol, @unchecked Sendable {
        var segments: [ProServeSegment]
        var error: Error?

        init(segments: [ProServeSegment] = [], error: Error? = nil) {
            self.segments = segments
            self.error = error
        }

        func segmentVideo(at url: URL, sessionId: String?) async throws -> [ProServeSegment] {
            if let error { throw error }
            return segments
        }
    }

    private struct MockCoachingService: CoachingServiceProtocol {
        var resultsByCallIndex: [CoachingResult] = []
        var error: Error?
        let callCount = Counter()

        func analyze(frames: [BackendFrame], detections: [[BackendDetection]]?, sessionId: String?) async throws -> CoachingResult {
            let index = await callCount.incrementAndGet()
            if let error { throw error }
            return resultsByCallIndex[index]
        }
    }

    private actor Counter {
        private var value = 0
        func incrementAndGet() -> Int {
            defer { value += 1 }
            return value
        }
    }

    private enum MockError: Error { case failed }

    private func dummyVideoURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dummy-\(UUID().uuidString).mov")
    }

    // MARK: - Tests

    @Test("orders results by segment index")
    func ordersResultsBySegmentIndex() async throws {
        let poseFrames = [BackendFrame(timestamp: 0.0, keypoints: [:]), BackendFrame(timestamp: 0.1, keypoints: [:])]
        let pipeline = ProServeAnalysisPipeline(
            videoSegmentationService: MockVideoSegmentationService(segments: [
                ProServeSegment(frames: [poseFrames[0]], detections: nil),
                ProServeSegment(frames: [poseFrames[1]], detections: nil),
            ]),
            coachingService: MockCoachingService(resultsByCallIndex: [
                CoachingResult(cues: [], summary: "serve 0"),
                CoachingResult(cues: [], summary: "serve 1"),
            ])
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        #expect(results.count == 2)
        #expect(results[0].serveIndex == 0)
        #expect(results[0].coaching.summary == "serve 0")
        #expect(results[1].serveIndex == 1)
        #expect(results[1].coaching.summary == "serve 1")
    }

    @Test("throws noSegmentsDetected when segmentation returns empty")
    func throwsNoSegmentsDetectedWhenSegmentationReturnsEmpty() async throws {
        let pipeline = ProServeAnalysisPipeline(
            videoSegmentationService: MockVideoSegmentationService(segments: []),
            coachingService: MockCoachingService(resultsByCallIndex: [])
        )

        await #expect(throws: ProServeAnalysisError.noSegmentsDetected) {
            _ = try await pipeline.analyze(videoURL: dummyVideoURL())
        }
    }

    @Test("propagates segmentation failure")
    func propagatesSegmentationFailure() async throws {
        let pipeline = ProServeAnalysisPipeline(
            videoSegmentationService: MockVideoSegmentationService(error: MockError.failed),
            coachingService: MockCoachingService()
        )

        await #expect(throws: MockError.self) {
            _ = try await pipeline.analyze(videoURL: dummyVideoURL())
        }
    }

    @Test("propagates analyze failure")
    func propagatesAnalyzeFailure() async throws {
        let frame = BackendFrame(timestamp: 0.0, keypoints: [:])
        let pipeline = ProServeAnalysisPipeline(
            videoSegmentationService: MockVideoSegmentationService(segments: [
                ProServeSegment(frames: [frame], detections: nil)
            ]),
            coachingService: MockCoachingService(error: MockError.failed)
        )

        await #expect(throws: MockError.self) {
            _ = try await pipeline.analyze(videoURL: dummyVideoURL())
        }
    }
}
