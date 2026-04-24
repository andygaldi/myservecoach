import AVFoundation
import Observation

enum RecordingState {
    case idle
    case recording
    case previewing(URL)
}

@Observable
final class CameraViewModel {
    var cameraPosition: AVCaptureDevice.Position = .back
    var recordingState: RecordingState = .idle
    var recordingError: String?

    private let cameraService: CameraService

    var session: AVCaptureSession { cameraService.session }
    var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }
    var previewURL: URL? {
        guard case .previewing(let url) = recordingState else { return nil }
        return url
    }

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

    func toggleRecording() {
        switch recordingState {
        case .idle:
            startRecording()
        case .recording:
            cameraService.stopRecording()
        case .previewing:
            break
        }
    }

    private func startRecording() {
        recordingError = nil
        let url = tempMovieURL()
        recordingState = .recording
        cameraService.startRecording(to: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let outputURL):
                    self.recordingState = .previewing(outputURL)
                case .failure(let error):
                    self.recordingError = error.localizedDescription
                    self.recordingState = .idle
                }
            }
        }
    }

    func useClip() {
        recordingState = .idle
    }

    func retake(url: URL) {
        try? FileManager.default.removeItem(at: url)
        recordingState = .idle
    }

    private func tempMovieURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
    }
}
