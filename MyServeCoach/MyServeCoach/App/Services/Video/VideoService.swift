import Foundation
import AVFoundation

// MARK: - Protocol

/// Abstracts AVFoundation video capture for testability.
protocol VideoServiceProtocol {
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording() async throws -> URL
}

// MARK: - Live Implementation

/// AVFoundation-backed implementation. Filled in during the Video Capture MVP epic.
final class LiveVideoService: VideoServiceProtocol {
    private(set) var isRecording: Bool = false

    func startRecording() throws {
        // TODO: Configure AVCaptureSession and AVCaptureMovieFileOutput
        isRecording = true
    }

    func stopRecording() async throws -> URL {
        // TODO: Stop recording and return the saved file URL
        isRecording = false
        throw VideoServiceError.notImplemented
    }
}

// MARK: - Errors

enum VideoServiceError: Error {
    case notImplemented
    case captureSessionFailed(String)
    case noOutputURL
}
