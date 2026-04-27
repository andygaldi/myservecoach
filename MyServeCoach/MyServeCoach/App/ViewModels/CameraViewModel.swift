import AVFoundation
import Observation

enum RecordingState: Equatable {
    case idle
    case recording
    case previewing(URL)
}

struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

@Observable
final class CameraViewModel {
    var cameraPosition: AVCaptureDevice.Position = .back
    var recordingState: RecordingState = .idle
    var recordingError: String?
    var permissionDenied: Bool = false
    private(set) var previewItem: PreviewItem?

    @ObservationIgnored
    private let permissionChecker: () async -> Bool

    private let cameraService: any CameraServiceProtocol
    private let pipeline = PoseAnalysisPipeline()

    var session: AVCaptureSession { cameraService.session }
    var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }

    init(
        cameraService: any CameraServiceProtocol = CameraService(),
        permissionChecker: @escaping () async -> Bool = CameraViewModel.defaultPermissionChecker
    ) {
        self.cameraService = cameraService
        self.permissionChecker = permissionChecker
    }

    func startSession() async {
        let authorized = await permissionChecker()
        guard authorized else {
            permissionDenied = true
            return
        }
        do {
            try cameraService.configure(position: cameraPosition)
            cameraService.startSession()
        } catch {
            // Device unavailable; UI surfaces permissionDenied only — hardware
            // errors will be visible via the blank preview.
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

    func useClip() {
        if case .previewing(let url) = recordingState {
            Task { try? await pipeline.analyze(videoURL: url) }
        }
        previewItem = nil
        recordingState = .idle
    }

    func retake(url: URL) {
        previewItem = nil
        try? FileManager.default.removeItem(at: url)
        recordingState = .idle
    }

    private func startRecording() {
        recordingError = nil
        let url = tempMovieURL()
        recordingState = .recording
        cameraService.startRecording(to: url) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let outputURL):
                    self.previewItem = PreviewItem(url: outputURL)
                    self.recordingState = .previewing(outputURL)
                case .failure(let error):
                    self.recordingError = error.localizedDescription
                    self.recordingState = .idle
                }
            }
        }
    }

    private func tempMovieURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
    }

    private static let defaultPermissionChecker: () async -> Bool = {
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
