import Foundation

/// Owns the lifecycle of a single in-flight analysis Task.
/// Cancels any previous run when a new one starts.
actor PipelineCoordinator {
    private let pipeline: any PoseAnalyzing
    private var task: Task<[[PoseFrame]], Error>?

    init(pipeline: any PoseAnalyzing = PoseAnalysisPipeline()) {
        self.pipeline = pipeline
    }

    func run(videoURL: URL) async throws -> [[PoseFrame]] {
        task?.cancel()
        let t = Task { [p = pipeline] in
            try await p.analyze(videoURL: videoURL)
        }
        task = t
        defer { task = nil }
        return try await t.value
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
