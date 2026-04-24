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
        #expect(vm.previewItem?.url == url)
    }

    @Test("recording → idle on recording failure")
    func recordingFailurePath() async {
        let mock = MockCameraService()
        let vm = CameraViewModel(cameraService: mock)
        vm.toggleRecording()

        mock.triggerCompletion(result: .failure(MockError.failed))
        await Task.yield()

        #expect(vm.recordingState == .idle)
        #expect(vm.previewItem == nil)
        #expect(vm.recordingError != nil)
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
        #expect(vm.previewItem == nil)
    }

    @Test("previewing → idle on useClip()")
    func previewingToIdleOnUseClip() async {
        let mock = MockCameraService()
        let vm = CameraViewModel(cameraService: mock)
        vm.toggleRecording()

        let url = URL(fileURLWithPath: "/tmp/test.mov")
        mock.triggerCompletion(result: .success(url))
        await Task.yield()

        vm.useClip()
        #expect(vm.recordingState == .idle)
        #expect(vm.previewItem == nil)
    }

    @Test("toggleRecording() is no-op when state == .previewing")
    func toggleRecordingNoOpWhilePreviewing() async {
        let mock = MockCameraService()
        let vm = CameraViewModel(cameraService: mock)
        vm.toggleRecording()

        let url = URL(fileURLWithPath: "/tmp/test.mov")
        mock.triggerCompletion(result: .success(url))
        await Task.yield()

        #expect(vm.recordingState == .previewing(url))
        vm.toggleRecording()
        #expect(vm.recordingState == .previewing(url))
    }

    @Test("permissionDenied set correctly from .denied status")
    func permissionDeniedFlag() async {
        let vm = CameraViewModel(cameraService: MockCameraService(), permissionChecker: { false })
        await vm.startSession()
        #expect(vm.permissionDenied == true)
    }

    @Test("permissionDenied stays false on authorized status")
    func permissionGrantedFlag() async {
        let vm = CameraViewModel(cameraService: MockCameraService(), permissionChecker: { true })
        await vm.startSession()
        #expect(vm.permissionDenied == false)
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

// MARK: - Helpers

private enum MockError: Error {
    case failed
}

// MARK: - Mock

private final class MockCameraService: CameraServiceProtocol {
    let session = AVCaptureSession()
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?

    func configure(position: AVCaptureDevice.Position) throws {}
    func startSession() {}
    func stopSession() {}

    func toggleCamera(currentPosition: AVCaptureDevice.Position) throws -> AVCaptureDevice.Position {
        currentPosition == .back ? .front : .back
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        recordingCompletion = completion
    }

    func stopRecording() {}

    func triggerCompletion(result: Result<URL, Error>) {
        recordingCompletion?(result)
        recordingCompletion = nil
    }
}
