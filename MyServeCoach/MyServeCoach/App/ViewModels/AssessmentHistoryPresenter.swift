import Foundation
import UIKit

/// Rebuilds the assessment display models from a persisted `ServeSession`, so history replay
/// renders through exactly the same subviews as the live results screen.
///
/// Lives outside the view because it decodes JSON and does the cross-serve grouping — neither
/// belongs in a SwiftUI body (CLAUDE.md: views stay thin), and both are worth testing directly.
@MainActor
struct AssessmentHistoryPresenter {
    let serveCount: Int
    let majorCount: Int
    let minorCount: Int
    let aggregatedCues: [AssessmentAggregateRow]
    let sections: [AssessmentServeSectionDisplay]

    init(session: ServeSession) {
        let results = session.results.sorted { $0.serveIndex < $1.serveIndex }
        let allCues = results.flatMap(\.cues)

        serveCount = results.count
        majorCount = allCues.filter { $0.severity == "major" }.count
        minorCount = allCues.filter { $0.severity == "minor" }.count

        let cueDisplaysPerServe = results.map { result in
            result.cues.sortedByCoachingPriority().enumerated().map { index, record in
                AssessmentCueDisplay(
                    id: "\(result.serveIndex)-\(index)-\(record.ruleId)",
                    message: record.message,
                    severity: record.severity,
                    phase: record.phase,
                    deviationCaption: CueDeviationFormatter.caption(for: record),
                    cue: Cue(record)
                )
            }
        }

        aggregatedCues = AssessmentDisplayBuilder.aggregate(cuesPerServe: cueDisplaysPerServe)
        sections = zip(results, cueDisplaysPerServe).map { result, cueDisplays in
            Self.section(for: result, cueDisplays: cueDisplays)
        }
    }

    private static func section(
        for result: ServeResult, cueDisplays: [AssessmentCueDisplay]
    ) -> AssessmentServeSectionDisplay {
        let cuesByPhase = Dictionary(grouping: cueDisplays, by: \.phase)

        let frames = result.phaseFrames
            .sorted { phaseRank($0.phaseKey) < phaseRank($1.phaseKey) }
            .compactMap { record -> AssessmentPhaseFrameDisplay? in
                // No image means nothing to draw on; its cues fall through to `unpairedCues`
                // below rather than disappearing.
                guard let decoded = PhaseFrameDecoding.decode(
                    frameImageData: record.frameImageData,
                    keypointsJSON: record.keypointsJSON,
                    detectionsJSON: record.detectionsJSON
                ) else { return nil }
                return AssessmentPhaseFrameDisplay(
                    id: "\(result.serveIndex)-\(record.phaseKey)",
                    phaseKey: record.phaseKey,
                    image: decoded.image,
                    frame: decoded.frame,
                    detections: decoded.detections,
                    cues: cuesByPhase[record.phaseKey] ?? []
                )
            }

        let shownPhases = Set(frames.map(\.phaseKey))
        return AssessmentServeSectionDisplay(
            id: result.serveIndex,
            serveIndex: result.serveIndex,
            summary: result.summary,
            phaseFrames: frames,
            unpairedCues: cueDisplays.filter { !shownPhases.contains($0.phase) }
        )
    }

    private static func phaseRank(_ phase: String) -> Int {
        AssessmentPhaseConstants.displayedPhases.firstIndex(of: phase)
            ?? AssessmentPhaseConstants.displayedPhases.count
    }
}

extension Cue {
    /// Rehydrates the network cue shape from its persisted record, so history feeds the overlay
    /// renderer and the deviation formatter the same type the live path does.
    init(_ record: CueRecord) {
        self.init(
            ruleId: record.ruleId,
            phase: record.phase,
            message: record.message,
            severity: record.severity,
            metric: record.metric,
            joints: record.joints,
            measuredValue: record.measuredValue,
            comparison: record.comparison,
            threshold: record.threshold,
            thresholdMin: record.thresholdMin,
            thresholdMax: record.thresholdMax
        )
    }
}
