import Foundation
import UIKit

struct GoalAttemptDisplay: Identifiable, Sendable {
    let id = UUID()
    let segmentIndex: Int
    let passed: Bool
    let spokenCue: String
    let phaseFrame: GoalPhaseFrame?
    let cue: Cue?
    /// Extracted client-side from the assembled session video in `finalizeVideo()`, after the
    /// video exists — `nil` at construction time, populated in place once extraction finishes.
    var stillImage: UIImage?

    init(
        segmentIndex: Int,
        passed: Bool,
        spokenCue: String,
        phaseFrame: GoalPhaseFrame? = nil,
        cue: Cue? = nil,
        stillImage: UIImage? = nil
    ) {
        self.segmentIndex = segmentIndex
        self.passed = passed
        self.spokenCue = spokenCue
        self.phaseFrame = phaseFrame
        self.cue = cue
        self.stillImage = stillImage
    }
}
