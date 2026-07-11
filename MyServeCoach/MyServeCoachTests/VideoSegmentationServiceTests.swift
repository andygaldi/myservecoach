import Foundation
import Testing
@testable import MyServeCoach

@Suite("LiveVideoSegmentationService Tests")
struct VideoSegmentationServiceTests {

    private func makeService(stub: StubURLProtocol.Stub) -> LiveVideoSegmentationService {
        let baseURL = StubURLProtocol.uniqueBaseURL()
        StubURLProtocol.setStub(stub, for: baseURL)
        return LiveVideoSegmentationService(baseURL: baseURL, session: StubURLProtocol.makeSession())
    }

    // upload(for:fromFile:) needs a real file on disk — content is irrelevant since the network
    // layer is fully mocked via StubURLProtocol; only the response side is under test here.
    private func makeDummyVideoFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")
        try Data("dummy video bytes".utf8).write(to: url)
        return url
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
        let videoURL = try makeDummyVideoFile()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let segments = try await service.segmentVideo(at: videoURL, sessionId: nil)

        #expect(segments.count == 2)
        #expect(segments[0].detections == nil)
        #expect(segments[1].detections?.count == 1)
    }

    @Test("throws networkError on a non-2xx status")
    func throwsOnNonSuccessStatus() async throws {
        let service = makeService(stub: .init(statusCode: 500, data: Data()))
        let videoURL = try makeDummyVideoFile()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        await #expect(throws: ProUploadError.self) {
            _ = try await service.segmentVideo(at: videoURL, sessionId: nil)
        }
    }

    @Test("propagates a decoding error on malformed JSON")
    func propagatesDecodingErrorOnMalformedJSON() async throws {
        let service = makeService(stub: .init(statusCode: 200, data: Data("not json".utf8)))
        let videoURL = try makeDummyVideoFile()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        await #expect(throws: (any Error).self) {
            _ = try await service.segmentVideo(at: videoURL, sessionId: nil)
        }
    }
}
