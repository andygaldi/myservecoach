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
    func analyze(frames: [BackendFrame], sessionId: String?) async throws -> CoachingResult
}

// MARK: - Live Implementation

/// URLSession-backed implementation targeting the backend's `POST /v1/analyze`.
/// Dormant Pro-mode service: no in-app caller in this phase — see phase P1's
/// requirements.md for the Lite-isolation rationale.
final class LiveCoachingService: CoachingServiceProtocol {
    private struct RequestBody: Encodable {
        let frames: [BackendFrame]
        let sessionId: String?

        enum CodingKeys: String, CodingKey {
            case frames
            case sessionId = "session_id"
        }
    }

    private let baseURL: URL

    init(baseURL: URL = BackendConfig.baseURL) {
        self.baseURL = baseURL
    }

    func analyze(frames: [BackendFrame], sessionId: String?) async throws -> CoachingResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/analyze"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(frames: frames, sessionId: sessionId))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CoachingServiceError.networkError("HTTP \(status)")
        }
        return try JSONDecoder().decode(CoachingResult.self, from: data)
    }
}

// MARK: - Errors

enum CoachingServiceError: Error {
    case networkError(String)
}
