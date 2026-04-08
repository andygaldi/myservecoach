import Foundation

// MARK: - Domain Types

/// The result of a backend serve analysis request.
struct CoachingResult: Codable {
    let cues: [String]
    /// Timestamps (seconds) of key pose phases, e.g. ["trophy": 1.2, "contact": 2.4]
    let keyframeTimestamps: [String: TimeInterval]
}

// MARK: - Protocol

/// Posts keypoints to the FastAPI backend and returns coaching cues.
protocol CoachingServiceProtocol {
    func analyze(keypointsJSON: String) async throws -> CoachingResult
}

// MARK: - Live Implementation

/// URLSession-backed implementation. Filled in during the Backend Serve Analysis epic.
final class LiveCoachingService: CoachingServiceProtocol {
    private let backendURL: URL

    init(backendURL: URL = URL(string: "http://localhost:8000/analysis/serve")!) {
        self.backendURL = backendURL
    }

    func analyze(keypointsJSON: String) async throws -> CoachingResult {
        // TODO: Build URLRequest, POST keypointsJSON body, decode CoachingResult response
        throw CoachingServiceError.notImplemented
    }
}

// MARK: - Errors

enum CoachingServiceError: Error {
    case notImplemented
    case networkError(String)
    case decodingFailed
}
