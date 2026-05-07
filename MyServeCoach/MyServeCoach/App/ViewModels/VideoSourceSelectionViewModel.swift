import Foundation
import Observation
import PhotosUI
import Photos

@Observable
final class VideoSourceSelectionViewModel {
    var navigateToRecord = false
    var showPhotoPicker = false
    var photoPickerItem: PhotosPickerItem?
    var photoPermissionDenied = false
    var isProcessing = false
    var errorMessage: String?

    private let exporter = LibraryVideoExporter()
    private let pipeline = PoseAnalysisPipeline()

    func handleLibraryButtonTap() {
        errorMessage = nil
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
        photoPickerItem = nil  // allow re-selection of the same clip next time
        isProcessing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = try await self.exporter.export(item)
                defer { try? FileManager.default.removeItem(at: url) }
                let segments = try await self.pipeline.analyze(videoURL: url)
                if segments.isEmpty {
                    self.errorMessage = "No serves detected. Try a different clip."
                }
            } catch {
                self.errorMessage = "Could not analyze video. Try again."
                print("[VideoSourceSelection] Pipeline error: \(error)")
            }
            self.isProcessing = false
        }
    }
}
