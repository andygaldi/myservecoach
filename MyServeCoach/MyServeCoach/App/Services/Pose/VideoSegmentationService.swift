import Foundation

struct ProServeSegment: Decodable, Sendable {
    let frames: [BackendFrame]
    let detections: [[BackendDetection]]?
}

protocol VideoSegmentationServiceProtocol {
    func segmentVideo(at url: URL, sessionId: String?) async throws -> [ProServeSegment]
}

/// URLSession-backed client for the backend's `POST /v1/segment/video` (Phase P6) — uploads a
/// clip's raw video file and lets the backend do frame extraction (OpenCV), pose + object
/// detection, and per-serve segmentation server-side, reusing the exact extraction path already
/// validated by the calibration tooling. Replaces the original per-frame JPEG-upload approach
/// (`/v1/pose` + `/v1/detect` + JSON `/v1/segment`), whose on-device AVFoundation/UIKit frame
/// extraction proved not pixel-equivalent enough to reliably match `segment_serves`'s tuning.
final class LiveVideoSegmentationService: VideoSegmentationServiceProtocol {
    private struct SegmentResponseBody: Decodable {
        let segments: [ProServeSegment]
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func segmentVideo(at url: URL, sessionId: String?) async throws -> [ProServeSegment] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/segment/video"), resolvingAgainstBaseURL: false
        )!
        if let sessionId {
            components.queryItems = [URLQueryItem(name: "session_id", value: sessionId)]
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")

        let body: SegmentResponseBody = try await sendUploadAndDecode(request, fromFile: url, session: session)
        return body.segments
    }
}
