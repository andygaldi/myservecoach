import AVFoundation

final class CameraService: NSObject {
    let session = AVCaptureSession()
    private var currentInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?
    var isRecording = false

    func configure(position: AVCaptureDevice.Position = .back) throws {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let existing = currentInput {
            session.removeInput(existing)
        }

        let device = try captureDevice(for: position)
        let input = try AVCaptureDeviceInput(device: device)

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraServiceError.cannotAddInput
        }

        session.addInput(input)
        currentInput = input

        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        updateMirroring(for: position)
    }

    func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    func toggleCamera(currentPosition: AVCaptureDevice.Position) throws -> AVCaptureDevice.Position {
        guard !isRecording else { return currentPosition }
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back

        let device = try captureDevice(for: newPosition)
        let newInput = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()

        if let existing = currentInput {
            session.removeInput(existing)
        }

        guard session.canAddInput(newInput) else {
            session.commitConfiguration()
            throw CameraServiceError.cannotAddInput
        }

        session.addInput(newInput)
        currentInput = newInput
        session.commitConfiguration()

        updateMirroring(for: newPosition)
        return newPosition
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        recordingCompletion = completion
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
    }

    func stopRecording() {
        movieOutput.stopRecording()
    }

    private func captureDevice(for position: AVCaptureDevice.Position) throws -> AVCaptureDevice {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraServiceError.deviceUnavailable
        }
        return device
    }

    private func updateMirroring(for position: AVCaptureDevice.Position) {
        for connection in session.connections where connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        isRecording = false
        let result: Result<URL, Error>
        if let error {
            result = .failure(error)
        } else {
            result = .success(outputFileURL)
        }
        recordingCompletion?(result)
        recordingCompletion = nil
    }
}

enum CameraServiceError: Error {
    case deviceUnavailable
    case cannotAddInput
}
