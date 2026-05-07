import Foundation
import Testing
@testable import MyServeCoach

// MARK: - LibraryVideoExporter tests

@Suite("LibraryVideoExporter Tests")
struct LibraryVideoExporterTests {

    @Test("copyToTemp copies source to a new .mov file in the temp directory")
    func copyToTempProducesValidFile() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString).mov")
        try Data("video fixture".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let dest = try LibraryVideoExporter.copyToTemp(from: source)
        defer { try? FileManager.default.removeItem(at: dest) }

        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(dest.path != source.path)
        #expect(dest.pathExtension == "mov")
    }

    @Test("copyToTemp produces unique URLs on repeated calls")
    func copyToTempIsUnique() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString).mov")
        try Data("video fixture".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let dest1 = try LibraryVideoExporter.copyToTemp(from: source)
        let dest2 = try LibraryVideoExporter.copyToTemp(from: source)
        defer {
            try? FileManager.default.removeItem(at: dest1)
            try? FileManager.default.removeItem(at: dest2)
        }

        #expect(dest1.path != dest2.path)
    }
}

// MARK: - VideoSourceSelectionViewModel tests

@Suite("VideoSourceSelectionViewModel Tests")
@MainActor
struct VideoSourceSelectionViewModelTests {

    @Test("zero segments → errorMessage set, isProcessing cleared")
    func zeroServesTriggersError() async {
        let vm = VideoSourceSelectionViewModel(pipeline: MockPipeline(segments: []))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == "No serves detected. Try a different clip.")
        #expect(vm.isProcessing == false)
    }

    @Test("non-empty segments → no error, isProcessing cleared")
    func servesDetectedNoError() async {
        let vm = VideoSourceSelectionViewModel(pipeline: MockPipeline(segments: [makeFrames()]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == nil)
        #expect(vm.isProcessing == false)
    }

    @Test("pipeline failure → generic error message, isProcessing cleared")
    func pipelineFailureSetsError() async {
        let vm = VideoSourceSelectionViewModel(pipeline: MockPipeline(error: MockError.failed))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == "Could not analyze video. Try again.")
        #expect(vm.isProcessing == false)
    }

    @Test("handleLibraryButtonTap clears errorMessage")
    func libraryButtonTapClearsError() {
        let vm = VideoSourceSelectionViewModel(pipeline: MockPipeline(segments: []))
        vm.errorMessage = "previous error"

        vm.handleLibraryButtonTap()

        #expect(vm.errorMessage == nil)
    }
}

// MARK: - Helpers

private func makeFrames() -> [PoseFrame] {
    [PoseFrame(timestamp: 0, joints: [
        "left_wrist_joint": JointPoint(x: 0.5, y: 0.5, confidence: 0.9)
    ])]
}

private enum MockError: Error { case failed }

private struct MockPipeline: PoseAnalyzing {
    var segments: [[PoseFrame]] = []
    var error: Error?

    func analyze(videoURL: URL) async throws -> [[PoseFrame]] {
        if let error { throw error }
        return segments
    }
}
