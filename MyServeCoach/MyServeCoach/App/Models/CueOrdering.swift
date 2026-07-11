import Foundation

enum CueOrderingConstants {
    /// Kovacs six-frame phase order — used to sort cues within a serve. Distinct from Lite's
    /// 3-case `ServePhase` enum (App/Models/ServePhase.swift); these are the raw backend phase
    /// key strings that conforming types' `phase` already carries.
    static let kovacsPhaseOrder = ["start", "release", "trophy_pose", "racket_drop", "contact", "finish"]
}

/// Common shape shared by `Cue` (network DTO, App/Services/Coaching/CoachingService.swift) and
/// `CueRecord` (SwiftData model, App/Models/SwiftData/CueRecord.swift) — lets both be sorted by
/// the same major-before-minor / Kovacs-phase-order comparator without duplicating it.
protocol CueOrdering {
    var phase: String { get }
    var severity: String { get }
}

extension Array where Element: CueOrdering {
    /// Major-before-minor, then Kovacs phase order within each severity.
    func sortedByCoachingPriority() -> [Element] {
        sorted { a, b in
            if a.severity != b.severity { return a.severity == "major" }
            let ai = CueOrderingConstants.kovacsPhaseOrder.firstIndex(of: a.phase) ?? CueOrderingConstants.kovacsPhaseOrder.count
            let bi = CueOrderingConstants.kovacsPhaseOrder.firstIndex(of: b.phase) ?? CueOrderingConstants.kovacsPhaseOrder.count
            return ai < bi
        }
    }
}

extension Cue: CueOrdering {}
extension CueRecord: CueOrdering {}
