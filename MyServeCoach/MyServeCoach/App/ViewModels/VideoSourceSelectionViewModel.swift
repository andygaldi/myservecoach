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
        guard item != nil else { return }
        // stub — asset export implemented in Group 3
        print("[VideoSourceSelection] PhotosPickerItem received; export pending")
    }
}
