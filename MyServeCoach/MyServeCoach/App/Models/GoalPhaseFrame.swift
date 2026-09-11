import Foundation

/// The goal rule's own phase frame, returned by the backend alongside a chunk's `GoalResult` —
/// keypoints/detections only, no image bytes (the still image is extracted client-side from the
/// assembled session video, see `SetGoalSessionViewModel.finalizeVideo()`).
struct GoalPhaseFrame: Decodable, Sendable {
    let frame: BackendFrame
    let detections: [BackendDetection]
}
