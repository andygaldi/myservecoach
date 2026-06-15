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
    var navigateToPhaseReview = false
    var phaseReviewViewModel: PhaseReviewViewModel?

    private let exporter = LibraryVideoExporter()
    private let coordinator: PipelineCoordinator
    private var pendingVideoURL: URL?

    @ObservationIgnored
    private let permissionChecker: any PermissionChecking

    init(
        coordinator: PipelineCoordinator = PipelineCoordinator(),
        permissionChecker: any PermissionChecking = PhotoLibraryPermissionChecker()
    ) {
        self.coordinator = coordinator
        self.permissionChecker = permissionChecker
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
        // Release any temp file left over from a previous incomplete session.
        if let old = pendingVideoURL {
            try? FileManager.default.removeItem(at: old)
            pendingVideoURL = nil
        }
        do {
            let segments = try await coordinator.run(videoURL: url)
            if segments.isEmpty {
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

    func dismissPhaseReview() {
        navigateToPhaseReview = false
        phaseReviewViewModel = nil
        if let url = pendingVideoURL {
            try? FileManager.default.removeItem(at: url)
            pendingVideoURL = nil
        }
    }

}
