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

    /// Returns canned JPEG data for every requested timestamp, or throws — so the pipeline's
    /// extraction handling can be exercised without a real asset on disk.
    private struct MockImageProvider: PhaseFrameImageProviding {
        var error: Error?
        var missingTimestamps: Set<Double> = []

        func imageData(at seconds: [Double], from videoURL: URL) async throws -> [Double: Data] {
            if let error { throw error }
            // Tolerates a repeated timestamp the way the real extractor does — it keys results by
            // requested time, so asking twice is harmless rather than fatal.
            var result: [Double: Data] = [:]
            for second in seconds where !missingTimestamps.contains(second) {
                result[second] = Data("jpeg-\(second)".utf8)
            }
            return result
        }
    }

    private enum MockError: Error { case failed }

    private func dummyVideoURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dummy-\(UUID().uuidString).mov")
    }

    private func frames(count: Int) -> [BackendFrame] {
        (0..<count).map { BackendFrame(timestamp: Double($0) / 10.0, keypoints: [
            "left_wrist": BackendKeypoint(x: Float($0) / 100.0, y: 0.5, confidence: 0.9)
        ]) }
    }

    private func detections(count: Int) -> [[BackendDetection]] {
        (0..<count).map { i in
            [BackendDetection(label: "ball", confidence: 0.9, bbox: BackendBoundingBox(
                xMin: Float(i) / 100.0, yMin: 0.1, xMax: 0.2, yMax: 0.2
            ))]
        }
    }

    private func phase(_ name: String, _ index: Int) -> PhaseDetection {
        PhaseDetection(phase: name, frameIndex: index, timestamp: Double(index) / 10.0)
    }

    private func allSixPhases() -> [PhaseDetection] {
        [phase("start", 0), phase("release", 1), phase("trophy_pose", 2),
         phase("racket_drop", 3), phase("contact", 4), phase("finish", 5)]
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

    // MARK: - Phase frame retention (P6c)

    private func makePipeline(
        segments: [ProServeSegment],
        results: [CoachingResult],
        imageProvider: MockImageProvider = MockImageProvider()
    ) -> ProServeAnalysisPipeline {
        ProServeAnalysisPipeline(
            videoSegmentationService: MockVideoSegmentationService(segments: segments),
            coachingService: MockCoachingService(resultsByCallIndex: results),
            imageProvider: imageProvider
        )
    }

    @Test("retains only the four displayed phases, skipping start and finish")
    func retainsOnlyDisplayedPhases() async throws {
        let pipeline = makePipeline(
            segments: [ProServeSegment(frames: frames(count: 6), detections: detections(count: 6))],
            results: [CoachingResult(cues: [], summary: nil, phases: allSixPhases())]
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        #expect(results[0].phaseFrames.map(\.phase) == ["release", "trophy_pose", "racket_drop", "contact"])
    }

    @Test("retains phase frames for a serve with zero cues")
    func retainsFramesForCleanServe() async throws {
        let pipeline = makePipeline(
            segments: [ProServeSegment(frames: frames(count: 6), detections: detections(count: 6))],
            results: [CoachingResult(cues: [], summary: "No major issues detected — good serve!", phases: allSixPhases())]
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        #expect(results[0].coaching.cues.isEmpty)
        #expect(results[0].phaseFrames.count == 4)
    }

    @Test("phase frame carries the keypoints and detections at the reported frame index")
    func phaseFrameCarriesKeypointsAndDetectionsAtIndex() async throws {
        let segmentFrames = frames(count: 6)
        let segmentDetections = detections(count: 6)
        let pipeline = makePipeline(
            segments: [ProServeSegment(frames: segmentFrames, detections: segmentDetections)],
            results: [CoachingResult(cues: [], summary: nil, phases: allSixPhases())]
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        let trophy = try #require(results[0].phaseFrames.first { $0.phase == "trophy_pose" })
        // allSixPhases() puts trophy_pose at frame index 2.
        #expect(trophy.timestamp == segmentFrames[2].timestamp)
        #expect(trophy.frame.keypoints["left_wrist"]?.x == segmentFrames[2].keypoints["left_wrist"]?.x)
        #expect(trophy.detections == segmentDetections[2])
    }

    @Test("an out-of-range frame index is skipped, not fatal")
    func outOfRangeFrameIndexIsSkipped() async throws {
        let pipeline = makePipeline(
            segments: [ProServeSegment(frames: frames(count: 3), detections: nil)],
            results: [CoachingResult(cues: [], summary: nil, phases: [
                phase("release", 1),
                phase("trophy_pose", 99),  // past the end of a 3-frame segment
                phase("contact", 2),
            ])]
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        #expect(results.count == 1)
        #expect(results[0].phaseFrames.map(\.phase) == ["release", "contact"])
    }

    @Test("a segment with no detections yields phase frames with empty detections")
    func missingDetectionsYieldEmptyArray() async throws {
        let pipeline = makePipeline(
            segments: [ProServeSegment(frames: frames(count: 6), detections: nil)],
            results: [CoachingResult(cues: [], summary: nil, phases: allSixPhases())]
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        let detectionCounts = results[0].phaseFrames.map(\.detections.count)
        #expect(results[0].phaseFrames.count == 4)
        #expect(detectionCounts == [0, 0, 0, 0])
    }

    @Test("image extraction failure leaves cues intact")
    func imageExtractionFailureLeavesCuesIntact() async throws {
        let cue = Cue(ruleId: "trophy_toss_arm_vertical", phase: "trophy_pose", message: "Keep it vertical.", severity: "major")
        let pipeline = makePipeline(
            segments: [ProServeSegment(frames: frames(count: 6), detections: detections(count: 6))],
            results: [CoachingResult(cues: [cue], summary: nil, phases: allSixPhases())],
            imageProvider: MockImageProvider(error: MockError.failed)
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        #expect(results.count == 1)
        #expect(results[0].coaching.cues.count == 1)
        #expect(results[0].coaching.cues[0].ruleId == "trophy_toss_arm_vertical")
        #expect(results[0].phaseFrames.isEmpty)
    }

    @Test("a phase whose individual frame could not be extracted is dropped, others kept")
    func individuallyMissingImageIsDropped() async throws {
        let pipeline = makePipeline(
            segments: [ProServeSegment(frames: frames(count: 6), detections: detections(count: 6))],
            results: [CoachingResult(cues: [], summary: nil, phases: allSixPhases())],
            // trophy_pose sits at frame index 2 → timestamp 0.2
            imageProvider: MockImageProvider(missingTimestamps: [0.2])
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        #expect(results[0].phaseFrames.map(\.phase) == ["release", "racket_drop", "contact"])
    }

    @Test("phase frames are attributed to the correct serve across multiple segments")
    func phaseFramesAttributedPerServe() async throws {
        let pipeline = makePipeline(
            segments: [
                ProServeSegment(frames: frames(count: 6), detections: nil),
                ProServeSegment(frames: frames(count: 6), detections: nil),
            ],
            results: [
                CoachingResult(cues: [], summary: "serve 0", phases: [phase("release", 1), phase("contact", 4)]),
                CoachingResult(cues: [], summary: "serve 1", phases: allSixPhases()),
            ]
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        #expect(results[0].phaseFrames.map(\.phase) == ["release", "contact"])
        #expect(results[1].phaseFrames.count == 4)
    }

    @Test("a pre-P6c response with no phases yields no phase frames but keeps cues")
    func responseWithoutPhasesYieldsNoFrames() async throws {
        let cue = Cue(ruleId: "contact_shoulders_stacked", phase: "contact", message: "Stack them.", severity: "major")
        let pipeline = makePipeline(
            segments: [ProServeSegment(frames: frames(count: 6), detections: nil)],
            results: [CoachingResult(cues: [cue], summary: nil)]
        )

        let results = try await pipeline.analyze(videoURL: dummyVideoURL())

        #expect(results[0].phaseFrames.isEmpty)
        #expect(results[0].coaching.cues.count == 1)
    }
}
