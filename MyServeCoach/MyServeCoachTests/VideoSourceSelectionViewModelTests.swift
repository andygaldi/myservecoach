import Foundation
import Photos
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
        let vm = makeVM(pipeline: MockPipeline(segments: []))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == "No serves detected. Try a different clip.")
        #expect(vm.isProcessing == false)
    }

    @Test("non-empty segments → no error, isProcessing cleared")
    func servesDetectedNoError() async {
        let vm = makeVM(pipeline: MockPipeline(segments: [makeFrames()]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == nil)
        #expect(vm.isProcessing == false)
    }

    @Test("pipeline failure → generic error message, isProcessing cleared")
    func pipelineFailureSetsError() async {
        let vm = makeVM(pipeline: MockPipeline(error: MockError.failed))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == "Could not analyze video. Try again.")
        #expect(vm.isProcessing == false)
    }

    @Test("handleLibraryButtonTap clears errorMessage")
    func libraryButtonTapClearsError() async {
        let vm = makeVM(authStatus: .authorized)
        vm.errorMessage = "previous error"

        await vm.handleLibraryButtonTap()

        #expect(vm.errorMessage == nil)
    }

    // MARK: - handleLibraryButtonTap permission branches

    @Test("denied → photoPermissionDenied set, picker not shown")
    func deniedStatusSetsPermissionDenied() async {
        let vm = makeVM(authStatus: .denied)
        await vm.handleLibraryButtonTap()
        #expect(vm.photoPermissionDenied == true)
        #expect(vm.showPhotoPicker == false)
    }

    @Test("restricted → photoPermissionDenied set, picker not shown")
    func restrictedStatusSetsPermissionDenied() async {
        let vm = makeVM(authStatus: .restricted)
        await vm.handleLibraryButtonTap()
        #expect(vm.photoPermissionDenied == true)
        #expect(vm.showPhotoPicker == false)
    }

    @Test("authorized → picker shown, photoPermissionDenied cleared")
    func authorizedStatusShowsPicker() async {
        let vm = makeVM(authStatus: .authorized)
        vm.photoPermissionDenied = true  // pre-existing denial from a previous tap

        await vm.handleLibraryButtonTap()

        #expect(vm.showPhotoPicker == true)
        #expect(vm.photoPermissionDenied == false)
    }

    @Test("limited → picker shown, photoPermissionDenied cleared")
    func limitedStatusShowsPicker() async {
        let vm = makeVM(authStatus: .limited)
        await vm.handleLibraryButtonTap()
        #expect(vm.showPhotoPicker == true)
        #expect(vm.photoPermissionDenied == false)
    }

    @Test("notDetermined → picker shown (PhotosPicker requests access itself)")
    func notDeterminedStatusShowsPicker() async {
        let vm = makeVM(authStatus: .notDetermined)
        await vm.handleLibraryButtonTap()
        #expect(vm.showPhotoPicker == true)
        #expect(vm.photoPermissionDenied == false)
    }

    // MARK: - handlePickerSelection nil guard

    @Test("nil item → no-op: isProcessing and errorMessage unchanged")
    func nilPickerItemIsNoOp() {
        let vm = makeVM(pipeline: MockPipeline(segments: []))
        vm.handlePickerSelection(nil)
        #expect(vm.isProcessing == false)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - handleExport

    @Test("export error → generic error message, isProcessing cleared")
    func handleExportErrorSetsMessage() async {
        let vm = makeVM(pipeline: MockPipeline(segments: []))
        vm.isProcessing = true
        await vm.handleExport { throw MockError.failed }
        #expect(vm.errorMessage == "Could not analyze video. Try again.")
        #expect(vm.isProcessing == false)
    }

    @Test("export success with serves → no error, isProcessing cleared")
    func handleExportSuccessWithServes() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")
        let vm = makeVM(pipeline: MockPipeline(segments: [makeFrames()]))
        vm.isProcessing = true
        await vm.handleExport { url }
        #expect(vm.errorMessage == nil)
        #expect(vm.isProcessing == false)
    }

    @Test("export success with zero serves → no-serves error, isProcessing cleared")
    func handleExportSuccessZeroServes() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")
        let vm = makeVM(pipeline: MockPipeline(segments: []))
        vm.isProcessing = true
        await vm.handleExport { url }
        #expect(vm.errorMessage == "No serves detected. Try a different clip.")
        #expect(vm.isProcessing == false)
    }
}

// MARK: - Helpers

@MainActor
private func makeVM(
    pipeline: any PoseAnalyzing = MockPipeline(segments: []),
    authStatus: PHAuthorizationStatus = .authorized
) -> VideoSourceSelectionViewModel {
    let granted = authStatus != .denied && authStatus != .restricted
    return VideoSourceSelectionViewModel(
        coordinator: PipelineCoordinator(pipeline: pipeline),
        permissionChecker: MockPermissionChecker(granted: granted)
    )
}

@MainActor
private func makeVM(authStatus: PHAuthorizationStatus) -> VideoSourceSelectionViewModel {
    makeVM(pipeline: MockPipeline(segments: []), authStatus: authStatus)
}

private func makeFrames() -> [PoseFrame] {
    [PoseFrame(timestamp: 0, joints: [
        "left_wrist_joint": JointPoint(x: 0.5, y: 0.5, confidence: 0.9)
    ])]
}

private enum MockError: Error { case failed }

private struct MockPermissionChecker: PermissionChecking {
    let granted: Bool
    func checkPermission() async -> Bool { granted }
}

private struct MockPipeline: PoseAnalyzing {
    var segments: [[PoseFrame]] = []
    var error: Error?

    func analyze(videoURL: URL) async throws -> [[PoseFrame]] {
        if let error { throw error }
        return segments
    }
}
