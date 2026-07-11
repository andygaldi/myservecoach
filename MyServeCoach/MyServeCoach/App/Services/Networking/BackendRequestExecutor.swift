import Foundation

enum ProUploadError: Error {
    case networkError(String)
}

/// `/v1/pose` and `/v1/detect` run real model inference (RTMPose / YOLO via ONNX Runtime)
/// sequentially over every sampled frame of the clip in a single request/response cycle — for a
/// multi-serve continuous recording that's easily hundreds of frames, plus a one-time cold-start
/// model-load cost on the backend's first call. `URLSession`'s default 60s request timeout is
/// comfortably exceeded by legitimate (successful, non-hung) requests at that scale; a real device
/// smoke test observed a 200 OK arrive from the backend after the client had already given up at
/// 60s. Generous but still bounded so a genuinely unreachable/hung backend fails visibly.
private let proRequestTimeout: TimeInterval = 180

/// Sends `request` on `session`, validates a 2xx status (throwing `ProUploadError.networkError`
/// otherwise), and decodes the response body as `T`. Shared by every Pro-mode backend client
/// (`LiveCoachingService`, `LivePoseUploadService`, `LiveObjectDetectionUploadService`,
/// `LiveServeSegmentationUploadService`) to avoid repeating the same status-check-and-decode
/// boilerplate in each one.
func sendAndDecode<T: Decodable>(_ request: URLRequest, session: URLSession) async throws -> T {
    var request = request
    request.timeoutInterval = proRequestTimeout
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw ProUploadError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
    }
    return try JSONDecoder().decode(T.self, from: data)
}
