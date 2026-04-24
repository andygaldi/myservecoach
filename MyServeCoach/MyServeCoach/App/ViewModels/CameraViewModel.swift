import AVFoundation
import Observation

@Observable
final class CameraViewModel {
    var cameraPosition: AVCaptureDevice.Position = .back
    var isRecording = false

    private let cameraService: CameraService

    var session: AVCaptureSession { cameraService.session }

    init(cameraService: CameraService = CameraService()) {
        self.cameraService = cameraService
    }

    func startSession() async {
        let authorized = await AVCaptureDevice.requestAccess(for: .video)
        guard authorized else { return }
        do {
            try cameraService.configure(position: cameraPosition)
            cameraService.startSession()
        } catch {
            // Permission granted but device unavailable; Group 5 will surface this to UI
        }
    }

    func stopSession() {
        cameraService.stopSession()
    }

    func toggleCamera() {
        guard !isRecording else { return }
        do {
            cameraPosition = try cameraService.toggleCamera(currentPosition: cameraPosition)
        } catch {
            // Front camera unavailable on this device
        }
    }
}
