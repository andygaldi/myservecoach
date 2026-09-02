import Foundation

protocol GoalSessionServicing: Sendable {
    func uploadChunk(fileURL: URL, sessionId: String, goalRuleId: String, isFinal: Bool) async throws -> [GoalChunkResult]
}

/// Uploads one chunk of a Set Goal recording session to `POST /v1/goal/session/chunk`, mirroring
/// `LiveVideoSegmentationService`'s upload style exactly (same `sendUploadAndDecode` helper, same
/// query-param-on-URL + raw-file-body shape).
final class LiveGoalSessionService: GoalSessionServicing {
    private struct ResponseBody: Decodable { let results: [GoalChunkResult] }

    private let baseURL: URL
    private let session: URLSession
    private let stride = 2  // matches segment.py's DEFAULT_STRIDE

    init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func uploadChunk(fileURL: URL, sessionId: String, goalRuleId: String, isFinal: Bool) async throws -> [GoalChunkResult] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/goal/session/chunk"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "goal_rule_id", value: goalRuleId),
            URLQueryItem(name: "stride", value: String(stride)),
            URLQueryItem(name: "is_final", value: String(isFinal)),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        let body: ResponseBody = try await sendUploadAndDecode(request, fromFile: fileURL, session: session)
        return body.results
    }
}
