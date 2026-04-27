import Foundation
import Vision

// MARK: - Domain Types

/// Normalized 2D keypoint. Coordinates are in Vision's normalized image space (0–1).
struct JointPoint: Codable {
    let x: Float
    let y: Float
    let confidence: Float
}

/// Pose keypoints detected in a single sampled video frame.
/// `joints` keys are `VNHumanBodyPoseObservation.JointName.rawValue` strings.
struct PoseFrame: Codable {
    let timestamp: Double
    let joints: [String: JointPoint]
}

// MARK: - Constants

enum PoseConstants {
    /// Sample every Nth frame from the 30 fps source, yielding ~10 fps of pose data.
    static let kPoseSampleStride: Int = 3
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
        // TODO: Use FrameSamplerService + PoseEstimationService
        throw PoseServiceError.notImplemented
    }
}

// MARK: - Errors

enum PoseServiceError: Error {
    case notImplemented
    case videoReadFailed(String)
    case noFramesDetected
}
