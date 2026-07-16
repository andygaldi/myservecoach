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

    // MARK: - Mode selector (Phase P6)

    @Test("default mode is Lite")
    func defaultModeIsLite() {
        let vm = makeVM()
        #expect(vm.selectedMode == .lite)
    }

    @Test("selected mode persists across VideoSourceSelectionViewModel instances sharing the same UserDefaults suite")
    func selectedModePersistsAcrossInstancesViaUserDefaults() {
        let defaults = makeIsolatedDefaults()
        let vm1 = VideoSourceSelectionViewModel(
            coordinator: PipelineCoordinator(pipeline: MockPipeline(segments: [])),
            proPipeline: MockProServeAnalyzing(),
            permissionChecker: MockPermissionChecker(granted: true),
            defaults: defaults
        )
        vm1.selectedMode = .pro2D

        let vm2 = VideoSourceSelectionViewModel(
            coordinator: PipelineCoordinator(pipeline: MockPipeline(segments: [])),
            proPipeline: MockProServeAnalyzing(),
            permissionChecker: MockPermissionChecker(granted: true),
            defaults: defaults
        )
        #expect(vm2.selectedMode == .pro2D)
    }

    @Test("Pro 2D mode routes runPipeline to the Pro pipeline, never the Lite coordinator")
    func proModeRoutesToProPipelineNotLiteCoordinator() async {
        let liteMock = MockPipeline(segments: [makeFrames()])
        let proMock = MockProServeAnalyzing(results: [AssessmentServeResult(serveIndex: 0, coaching: CoachingResult(cues: [], summary: nil))])
        let vm = makeVM(pipeline: liteMock, proAnalyzer: proMock)
        vm.selectedMode = .pro2D
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(await proMock.wasCalled == true)
        #expect(await liteMock.wasCalled == false)
        #expect(vm.navigateToAssessmentResults == true)
    }

    @Test("Pro 2D mode: no segments detected sets a Pro-specific error message")
    func proModeNoSegmentsSetsDistinctErrorMessage() async {
        let proMock = MockProServeAnalyzing(error: ProServeAnalysisError.noSegmentsDetected)
        let vm = makeVM(proAnalyzer: proMock)
        vm.selectedMode = .pro2D
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == "No serves detected in this clip. Try a different clip.")
        #expect(vm.isProcessing == false)
    }

    @Test("Pro 2D mode: success sets assessmentResults and navigates")
    func proModeSuccessSetsAssessmentResultsAndNavigates() async {
        let expected = [AssessmentServeResult(serveIndex: 0, coaching: CoachingResult(cues: [], summary: "clean"))]
        let proMock = MockProServeAnalyzing(results: expected)
        let vm = makeVM(proAnalyzer: proMock)
        vm.selectedMode = .pro2D
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.assessmentResults?.count == 1)
        #expect(vm.assessmentResults?.first?.coaching.summary == "clean")
        #expect(vm.navigateToAssessmentResults == true)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Import re-encode gating (Phase P6b)

    @Test("Pro 2D mode: imported clip is re-encoded before analysis")
    func proModeImportedClipReencodesBeforeAnalyzing() async {
        let reencoder = MockVideoReencoding()
        let proMock = MockProServeAnalyzing(results: [AssessmentServeResult(serveIndex: 0, coaching: CoachingResult(cues: [], summary: nil))])
        let vm = makeVM(proAnalyzer: proMock, reencoder: reencoder)
        vm.selectedMode = .pro2D
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url, inputType: "imported")

        #expect(await reencoder.callCount == 1)
        #expect(await reencoder.receivedURL == url)
        #expect(vm.pendingVideoURL != url)  // the reencoded URL, not the original import
        #expect(vm.navigateToAssessmentResults == true)
    }

    @Test("Pro 2D mode: recorded clip skips re-encoding entirely")
    func proModeRecordedClipSkipsReencoding() async {
        let reencoder = MockVideoReencoding()
        let proMock = MockProServeAnalyzing(results: [AssessmentServeResult(serveIndex: 0, coaching: CoachingResult(cues: [], summary: nil))])
        let vm = makeVM(proAnalyzer: proMock, reencoder: reencoder)
        vm.selectedMode = .pro2D
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url, inputType: "recorded")

        #expect(await reencoder.callCount == 0)
        #expect(vm.pendingVideoURL == url)
        #expect(vm.navigateToAssessmentResults == true)
    }

    @Test("Pro 2D mode: re-encode failure sets a distinct error message and resets processing state")
    func proModeReencodeFailureSetsErrorMessage() async {
        let reencoder = MockVideoReencoding(error: MockError.failed)
        let vm = makeVM(reencoder: reencoder)
        vm.selectedMode = .pro2D
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url, inputType: "imported")

        #expect(vm.errorMessage == "Could not process imported video. Try again.")
        #expect(vm.isProcessing == false)
        #expect(vm.navigateToAssessmentResults == false)
    }

    // MARK: - Lite path, unchanged (explicit .lite mode)

    @Test("Lite mode: zero segments → errorMessage set, isProcessing cleared")
    func liteModeZeroServesTriggersError() async {
        let vm = makeVM(pipeline: MockPipeline(segments: []))
        vm.selectedMode = .lite
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == "No serves detected. Try a different clip.")
        #expect(vm.isProcessing == false)
    }

    @Test("Lite mode: non-empty segments → no error, isProcessing cleared")
    func liteModeServesDetectedNoError() async {
        let vm = makeVM(pipeline: MockPipeline(segments: [makeFrames()]))
        vm.selectedMode = .lite
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == nil)
        #expect(vm.isProcessing == false)
    }

    @Test("Lite mode: pipeline failure → generic error message, isProcessing cleared")
    func liteModePipelineFailureSetsError() async {
        let vm = makeVM(pipeline: MockPipeline(error: MockError.failed))
        vm.selectedMode = .lite
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mov")

        await vm.runPipeline(on: url)

        #expect(vm.errorMessage == "Could not analyze video. Try again.")
        #expect(vm.isProcessing == false)
    }
}

// MARK: - Helpers

@MainActor
private func makeVM(
    pipeline: any PoseAnalyzing = MockPipeline(segments: []),
    authStatus: PHAuthorizationStatus = .authorized,
    proAnalyzer: any ProServeAnalyzing = MockProServeAnalyzing(),
    reencoder: any VideoReencoding = MockVideoReencoding()
) -> VideoSourceSelectionViewModel {
    let granted = authStatus != .denied && authStatus != .restricted
    return VideoSourceSelectionViewModel(
        coordinator: PipelineCoordinator(pipeline: pipeline),
        proPipeline: proAnalyzer,
        reencoder: reencoder,
        permissionChecker: MockPermissionChecker(granted: granted),
        defaults: makeIsolatedDefaults()
    )
}

@MainActor
private func makeVM(authStatus: PHAuthorizationStatus) -> VideoSourceSelectionViewModel {
    makeVM(pipeline: MockPipeline(segments: []), authStatus: authStatus)
}

/// A fresh, uniquely-named UserDefaults suite per call — avoids cross-test races on the shared
/// standard domain (same lesson as StubURLProtocol's per-host state; see that file's doc comment).
private func makeIsolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "com.myservecoach.tests.\(UUID().uuidString)")!
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

private actor MockPipeline: PoseAnalyzing {
    var segments: [[PoseFrame]] = []
    var error: Error?
    private(set) var wasCalled = false

    init(segments: [[PoseFrame]] = [], error: Error? = nil) {
        self.segments = segments
        self.error = error
    }

    func analyze(videoURL: URL) async throws -> [[PoseFrame]] {
        wasCalled = true
        if let error { throw error }
        return segments
    }
}

private actor MockProServeAnalyzing: ProServeAnalyzing {
    var results: [AssessmentServeResult] = []
    var error: Error?
    private(set) var wasCalled = false

    init(results: [AssessmentServeResult] = [], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func analyze(videoURL: URL) async throws -> [AssessmentServeResult] {
        wasCalled = true
        if let error { throw error }
        return results
    }
}

private actor MockVideoReencoding: VideoReencoding {
    var error: Error?
    private(set) var callCount = 0
    private(set) var receivedURL: URL?

    init(error: Error? = nil) {
        self.error = error
    }

    func reencode(sourceURL: URL) async throws -> URL {
        callCount += 1
        receivedURL = sourceURL
        if let error { throw error }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("reencoded-\(UUID().uuidString).mov")
    }
}
