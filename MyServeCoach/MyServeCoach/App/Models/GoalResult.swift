import Foundation

struct GoalResult: Codable, Sendable {
    let passed: Bool
    let spokenCue: String
    /// The ServePhase (raw backend string) the goal's own rule targets — always populated by the
    /// backend, not always "contact". No default: this init exists only for test fixtures (the
    /// real network path decodes `GoalResult` directly), and a missing `phase` should be a
    /// compile error at the call site, not a silently-plausible fallback value.
    let phase: String
    /// The firing `Cue` on a miss (for the failing-joint highlight), `nil` on a pass.
    let cue: Cue?

    init(passed: Bool, spokenCue: String, phase: String, cue: Cue? = nil) {
        self.passed = passed
        self.spokenCue = spokenCue
        self.phase = phase
        self.cue = cue
    }

    enum CodingKeys: String, CodingKey {
        case passed; case spokenCue = "spoken_cue"; case phase; case cue
    }
}

struct GoalChunkResult: Decodable, Sendable {
    let segmentIndex: Int
    let goalResult: GoalResult
    let phaseFrame: GoalPhaseFrame?

    init(segmentIndex: Int, goalResult: GoalResult, phaseFrame: GoalPhaseFrame? = nil) {
        self.segmentIndex = segmentIndex
        self.goalResult = goalResult
        self.phaseFrame = phaseFrame
    }

    enum CodingKeys: String, CodingKey {
        case segmentIndex = "segment_index"
        case goalResult = "goal_result"
        case phaseFrame = "phase_frame"
    }
}
