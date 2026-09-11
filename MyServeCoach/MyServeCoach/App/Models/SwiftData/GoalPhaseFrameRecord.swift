import Foundation
import SwiftData

/// The Set Goal counterpart to `PhaseFrameRecord` — the goal rule's own phase frame, plus the
/// firing `Cue` (if any) for the failing-joint highlight. No `phaseKey`/`result`: Set Goal has
/// exactly one phase frame per attempt (the goal rule's own phase), not per-serve-phase like
/// Assessment.
@Model
final class GoalPhaseFrameRecord {
    var id: UUID = UUID()
    var frameTimestamp: Double = 0
    var frameImageData: Data = Data()
    /// JSON-encoded `BackendFrame`.
    var keypointsJSON: Data = Data()
    /// JSON-encoded `[BackendDetection]` at the same frame (ball/racket boxes).
    var detectionsJSON: Data = Data()
    /// JSON-encoded `Cue`, `nil` on a pass (no firing cue). Unlike Assessment's `CueRecord`
    /// (a typed `@Model`, queryable for `majorCount`/`minorCount` aggregation across a whole
    /// session), Set Goal has at most one cue per attempt and never aggregates it — a second
    /// `@Model`/relationship would add SwiftData schema surface with no query it's needed for,
    /// so it's stored as opaque JSON like `keypointsJSON`/`detectionsJSON` above instead.
    var cueJSON: Data?
    var attempt: GoalAttemptRecord?

    init(
        frameTimestamp: Double,
        frameImageData: Data,
        keypointsJSON: Data,
        detectionsJSON: Data,
        cueJSON: Data?
    ) {
        self.frameTimestamp = frameTimestamp
        self.frameImageData = frameImageData
        self.keypointsJSON = keypointsJSON
        self.detectionsJSON = detectionsJSON
        self.cueJSON = cueJSON
    }
}
