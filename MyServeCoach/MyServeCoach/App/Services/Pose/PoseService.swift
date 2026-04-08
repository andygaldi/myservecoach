import Foundation
import Vision

// MARK: - Domain Types

/// Normalized 2D keypoint. Coordinates are in Vision's normalized image space (0–1).
struct Keypoint: Codable {
    let jointName: String
    let x: Float
    let y: Float
    let confidence: Float
}

/// All keypoints detected in a single video frame.
struct PoseFrame: Codable {
    let frameIndex: Int
    let timestamp: TimeInterval
    let keypoints: [Keypoint]
}

// MARK: - Protocol

/// Extracts human pose keypoints from a serve video.
protocol PoseServiceProtocol {
    func extractPoses(from videoURL: URL, confidenceThreshold: Float) async throws -> [PoseFrame]
}

// MARK: - Live Implementation

/// Vision-framework-backed implementation. Filled in during the On-Device Pose epic.
final class LivePoseService: PoseServiceProtocol {
    func extractPoses(from videoURL: URL, confidenceThreshold: Float) async throws -> [PoseFrame] {
        // TODO: Use AVAssetReader + VNDetectHumanBodyPoseRequest, sample every N frames
        throw PoseServiceError.notImplemented
    }
}

// MARK: - Errors

enum PoseServiceError: Error {
    case notImplemented
    case videoReadFailed(String)
    case noFramesDetected
}
