import Foundation

// MARK: - Domain Types

/// A single coaching cue returned by the backend's rule engine.
struct Cue: Codable, Sendable {
    let ruleId: String
    let phase: String
    let message: String
    let severity: String

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case phase, message, severity
    }
}

/// The result of a backend serve analysis request. Mirrors the backend's `AnalyzeResponse`.
struct CoachingResult: Codable, Sendable {
    let cues: [Cue]
    let summary: String?
}

// MARK: - Protocol

/// Posts keypoints to the FastAPI backend and returns coaching cues.
protocol CoachingServiceProtocol {
    func analyze(
        frames: [BackendFrame],
        detections: [[BackendDetection]]?,
        sessionId: String?
    ) async throws -> CoachingResult
}

// MARK: - Live Implementation

/// URLSession-backed implementation targeting the backend's `POST /v1/analyze`.
/// First caller lands in Phase P6 (Pro 2D Assessment) — see phase P1's requirements.md
/// for why this was built dormant/uncalled originally.
final class LiveCoachingService: CoachingServiceProtocol {
    private struct RequestBody: Encodable {
        let frames: [BackendFrame]
        let detections: [[BackendDetection]]?
        let sessionId: String?

        enum CodingKeys: String, CodingKey {
            case frames, detections
            case sessionId = "session_id"
        }
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func analyze(
        frames: [BackendFrame],
        detections: [[BackendDetection]]? = nil,
        sessionId: String? = nil
    ) async throws -> CoachingResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/analyze"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(frames: frames, detections: detections, sessionId: sessionId)
        )

        return try await sendAndDecode(request, session: session)
    }
}
