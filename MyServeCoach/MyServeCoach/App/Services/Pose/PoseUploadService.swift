import Foundation

protocol PoseUploadServiceProtocol {
    func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendFrame]
}

/// URLSession-backed client for the backend's `POST /v1/pose` — the off-device pose model that
/// replaces on-device Vision for Pro 2D mode. First caller lands in Phase P6.
final class LivePoseUploadService: PoseUploadServiceProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = MultipartFormEncoder()

    init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendFrame] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/pose"))
        request.httpMethod = "POST"
        request.setValue(encoder.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = encoder.encodeFrames(frames, sessionId: sessionId)

        struct PoseResponseBody: Decodable { let frames: [BackendFrame] }
        let body: PoseResponseBody = try await sendAndDecode(request, session: session)
        return body.frames
    }
}
