import Foundation
import Testing
@testable import MyServeCoach

@Suite("LiveServeSegmentationUploadService Tests")
struct ServeSegmentationUploadServiceTests {

    private func makeService(stub: StubURLProtocol.Stub) -> LiveServeSegmentationUploadService {
        let baseURL = StubURLProtocol.uniqueBaseURL()
        StubURLProtocol.setStub(stub, for: baseURL)
        return LiveServeSegmentationUploadService(baseURL: baseURL, session: StubURLProtocol.makeSession())
    }

    @Test("decodes a successful response into ProServeSegment list")
    func decodesSuccessResponse() async throws {
        let service = makeService(stub: .init(
            statusCode: 200,
            data: Data("""
            { "segments": [
                { "frames": [{ "timestamp": 0.1, "keypoints": {} }], "detections": null },
                { "frames": [{ "timestamp": 0.5, "keypoints": {} }], "detections": [[]] }
            ] }
            """.utf8)
        ))
        let frame = BackendFrame(timestamp: 0.1, keypoints: [:])
        let segments = try await service.segment(frames: [frame], detections: nil, sessionId: nil)

        #expect(segments.count == 2)
        #expect(segments[0].detections == nil)
        #expect(segments[1].detections?.count == 1)
    }

    @Test("throws networkError on a non-2xx status")
    func throwsOnNonSuccessStatus() async {
        let service = makeService(stub: .init(statusCode: 500, data: Data()))
        let frame = BackendFrame(timestamp: 0.1, keypoints: [:])

        await #expect(throws: ProUploadError.self) {
            _ = try await service.segment(frames: [frame], detections: nil, sessionId: nil)
        }
    }

    @Test("propagates a decoding error on malformed JSON")
    func propagatesDecodingErrorOnMalformedJSON() async {
        let service = makeService(stub: .init(statusCode: 200, data: Data("not json".utf8)))
        let frame = BackendFrame(timestamp: 0.1, keypoints: [:])

        await #expect(throws: (any Error).self) {
            _ = try await service.segment(frames: [frame], detections: nil, sessionId: nil)
        }
    }
}
