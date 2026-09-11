import AVFoundation

// MARK: - Protocol

protocol CameraServiceProtocol: AnyObject {
    var session: AVCaptureSession { get }
    func configure(position: AVCaptureDevice.Position, sessionMode: SessionMode) throws
    func startSession()
    func stopSession()
    func toggleCamera(currentPosition: AVCaptureDevice.Position) throws -> AVCaptureDevice.Position
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void)
    func stopRecording()
    func startChunkedRecording(chunkDuration: TimeInterval, onChunkFinalized: @escaping (URL?, Bool) -> Void)
    func stopChunkedRecording()
}

// MARK: - Recording output seam (testability)

// AVCaptureMovieFileOutput.startRecording crashes the process if called while not attached to a
// running AVCaptureSession — which Simulator/CI can never provide (no camera hardware). This seam
// lets tests substitute a non-AVFoundation fake to exercise the chunk state machine safely, while
// production always uses the real movieOutput.
protocol MovieRecordingOutput: AnyObject {
    func startRecording(to outputFileURL: URL, recordingDelegate: AVCaptureFileOutputRecordingDelegate)
    func stopRecording()
}

extension AVCaptureMovieFileOutput: MovieRecordingOutput {}

// MARK: - Live Implementation

final class CameraService: NSObject, CameraServiceProtocol {
    let session = AVCaptureSession()
    // All AVFoundation mutations and mutable state must run on sessionQueue.
    private let sessionQueue = DispatchQueue(label: "com.myservecoach.CameraService.session")
    private var currentInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()
    private let recordingOutput: MovieRecordingOutput
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?
    private var isRecording = false
    private var chunkOnFinalized: ((URL?, Bool) -> Void)?
    private var chunkDuration: TimeInterval = 0
    private var isChunking = false
    private var chunkTimer: DispatchSourceTimer?

    init(recordingOutput: MovieRecordingOutput? = nil) {
        self.recordingOutput = recordingOutput ?? movieOutput
        super.init()
    }

    func configure(position: AVCaptureDevice.Position = .back, sessionMode: SessionMode) throws {
        var caught: Error?
        sessionQueue.sync {
            do {
                try _configure(position: position, sessionMode: sessionMode)
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
            recordingOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async { [recordingOutput] in
            recordingOutput.stopRecording()
        }
    }

    func startChunkedRecording(chunkDuration: TimeInterval, onChunkFinalized: @escaping (URL?, Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isChunking = true
            self.chunkDuration = chunkDuration
            chunkOnFinalized = onChunkFinalized
            _beginNextChunk()
        }
    }

    func stopChunkedRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isChunking = false
            chunkTimer?.cancel()
            chunkTimer = nil
            recordingOutput.stopRecording()
        }
    }

    // MARK: - Private (session-queue only)

    private func _beginNextChunk() {
        let url = _tempChunkURL()
        isRecording = true
        recordingOutput.startRecording(to: url, recordingDelegate: self)
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + chunkDuration)
        timer.setEventHandler { [weak self] in self?.recordingOutput.stopRecording() }
        timer.resume()
        chunkTimer = timer
    }

    private func _tempChunkURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
    }

    private func _configure(position: AVCaptureDevice.Position, sessionMode: SessionMode) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Lite keeps the existing device-relative `.high` preset unchanged — CameraService is
        // shared by both modes, and Lite's on-device segmentation was calibrated against
        // whatever `.high` already produces on real devices. Pro 2D locks to a known-good,
        // fixed resolution/fps instead of leaving it device-dependent: real-device testing found
        // the backend's segmentation heuristic reliably breaks on higher resolutions/frame rates
        // (e.g. 1080x1920@60fps, 2160x3840@60fps) that `.high` can produce depending on device,
        // while 720x1280@30fps (matching the calibration footage segment_serves was tuned
        // against) does not have that failure mode. See phases/2026-07-10-p6-.../requirements.md.
        session.sessionPreset = sessionMode == .pro2D ? .hd1280x720 : .high

        let previous = currentInput
        currentInput = nil
        if let previous { session.removeInput(previous) }

        let device = try _captureDevice(for: position)
        if sessionMode == .pro2D {
            try _lockFrameRate(on: device, to: 30)
        }
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

    private func _lockFrameRate(on device: AVCaptureDevice, to fps: Int32) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        let duration = CMTime(value: 1, timescale: fps)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
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
        // Only the preview connection mirrors for a natural selfie view. movieOutput's connection
        // must never mirror: it's the recorded/uploaded file, and a mirrored frame breaks the
        // backend's real-orientation assumptions (HANDEDNESS's "right" hitting wrist, phases.py)
        // for front-camera Set Goal sessions — the wrong/flickering wrist gets tracked, producing
        // spurious serve peaks on idle motion.
        for connection in session.connections where connection.isVideoMirroringSupported {
            guard connection.output !== movieOutput else { continue }
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
            if let chunkHandler = chunkOnFinalized {
                let isFinal = !isChunking
                if isFinal { chunkOnFinalized = nil } else { _beginNextChunk() }
                // A non-final chunk's write error is dropped silently — the rotation continues via
                // _beginNextChunk() above, losing only that chunk's upload. A final chunk's error
                // still must notify the caller (nil URL, isFinal: true) — there's no future chunk to
                // carry that signal, so silently dropping it here would leave the session's
                // finalization (e.g. isFinalizing) stuck forever.
                if error == nil {
                    chunkHandler(outputFileURL, isFinal)
                } else if isFinal {
                    chunkHandler(nil, true)
                }
                return
            }
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
