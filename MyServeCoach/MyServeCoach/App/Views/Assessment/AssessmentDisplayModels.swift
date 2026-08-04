import Foundation
import UIKit

/// Plain display values shared by the live results screen and history replay.
///
/// Both screens build these — one from a fresh `[AssessmentServeResult]`, the other from
/// SwiftData records — so the section views below can render either without knowing which.

struct AssessmentCueDisplay: Identifiable {
    let id: String
    let message: String
    let severity: String
    let phase: String
    /// "measured 62° · target ≤45°", or `nil` for a cue with no deviation detail.
    let deviationCaption: String?
    /// Carried so the overlay can draw the segment this cue measured.
    let cue: Cue
}

struct AssessmentPhaseFrameDisplay: Identifiable {
    let id: String
    let phaseKey: String
    let image: UIImage
    /// `nil` when the persisted keypoints could not be decoded — the frame renders without a
    /// skeleton rather than vanishing.
    let frame: BackendFrame?
    let detections: [BackendDetection]
    /// Cues this phase produced, in priority order.
    let cues: [AssessmentCueDisplay]

    var label: String { AssessmentPhaseConstants.label(for: phaseKey) }

    /// The most severe cue on this phase drives the highlight; `nil` leaves the skeleton alone.
    var highlightedCue: Cue? { cues.first?.cue }
}

struct AssessmentServeSectionDisplay: Identifiable {
    let id: Int
    let serveIndex: Int
    let summary: String?
    let phaseFrames: [AssessmentPhaseFrameDisplay]
    /// Cues whose phase has no retained frame — a phase outside the displayed four, or one whose
    /// image extraction failed. Shown as plain rows so no cue is ever silently dropped.
    let unpairedCues: [AssessmentCueDisplay]

    var title: String { "Serve \(serveIndex + 1)" }
    var hasNoCues: Bool { phaseFrames.allSatisfy { $0.cues.isEmpty } && unpairedCues.isEmpty }
}

struct AssessmentAggregateRow: Identifiable {
    let id: String  // ruleId
    let message: String
    let severity: String
    let phase: String
    let flaggedServeCount: Int
    let totalServeCount: Int

    var isMajor: Bool { severity == "major" }
    var subtitle: String {
        "\(flaggedServeCount) of \(totalServeCount) serve\(totalServeCount == 1 ? "" : "s") · \(AssessmentPhaseConstants.label(for: phase).lowercased())"
    }
}

enum AssessmentDisplayBuilder {

    /// Groups cues by `ruleId` across serves.
    ///
    /// The count is of *serves flagged*, not cue occurrences — a rule that fires twice within one
    /// serve still counts that serve once, so "3 of 4 serves" always reads against the same
    /// denominator.
    static func aggregate(cuesPerServe: [[AssessmentCueDisplay]]) -> [AssessmentAggregateRow] {
        let totalServeCount = cuesPerServe.count
        var order: [String] = []
        var flaggedServes: [String: Int] = [:]
        var representative: [String: AssessmentCueDisplay] = [:]

        for serveCues in cuesPerServe {
            var seenThisServe: Set<String> = []
            for cue in serveCues {
                let ruleId = cue.cue.ruleId
                if representative[ruleId] == nil {
                    representative[ruleId] = cue
                    order.append(ruleId)
                }
                guard seenThisServe.insert(ruleId).inserted else { continue }
                flaggedServes[ruleId, default: 0] += 1
            }
        }

        let rows = order.compactMap { ruleId -> AssessmentAggregateRow? in
            guard let cue = representative[ruleId] else { return nil }
            return AssessmentAggregateRow(
                id: ruleId,
                message: cue.message,
                severity: cue.severity,
                phase: cue.phase,
                flaggedServeCount: flaggedServes[ruleId] ?? 0,
                totalServeCount: totalServeCount
            )
        }

        return rows.sorted { a, b in
            if a.isMajor != b.isMajor { return a.isMajor }
            if a.flaggedServeCount != b.flaggedServeCount { return a.flaggedServeCount > b.flaggedServeCount }
            return phaseRank(a.phase) < phaseRank(b.phase)
        }
    }

    private static func phaseRank(_ phase: String) -> Int {
        CueOrderingConstants.kovacsPhaseOrder.firstIndex(of: phase)
            ?? CueOrderingConstants.kovacsPhaseOrder.count
    }
}
