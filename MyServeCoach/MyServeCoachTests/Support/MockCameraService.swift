import AVFoundation
@testable import MyServeCoach

/// Shared `CameraServiceProtocol` test double — used by `CameraViewModelTests` for single-shot
/// recording and by `SetGoalSessionViewModelTests` for chunked recording, so both suites drive
/// the same mock rather than maintaining separate copies.
final class MockCameraService: CameraServiceProtocol {
    let session = AVCaptureSession()
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?
    private var chunkHandler: ((URL?, Bool) -> Void)?
    private(set) var lastChunkDuration: TimeInterval?
    private(set) var stopChunkedRecordingCallCount = 0

    func configure(position: AVCaptureDevice.Position, sessionMode: SessionMode) throws {}
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

    func startChunkedRecording(chunkDuration: TimeInterval, onChunkFinalized: @escaping (URL?, Bool) -> Void) {
        lastChunkDuration = chunkDuration
        chunkHandler = onChunkFinalized
    }

    func stopChunkedRecording() {
        stopChunkedRecordingCallCount += 1
    }

    func triggerChunk(url: URL?, isFinal: Bool) {
        chunkHandler?(url, isFinal)
    }
}
