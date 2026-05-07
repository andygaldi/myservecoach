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

    private let exporter = LibraryVideoExporter()
    private let pipeline = PoseAnalysisPipeline()

    func handleLibraryButtonTap() {
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
        isProcessing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = try await self.exporter.export(item)
                defer { try? FileManager.default.removeItem(at: url) }
                _ = try await self.pipeline.analyze(videoURL: url)
            } catch {
                // Group 4 surfaces error state
                print("[VideoSourceSelection] Pipeline error: \(error)")
            }
            self.isProcessing = false
        }
    }
}
