import AVFoundation

// MARK: - Protocol

protocol CameraServiceProtocol: AnyObject {
    var session: AVCaptureSession { get }
    func configure(position: AVCaptureDevice.Position) throws
    func startSession()
    func stopSession()
    func toggleCamera(currentPosition: AVCaptureDevice.Position) throws -> AVCaptureDevice.Position
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void)
    func stopRecording()
}

// MARK: - Live Implementation

final class CameraService: NSObject, CameraServiceProtocol {
    let session = AVCaptureSession()
    // All AVFoundation mutations and mutable state must run on sessionQueue.
    private let sessionQueue = DispatchQueue(label: "com.myservecoach.CameraService.session")
    private var currentInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?
    private var isRecording = false

    func configure(position: AVCaptureDevice.Position = .back) throws {
        var caught: Error?
        sessionQueue.sync {
            do {
                try _configure(position: position)
                _updateMirroring(for: position)
            } catch {
                caught = error
            }
        }
        if let error = caught { throw error }
    }

    func startSession() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func toggleCamera(currentPosition: AVCaptureDevice.Position) throws -> AVCaptureDevice.Position {
        var newPosition = currentPosition
        var caught: Error?
        sessionQueue.sync {
            do {
                newPosition = try _toggleCamera(currentPosition: currentPosition)
            } catch {
                caught = error
            }
        }
        if let error = caught { throw error }
        return newPosition
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isRecording = true
            recordingCompletion = completion
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async { [movieOutput] in
            movieOutput.stopRecording()
        }
    }

    // MARK: - Private (session-queue only)

    private func _configure(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        let previous = currentInput
        currentInput = nil
        if let previous { session.removeInput(previous) }

        let device = try _captureDevice(for: position)
        let input = try AVCaptureDeviceInput(device: device)

        guard session.canAddInput(input) else {
            throw CameraServiceError.cannotAddInput
        }

        session.addInput(input)
        currentInput = input

        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
    }

    private func _toggleCamera(currentPosition: AVCaptureDevice.Position) throws -> AVCaptureDevice.Position {
        guard !isRecording else { return currentPosition }
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back

        let device = try _captureDevice(for: newPosition)
        let newInput = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()

        let previous = currentInput
        currentInput = nil
        if let previous { session.removeInput(previous) }

        guard session.canAddInput(newInput) else {
            session.commitConfiguration()
            throw CameraServiceError.cannotAddInput
        }

        session.addInput(newInput)
        currentInput = newInput
        session.commitConfiguration()

        _updateMirroring(for: newPosition)
        return newPosition
    }

    private func _captureDevice(for position: AVCaptureDevice.Position) throws -> AVCaptureDevice {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraServiceError.deviceUnavailable
        }
        return device
    }

    private func _updateMirroring(for position: AVCaptureDevice.Position) {
        for connection in session.connections where connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // AVFoundation calls this on an arbitrary queue; bounce to sessionQueue
        // before touching any mutable state.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isRecording = false
            let completion = recordingCompletion
            recordingCompletion = nil
            let result: Result<URL, Error> = error.map { .failure($0) } ?? .success(outputFileURL)
            completion?(result)
        }
    }
}

enum CameraServiceError: Error {
    case deviceUnavailable
    case cannotAddInput
}
