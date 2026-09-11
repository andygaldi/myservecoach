import Foundation
import UIKit

/// Rehydrates a persisted `GoalAttemptRecord` into `GoalAttemptRowView`'s display inputs —
/// the Set Goal counterpart to `AssessmentHistoryPresenter`'s phase-frame rebuilding, minus the
/// aggregation: one attempt has exactly one phase frame, not several ranked by displayed phase.
@MainActor
struct PersistedGoalAttemptDisplay {
    let segmentIndex: Int
    let passed: Bool
    let spokenCue: String
    /// `nil` when the attempt has no persisted `GoalPhaseFrameRecord` (older sessions saved
    /// before this existed) or its image data won't decode — the row still shows, pass/fail only.
    let stillImage: UIImage?
    /// `nil` also when the keypoints won't decode — the still image shows without a skeleton.
    let poseFrame: BackendFrame?
    let detections: [BackendDetection]
    /// `nil` on a pass, or when the cue JSON is missing/won't decode.
    let highlightedCue: Cue?

    init(_ attempt: GoalAttemptRecord) {
        segmentIndex = attempt.segmentIndex
        passed = attempt.passed
        spokenCue = attempt.spokenCue

        guard let phaseFrame = attempt.phaseFrame,
              let decoded = PhaseFrameDecoding.decode(
                  frameImageData: phaseFrame.frameImageData,
                  keypointsJSON: phaseFrame.keypointsJSON,
                  detectionsJSON: phaseFrame.detectionsJSON
              )
        else {
            stillImage = nil
            poseFrame = nil
            detections = []
            highlightedCue = nil
            return
        }
        stillImage = decoded.image
        poseFrame = decoded.frame
        detections = decoded.detections
        highlightedCue = phaseFrame.cueJSON.flatMap { try? JSONDecoder().decode(Cue.self, from: $0) }
    }
}
