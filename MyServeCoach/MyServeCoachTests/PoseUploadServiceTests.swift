import Foundation
import Testing
@testable import MyServeCoach

@Suite("LivePoseUploadService Tests")
struct PoseUploadServiceTests {

    private func makeService(stub: StubURLProtocol.Stub) -> LivePoseUploadService {
        let baseURL = StubURLProtocol.uniqueBaseURL()
        StubURLProtocol.setStub(stub, for: baseURL)
        return LivePoseUploadService(baseURL: baseURL, session: StubURLProtocol.makeSession())
    }

    @Test("decodes a successful response into BackendFrame")
    func decodesSuccessResponse() async throws {
        let service = makeService(stub: .init(
            statusCode: 200,
            data: Data("""
            { "frames": [{ "timestamp": 0.1, "keypoints": { "right_wrist": { "x": 0.5, "y": 0.5, "confidence": 0.9 } } }] }
            """.utf8)
        ))
        let frames = try await service.infer(frames: [(timestamp: 0.1, jpegData: Data())], sessionId: nil)

        #expect(frames.count == 1)
        #expect(frames[0].timestamp == 0.1)
        #expect(frames[0].keypoints["right_wrist"]?.x == 0.5)
    }

    @Test("throws networkError on a non-2xx status")
    func throwsOnNonSuccessStatus() async {
        let service = makeService(stub: .init(statusCode: 500, data: Data()))

        await #expect(throws: ProUploadError.self) {
            _ = try await service.infer(frames: [(timestamp: 0.1, jpegData: Data())], sessionId: nil)
        }
    }

    @Test("propagates a decoding error on malformed JSON")
    func propagatesDecodingErrorOnMalformedJSON() async {
        let service = makeService(stub: .init(statusCode: 200, data: Data("not json".utf8)))

        await #expect(throws: (any Error).self) {
            _ = try await service.infer(frames: [(timestamp: 0.1, jpegData: Data())], sessionId: nil)
        }
    }
}
