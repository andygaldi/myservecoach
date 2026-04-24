import AVFoundation
import Testing
@testable import MyServeCoach

@Suite("CameraViewModel Tests")
@MainActor
struct CameraViewModelTests {

    @Test("idle → recording on toggleRecording()")
    func idleToRecording() {
        let vm = CameraViewModel(cameraService: MockCameraService())
        #expect(vm.recordingState == .idle)
        vm.toggleRecording()
        #expect(vm.recordingState == .recording)
    }

    @Test("recording → previewing on recordingFinished(url:)")
    func recordingToPreviewing() async {
        let mock = MockCameraService()
        let vm = CameraViewModel(cameraService: mock)
        vm.toggleRecording()

        let url = URL(fileURLWithPath: "/tmp/test.mov")
        mock.triggerCompletion(result: .success(url))
        await Task.yield()

        #expect(vm.recordingState == .previewing(url))
    }

    @Test("previewing → idle on retake()")
    func previewingToIdleOnRetake() async {
        let mock = MockCameraService()
        let vm = CameraViewModel(cameraService: mock)
        vm.toggleRecording()

        let url = URL(fileURLWithPath: "/tmp/test.mov")
        mock.triggerCompletion(result: .success(url))
        await Task.yield()

        vm.retake(url: url)
        #expect(vm.recordingState == .idle)
    }

    @Test("permissionDenied set correctly from .denied status")
    func permissionDeniedFlag() async {
        let vm = CameraViewModel(cameraService: MockCameraService())
        vm.permissionChecker = { false }
        await vm.startSession()
        #expect(vm.permissionDenied == true)
    }

    @Test("cameraPosition toggles .back → .front → .back")
    func cameraPositionToggles() {
        let vm = CameraViewModel(cameraService: MockCameraService())
        #expect(vm.cameraPosition == .back)
        vm.toggleCamera()
        #expect(vm.cameraPosition == .front)
        vm.toggleCamera()
        #expect(vm.cameraPosition == .back)
    }

    @Test("toggleCamera() is no-op when state == .recording")
    func toggleCameraNoOpWhileRecording() {
        let vm = CameraViewModel(cameraService: MockCameraService())
        vm.toggleRecording()
        #expect(vm.isRecording)
        vm.toggleCamera()
        #expect(vm.cameraPosition == .back)
    }
}

// MARK: - Mock

private final class MockCameraService: CameraServiceProtocol {
    let session = AVCaptureSession()
    var isRecording = false
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?

    func configure(position: AVCaptureDevice.Position) throws {}
    func startSession() {}
    func stopSession() {}

    func toggleCamera(currentPosition: AVCaptureDevice.Position) throws -> AVCaptureDevice.Position {
        currentPosition == .back ? .front : .back
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        isRecording = true
        recordingCompletion = completion
    }

    func stopRecording() {
        isRecording = false
    }

    func triggerCompletion(result: Result<URL, Error>) {
        recordingCompletion?(result)
        recordingCompletion = nil
        isRecording = false
    }
}
