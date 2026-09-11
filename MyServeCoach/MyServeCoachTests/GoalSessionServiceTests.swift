import Foundation
import Testing
@testable import MyServeCoach

@Suite("LiveGoalSessionService Tests")
struct GoalSessionServiceTests {

    private func makeService(stub: StubURLProtocol.Stub) -> (LiveGoalSessionService, URL) {
        let baseURL = StubURLProtocol.uniqueBaseURL()
        StubURLProtocol.setStub(stub, for: baseURL)
        return (LiveGoalSessionService(baseURL: baseURL, session: StubURLProtocol.makeSession()), baseURL)
    }

    private func makeDummyVideoFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")
        try Data("dummy video bytes".utf8).write(to: url)
        return url
    }

    @Test("builds the expected URL query items and decodes results, mapping spoken_cue correctly")
    func uploadChunkBuildsRequestAndDecodesResponse() async throws {
        let (service, baseURL) = makeService(stub: .init(
            statusCode: 200,
            data: Data("""
            { "results": [
                { "segment_index": 0, "goal_result": { "passed": false, "spoken_cue": "Keep your arm straighter", "phase": "trophy_pose" } }
            ] }
            """.utf8)
        ))
        let videoURL = try makeDummyVideoFile()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let results = try await service.uploadChunk(
            fileURL: videoURL, sessionId: "abc-123", goalRuleId: "release_toss_arm_straight", isFinal: true
        )

        #expect(results.count == 1)
        #expect(results[0].segmentIndex == 0)
        #expect(results[0].goalResult.passed == false)
        #expect(results[0].goalResult.spokenCue == "Keep your arm straighter")

        let body = StubURLProtocol.lastBody(for: baseURL)
        #expect(body == Data("dummy video bytes".utf8))

        let requestURL = try #require(StubURLProtocol.lastURL(for: baseURL))
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v1/goal/session/chunk")
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(URLQueryItem(name: "session_id", value: "abc-123")))
        #expect(queryItems.contains(URLQueryItem(name: "goal_rule_id", value: "release_toss_arm_straight")))
        #expect(queryItems.contains(URLQueryItem(name: "stride", value: "2")))
        #expect(queryItems.contains(URLQueryItem(name: "is_final", value: "true")))
    }

    @Test("throws networkError on a non-2xx status")
    func throwsOnNonSuccessStatus() async throws {
        let (service, _) = makeService(stub: .init(statusCode: 500, data: Data()))
        let videoURL = try makeDummyVideoFile()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        await #expect(throws: ProUploadError.self) {
            _ = try await service.uploadChunk(
                fileURL: videoURL, sessionId: "abc-123", goalRuleId: "release_toss_arm_straight", isFinal: false
            )
        }
    }
}
