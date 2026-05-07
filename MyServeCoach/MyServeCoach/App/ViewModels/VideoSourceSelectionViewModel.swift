import Foundation
import Observation
import SwiftUI   // required: PhotosPickerItem lives in _PhotosUI_SwiftUI overlay on iOS 26+
import PhotosUI
import Photos

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

    private let exporter = LibraryVideoExporter()
    private let pipeline: any PoseAnalyzing

    @ObservationIgnored
    private let authorizationStatus: (PHAccessLevel) -> PHAuthorizationStatus

    init(
        pipeline: any PoseAnalyzing = PoseAnalysisPipeline(),
        authorizationStatus: @escaping (PHAccessLevel) -> PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for:)
    ) {
        self.pipeline = pipeline
        self.authorizationStatus = authorizationStatus
    }

    func handleLibraryButtonTap() {
        errorMessage = nil
        let status = authorizationStatus(.readWrite)
        switch status {
        case .denied, .restricted:
            photoPermissionDenied = true
        default:
            photoPermissionDenied = false
            showPhotoPicker = true
        }
    }

    func handlePickerSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        errorMessage = nil
        isProcessing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = try await self.exporter.export(item)
                await self.runPipeline(on: url)
            } catch {
                self.errorMessage = "Could not analyze video. Try again."
                print("[VideoSourceSelection] Export error: \(error)")
                self.isProcessing = false
            }
        }
    }

    // Internal so tests can exercise the pipeline path directly.
    @MainActor
    func runPipeline(on url: URL) async {
        do {
            defer { try? FileManager.default.removeItem(at: url) }
            let segments = try await pipeline.analyze(videoURL: url)
            if segments.isEmpty {
                errorMessage = "No serves detected. Try a different clip."
            }
        } catch {
            errorMessage = "Could not analyze video. Try again."
            print("[VideoSourceSelection] Pipeline error: \(error)")
        }
        isProcessing = false
    }
}
