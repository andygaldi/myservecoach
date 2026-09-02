import AVFoundation
import Foundation
import Observation
import SwiftUI   // required: PhotosPickerItem lives in _PhotosUI_SwiftUI overlay on iOS 26+
import PhotosUI

// PhotosPickerItem is kept in @State in VideoSourceSelectionView to avoid
// @Observable macro generating a synthetic file that can't resolve PhotosUI types.

@MainActor
@Observable
final class VideoSourceSelectionViewModel {
    var navigateToRecord = false
    var showPhotoPicker = false
    var photoPermissionDenied = false
    var isProcessing = false
    var errorMessage: String?
    var noPoseDetected = false
    var navigateToPhaseReview = false
    var phaseReviewViewModel: PhaseReviewViewModel?
    var navigateToAssessmentResults = false
    private(set) var assessmentResults: [AssessmentServeResult]?
    private(set) var pendingInputType: String = "imported"

    // Not persisted (unlike selectedMode) — resets to Assessment each visit. Only read when
    // selectedMode == .pro2D.
    var selectedWorkflow: ProWorkflow = .assessment
    var navigateToGoalSelection = false
    private(set) var selectedGoal: GoalDefinition?
    var navigateToSetGoalSession = false

    // Not @AppStorage: @Observable classes don't mix cleanly with that property wrapper.
    // UserDefaults-backed directly instead; persists the last-selected mode across sessions.
    // `defaults` is injectable (default `.standard`) so tests can use an isolated suite rather
    // than racing on the shared standard domain.
    private static let modeDefaultsKey = "com.myservecoach.sessionMode"
    var selectedMode: SessionMode {
        get { SessionMode(rawValue: defaults.string(forKey: Self.modeDefaultsKey) ?? "") ?? .lite }
        set { defaults.set(newValue.rawValue, forKey: Self.modeDefaultsKey) }
    }

    private let exporter = LibraryVideoExporter()
    private let coordinator: PipelineCoordinator
    private let proPipeline: any ProServeAnalyzing
    private let reencoder: any VideoReencoding
    private(set) var pendingVideoURL: URL?

    @ObservationIgnored
    private let permissionChecker: any PermissionChecking
    @ObservationIgnored
    private let defaults: UserDefaults

    init(
        coordinator: PipelineCoordinator = PipelineCoordinator(),
        proPipeline: any ProServeAnalyzing = ProServeAnalysisPipeline(),
        reencoder: any VideoReencoding = VideoReencoder(),
        permissionChecker: any PermissionChecking = PhotoLibraryPermissionChecker(),
        defaults: UserDefaults = .standard
    ) {
        self.coordinator = coordinator
        self.proPipeline = proPipeline
        self.reencoder = reencoder
        self.permissionChecker = permissionChecker
        self.defaults = defaults
    }

    func handleLibraryButtonTap() async {
        errorMessage = nil
        let granted = await permissionChecker.checkPermission()
        photoPermissionDenied = !granted
        if granted { showPhotoPicker = true }
    }

    func handlePickerSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        errorMessage = nil
        isProcessing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.handleExport { try await self.exporter.export(item) }
        }
    }

    // Internal so tests can exercise the export→pipeline path without a real PhotosPickerItem.
    @MainActor
    func handleExport(_ action: @escaping () async throws -> URL) async {
        do {
            let url = try await action()
            await runPipeline(on: url)
        } catch {
            errorMessage = "Could not analyze video. Try again."
            print("[VideoSourceSelection] Export error: \(error)")
            isProcessing = false
        }
    }

    // Internal so tests can exercise the pipeline path directly.
    @MainActor
    func runPipeline(on url: URL, inputType: String = "imported") async {
        switch selectedMode {
        case .lite:
            await runLitePipeline(on: url, inputType: inputType)
        case .pro2D:
            await runProPipeline(on: url, inputType: inputType)
        }
    }

    // Renamed verbatim from the original single-mode runPipeline(on:inputType:) body — no
    // logic changes, so the Lite path stays byte-for-byte identical once selected.
    @MainActor
    private func runLitePipeline(on url: URL, inputType: String = "imported") async {
        errorMessage = nil
        noPoseDetected = false
        // Release any temp file left over from a previous incomplete session.
        if let old = pendingVideoURL {
            try? FileManager.default.removeItem(at: old)
            pendingVideoURL = nil
        }
        do {
            let segments = try await coordinator.run(videoURL: url)
            if segments.isEmpty {
                noPoseDetected = true
                errorMessage = "No serves detected. Try a different clip."
                try? FileManager.default.removeItem(at: url)
            } else {
                let guessedFrames = PhaseGuesser().guess(frames: segments[0])
                let asset = AVURLAsset(url: url)
                pendingVideoURL = url
                phaseReviewViewModel = PhaseReviewViewModel(guessedFrames: guessedFrames, videoAsset: asset, inputType: inputType)
                navigateToPhaseReview = true
            }
        } catch {
            errorMessage = "Could not analyze video. Try again."
            try? FileManager.default.removeItem(at: url)
            print("[VideoSourceSelection] Pipeline error: \(error)")
        }
        isProcessing = false
    }

    @MainActor
    private func runProPipeline(on url: URL, inputType: String = "imported") async {
        errorMessage = nil
        if let old = pendingVideoURL {
            try? FileManager.default.removeItem(at: old)
            pendingVideoURL = nil
        }

        // Photos-library imports bypass CameraService's live-capture 720x1280@30fps lock (the
        // resolution/fps segment_serves is validated against) — LibraryVideoExporter.copyToTemp
        // is a byte copy, not a re-encode. Recorded clips already arrive correctly locked, so
        // they skip this step entirely.
        var analysisURL = url
        if inputType == "imported" {
            do {
                let reencoded = try await reencoder.reencode(sourceURL: url)
                try? FileManager.default.removeItem(at: url)
                analysisURL = reencoded
            } catch {
                errorMessage = "Could not process imported video. Try again."
                try? FileManager.default.removeItem(at: url)
                isProcessing = false
                print("[VideoSourceSelection] Re-encode error: \(error)")
                return
            }
        }

        do {
            let results = try await proPipeline.analyze(videoURL: analysisURL)
            pendingVideoURL = analysisURL
            pendingInputType = inputType
            assessmentResults = results
            navigateToAssessmentResults = true
        } catch ProServeAnalysisError.noSegmentsDetected {
            errorMessage = "No serves detected in this clip. Try a different clip."
            try? FileManager.default.removeItem(at: analysisURL)
        } catch {
            errorMessage = "Could not analyze video. Try again."
            try? FileManager.default.removeItem(at: analysisURL)
            print("[VideoSourceSelection] Pro pipeline error: \(error)")
        }
        isProcessing = false
    }

    func dismissPhaseReview() {
        navigateToPhaseReview = false
        phaseReviewViewModel = nil
        if let url = pendingVideoURL {
            try? FileManager.default.removeItem(at: url)
            pendingVideoURL = nil
        }
    }

    func dismissAssessmentResults() {
        navigateToAssessmentResults = false
        assessmentResults = nil
        if let url = pendingVideoURL {
            try? FileManager.default.removeItem(at: url)
            pendingVideoURL = nil
        }
    }

    func selectGoal(_ goal: GoalDefinition) {
        selectedGoal = goal
        navigateToGoalSelection = false
        navigateToSetGoalSession = true
    }

    func dismissSetGoalSession() {
        navigateToSetGoalSession = false
        selectedGoal = nil
    }

}
