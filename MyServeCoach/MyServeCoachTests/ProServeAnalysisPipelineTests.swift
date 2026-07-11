import AVFoundation
import CoreVideo
import Testing
@testable import MyServeCoach

@Suite("ProServeAnalysisPipeline Tests")
struct ProServeAnalysisPipelineTests {

    // MARK: - Mocks

    private struct MockPoseUploadService: PoseUploadServiceProtocol {
        var frames: [BackendFrame] = []
        var error: Error?
        func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendFrame] {
            if let error { throw error }
            return self.frames
        }
    }

    private struct MockObjectDetectionUploadService: ObjectDetectionUploadServiceProtocol {
        var frames: [BackendDetectionFrame] = []
        var error: Error?
        func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendDetectionFrame] {
            if let error { throw error }
            return self.frames
        }
    }

    private final class MockServeSegmentationUploadService: ServeSegmentationUploadServiceProtocol, @unchecked Sendable {
        var segments: [ProServeSegment]
        var error: Error?
        private(set) var lastReceivedDetections: [[BackendDetection]]?
        private(set) var lastReceivedFrames: [BackendFrame]?

        init(segments: [ProServeSegment] = [], error: Error? = nil) {
            self.segments = segments
            self.error = error
        }

        func segment(frames: [BackendFrame], detections: [[BackendDetection]]?, sessionId: String?) async throws -> [ProServeSegment] {
            lastReceivedFrames = frames
            lastReceivedDetections = detections
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

    // MARK: - Fixture video

    private func makeTestVideo(frameCount: Int = 6, frameRate: Float = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 32,
            AVVideoHeightKey: 32
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 32 as Int,
                kCVPixelBufferHeightKey as String: 32 as Int
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let timeScale = CMTimeScale(frameRate)
        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pb)
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: timeScale))
        }

        input.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        return url
    }

    // MARK: - Tests

    @Test("orders results by segment index")
    func ordersResultsBySegmentIndex() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        let poseFrames = [BackendFrame(timestamp: 0.0, keypoints: [:]), BackendFrame(timestamp: 0.1, keypoints: [:])]
        let pipeline = ProServeAnalysisPipeline(
            poseUploader: MockPoseUploadService(frames: poseFrames),
            detectionUploader: MockObjectDetectionUploadService(frames: []),
            segmentationUploader: MockServeSegmentationUploadService(segments: [
                ProServeSegment(frames: [poseFrames[0]], detections: nil),
                ProServeSegment(frames: [poseFrames[1]], detections: nil),
            ]),
            coachingService: MockCoachingService(resultsByCallIndex: [
                CoachingResult(cues: [], summary: "serve 0"),
                CoachingResult(cues: [], summary: "serve 1"),
            ])
        )

        let results = try await pipeline.analyze(videoURL: url)

        #expect(results.count == 2)
        #expect(results[0].serveIndex == 0)
        #expect(results[0].coaching.summary == "serve 0")
        #expect(results[1].serveIndex == 1)
        #expect(results[1].coaching.summary == "serve 1")
    }

    @Test("throws noSegmentsDetected when segmentation returns empty")
    func throwsNoSegmentsDetectedWhenSegmentationReturnsEmpty() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        let pipeline = ProServeAnalysisPipeline(
            poseUploader: MockPoseUploadService(frames: []),
            detectionUploader: MockObjectDetectionUploadService(frames: []),
            segmentationUploader: MockServeSegmentationUploadService(segments: []),
            coachingService: MockCoachingService(resultsByCallIndex: [])
        )

        await #expect(throws: ProServeAnalysisError.noSegmentsDetected) {
            _ = try await pipeline.analyze(videoURL: url)
        }
    }

    @Test("propagates pose upload failure")
    func propagatesPoseUploadFailure() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        let pipeline = ProServeAnalysisPipeline(
            poseUploader: MockPoseUploadService(error: MockError.failed),
            detectionUploader: MockObjectDetectionUploadService(frames: []),
            segmentationUploader: MockServeSegmentationUploadService(),
            coachingService: MockCoachingService()
        )

        await #expect(throws: MockError.self) {
            _ = try await pipeline.analyze(videoURL: url)
        }
    }

    @Test("propagates detection upload failure")
    func propagatesDetectionUploadFailure() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        let pipeline = ProServeAnalysisPipeline(
            poseUploader: MockPoseUploadService(frames: []),
            detectionUploader: MockObjectDetectionUploadService(error: MockError.failed),
            segmentationUploader: MockServeSegmentationUploadService(),
            coachingService: MockCoachingService()
        )

        await #expect(throws: MockError.self) {
            _ = try await pipeline.analyze(videoURL: url)
        }
    }

    @Test("propagates segmentation failure")
    func propagatesSegmentationFailure() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        let segmentationMock = MockServeSegmentationUploadService()
        segmentationMock.error = MockError.failed
        let pipeline = ProServeAnalysisPipeline(
            poseUploader: MockPoseUploadService(frames: []),
            detectionUploader: MockObjectDetectionUploadService(frames: []),
            segmentationUploader: segmentationMock,
            coachingService: MockCoachingService()
        )

        await #expect(throws: MockError.self) {
            _ = try await pipeline.analyze(videoURL: url)
        }
    }

    @Test("propagates analyze failure")
    func propagatesAnalyzeFailure() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        let frame = BackendFrame(timestamp: 0.0, keypoints: [:])
        let pipeline = ProServeAnalysisPipeline(
            poseUploader: MockPoseUploadService(frames: [frame]),
            detectionUploader: MockObjectDetectionUploadService(frames: []),
            segmentationUploader: MockServeSegmentationUploadService(segments: [
                ProServeSegment(frames: [frame], detections: nil)
            ]),
            coachingService: MockCoachingService(error: MockError.failed)
        )

        await #expect(throws: MockError.self) {
            _ = try await pipeline.analyze(videoURL: url)
        }
    }

    @Test("aligns detections to frames by timestamp before passing to segmentation, not array position")
    func passesDetectionsAlignedByTimestampToSegmentation() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        // Pose frames in one order; detection frames returned in a different order and missing
        // one timestamp entirely — the pipeline must align by timestamp, not position.
        let poseFrames = [
            BackendFrame(timestamp: 0.0, keypoints: [:]),
            BackendFrame(timestamp: 0.1, keypoints: [:]),
            BackendFrame(timestamp: 0.2, keypoints: [:]),
        ]
        let ballDetection = BackendDetection(
            label: "ball", confidence: 0.9, bbox: BackendBoundingBox(xMin: 0, yMin: 0, xMax: 1, yMax: 1)
        )
        let detectionFrames = [
            BackendDetectionFrame(timestamp: 0.2, detections: [ballDetection]),
            BackendDetectionFrame(timestamp: 0.0, detections: []),
            // 0.1 intentionally missing.
        ]

        let segmentationMock = MockServeSegmentationUploadService()
        segmentationMock.segments = [ProServeSegment(frames: poseFrames, detections: nil)]

        let pipeline = ProServeAnalysisPipeline(
            poseUploader: MockPoseUploadService(frames: poseFrames),
            detectionUploader: MockObjectDetectionUploadService(frames: detectionFrames),
            segmentationUploader: segmentationMock,
            coachingService: MockCoachingService(resultsByCallIndex: [CoachingResult(cues: [], summary: nil)])
        )

        _ = try await pipeline.analyze(videoURL: url)

        let received = try #require(segmentationMock.lastReceivedDetections)
        #expect(received.count == 3)
        #expect(received[0] == [])
        #expect(received[1] == [])
        #expect(received[2].first?.label == "ball")
    }
}
