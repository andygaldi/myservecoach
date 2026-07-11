import Foundation

struct BackendDetectionFrame: Decodable, Sendable {
    let timestamp: Double
    let detections: [BackendDetection]
}

protocol ObjectDetectionUploadServiceProtocol {
    func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendDetectionFrame]
}

/// URLSession-backed client for the backend's `POST /v1/detect` — racket/ball object detection
/// for Pro 2D mode. First caller lands in Phase P6.
final class LiveObjectDetectionUploadService: ObjectDetectionUploadServiceProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = MultipartFormEncoder()

    init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendDetectionFrame] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/detect"))
        request.httpMethod = "POST"
        request.setValue(encoder.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = encoder.encodeFrames(frames, sessionId: sessionId)

        struct DetectResponseBody: Decodable { let frames: [BackendDetectionFrame] }
        let body: DetectResponseBody = try await sendAndDecode(request, session: session)
        return body.frames
    }
}
