import Foundation

struct ProServeSegment: Decodable, Sendable {
    let frames: [BackendFrame]
    let detections: [[BackendDetection]]?
}

protocol ServeSegmentationUploadServiceProtocol {
    func segment(frames: [BackendFrame], detections: [[BackendDetection]]?, sessionId: String?) async throws -> [ProServeSegment]
}

/// URLSession-backed client for the backend's `POST /v1/segment` (Phase P6) — splits a
/// continuous multi-serve clip's frames into per-serve segments, ready to feed individually
/// into `CoachingServiceProtocol.analyze`.
final class LiveServeSegmentationUploadService: ServeSegmentationUploadServiceProtocol {
    private struct RequestBody: Encodable {
        let frames: [BackendFrame]
        let detections: [[BackendDetection]]?
        let sessionId: String?

        enum CodingKeys: String, CodingKey {
            case frames, detections
            case sessionId = "session_id"
        }
    }

    private struct SegmentResponseBody: Decodable {
        let segments: [ProServeSegment]
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func segment(frames: [BackendFrame], detections: [[BackendDetection]]?, sessionId: String?) async throws -> [ProServeSegment] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/segment"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(frames: frames, detections: detections, sessionId: sessionId)
        )

        let body: SegmentResponseBody = try await sendAndDecode(request, session: session)
        return body.segments
    }
}
