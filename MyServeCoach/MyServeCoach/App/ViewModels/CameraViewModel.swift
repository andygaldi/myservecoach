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
    private let permissionChecker: any PermissionChecking

    private let cameraService: any CameraServiceProtocol
    private let coordinator: PipelineCoordinator
    private let sessionMode: SessionMode

    var session: AVCaptureSession { cameraService.session }
    var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }

    init(
        cameraService: any CameraServiceProtocol = CameraService(),
        permissionChecker: any PermissionChecking = CameraPermissionChecker(),
        coordinator: PipelineCoordinator = PipelineCoordinator(),
        sessionMode: SessionMode = .lite
    ) {
        self.cameraService = cameraService
        self.permissionChecker = permissionChecker
        self.coordinator = coordinator
        self.sessionMode = sessionMode
    }

    func startSession() async {
        let authorized = await permissionChecker.checkPermission()
        guard authorized else {
            permissionDenied = true
            return
        }
        do {
            try cameraService.configure(position: cameraPosition, sessionMode: sessionMode)
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

    func startChunkedRecording(chunkDuration: TimeInterval, onChunkFinalized: @escaping (URL?, Bool) -> Void) {
        recordingState = .recording
        cameraService.startChunkedRecording(chunkDuration: chunkDuration, onChunkFinalized: onChunkFinalized)
    }

    func stopChunkedRecording() {
        cameraService.stopChunkedRecording()
    }

    func useClip() {
        if case .previewing(let url) = recordingState {
            let c = coordinator
            Task { try? await c.run(videoURL: url) }
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
}
