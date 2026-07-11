import Foundation
import Testing
@testable import MyServeCoach

@Suite("LiveCoachingService Request Encoding Tests")
struct CoachingServiceRequestEncodingTests {

    private func makeService() -> (service: LiveCoachingService, baseURL: URL) {
        let baseURL = StubURLProtocol.uniqueBaseURL()
        StubURLProtocol.setStub(
            .init(statusCode: 200, data: Data("""
            { "cues": [], "summary": null }
            """.utf8)),
            for: baseURL
        )
        let service = LiveCoachingService(baseURL: baseURL, session: StubURLProtocol.makeSession())
        return (service, baseURL)
    }

    private func decodeBody(for baseURL: URL) throws -> [String: Any] {
        let body = try #require(StubURLProtocol.lastBody(for: baseURL))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        return try #require(json)
    }

    @Test("request body includes frames, detections, session_id keys when all are non-nil")
    func requestBodyHasExpectedKeys() async throws {
        let (service, baseURL) = makeService()
        let frame = BackendFrame(timestamp: 0.1, keypoints: [:])
        _ = try await service.analyze(frames: [frame], detections: [[]], sessionId: "abc")

        let json = try decodeBody(for: baseURL)
        #expect(Set(json.keys) == ["frames", "detections", "session_id"])
    }

    @Test("nil detections and session_id are omitted from the request body (Codable's encodeIfPresent) — Pydantic's Optional defaults accept a missing key identically to an explicit null")
    func nilDetectionsOmitsKey() async throws {
        let (service, baseURL) = makeService()
        let frame = BackendFrame(timestamp: 0.1, keypoints: [:])
        _ = try await service.analyze(frames: [frame], detections: nil, sessionId: nil)

        let json = try decodeBody(for: baseURL)
        #expect(Set(json.keys) == ["frames"])
    }

    @Test("non-nil detections are encoded and round-trip in the request body")
    func nonNilDetectionsEncoded() async throws {
        let (service, baseURL) = makeService()
        let frame = BackendFrame(timestamp: 0.1, keypoints: [:])
        let detection = BackendDetection(
            label: "ball", confidence: 0.9,
            bbox: BackendBoundingBox(xMin: 0.1, yMin: 0.2, xMax: 0.3, yMax: 0.4)
        )
        _ = try await service.analyze(frames: [frame], detections: [[detection]], sessionId: nil)

        let json = try decodeBody(for: baseURL)
        let detections = try #require(json["detections"] as? [[[String: Any]]])
        #expect(detections.count == 1)
        #expect(detections[0].count == 1)
        #expect(detections[0][0]["label"] as? String == "ball")
    }
}
