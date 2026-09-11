import AVFoundation
import Foundation
@testable import MyServeCoach

/// Shared test doubles for `SetGoalSessionViewModel`'s three service collaborators.

final class MockGoalSessionService: GoalSessionServicing, @unchecked Sendable {
    struct Call: Equatable {
        let sessionId: String
        let goalRuleId: String
        let isFinal: Bool
    }

    private let lock = NSLock()
    private(set) var calls: [Call] = []

    /// Handler invoked per call; override in tests to control results/errors/suspension.
    /// Default returns an empty result list immediately.
    var handler: @Sendable (URL, String, String, Bool) async throws -> [GoalChunkResult] = { _, _, _, _ in [] }

    func uploadChunk(fileURL: URL, sessionId: String, goalRuleId: String, isFinal: Bool) async throws -> [GoalChunkResult] {
        lock.withLock { calls.append(Call(sessionId: sessionId, goalRuleId: goalRuleId, isFinal: isFinal)) }
        return try await handler(fileURL, sessionId, goalRuleId, isFinal)
    }
}

final class MockSpokenFeedbackService: SpokenFeedbackServicing, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var spokenTexts: [String] = []

    func speak(_ text: String) {
        lock.withLock { spokenTexts.append(text) }
    }
}

final class MockChunkVideoConcatenator: ChunkVideoConcatenating, @unchecked Sendable {
    private(set) var concatenateCallCount = 0
    private(set) var lastChunkURLs: [URL]?
    var resultURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("concatenated.mov")

    func concatenate(chunkURLs: [URL]) async throws -> URL {
        concatenateCallCount += 1
        lastChunkURLs = chunkURLs
        return resultURL
    }
}

final class MockPhaseFrameImageProvider: PhaseFrameImageProviding, @unchecked Sendable {
    private(set) var lastRequestedSeconds: [Double]?
    private(set) var lastTolerance: CMTime?
    /// Keyed by timestamp; a timestamp absent here is dropped from the result, same as a
    /// real extraction failure.
    var dataBySeconds: [Double: Data] = [:]

    func imageData(at seconds: [Double], from videoURL: URL, tolerance: CMTime) async throws -> [Double: Data] {
        lastRequestedSeconds = seconds
        lastTolerance = tolerance
        return seconds.reduce(into: [:]) { result, second in
            if let data = dataBySeconds[second] { result[second] = data }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
