import Foundation
import Testing
@testable import MyServeCoach

@Suite("LiveObjectDetectionUploadService Tests")
struct ObjectDetectionUploadServiceTests {

    private func makeService(stub: StubURLProtocol.Stub) -> LiveObjectDetectionUploadService {
        let baseURL = StubURLProtocol.uniqueBaseURL()
        StubURLProtocol.setStub(stub, for: baseURL)
        return LiveObjectDetectionUploadService(baseURL: baseURL, session: StubURLProtocol.makeSession())
    }

    @Test("decodes a successful response into BackendDetectionFrame")
    func decodesSuccessResponse() async throws {
        let service = makeService(stub: .init(
            statusCode: 200,
            data: Data("""
            { "frames": [{ "timestamp": 0.1, "detections": [{ "label": "ball", "confidence": 0.9, "bbox": { "x_min": 0.1, "y_min": 0.2, "x_max": 0.3, "y_max": 0.4 } }] }] }
            """.utf8)
        ))
        let frames = try await service.infer(frames: [(timestamp: 0.1, jpegData: Data())], sessionId: nil)

        #expect(frames.count == 1)
        #expect(frames[0].timestamp == 0.1)
        #expect(frames[0].detections.count == 1)
        #expect(frames[0].detections[0].label == "ball")
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
