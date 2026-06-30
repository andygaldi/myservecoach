import AVFoundation
import Photos

protocol PermissionChecking: Sendable {
    func checkPermission() async -> Bool
}

struct CameraPermissionChecker: PermissionChecking {
    func checkPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        @unknown default:
            return false
        }
    }
}

// PhotosPicker requests authorization on its own; this checker only surfaces
// whether access has been explicitly denied so the UI can show a Settings prompt.
struct PhotoLibraryPermissionChecker: PermissionChecking {
    func checkPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status != .denied && status != .restricted
    }
}
