import Foundation
import Observation
import SwiftData
import UIKit

struct AssessmentServeDisplay: Identifiable {
    let id = UUID()
    let serveIndex: Int
    let summary: String?
    let cues: [Cue]  // pre-sorted: major before minor, then Kovacs phase order
    /// Retained phase frames, in `AssessmentPhaseConstants.displayedPhases` order.
    let phaseFrames: [AssessmentPhaseFrame]
}

@MainActor
@Observable
final class AssessmentResultViewModel {
    let serves: [AssessmentServeDisplay]
    let inputType: String
    private let videoURL: URL?

    /// Cues grouped by rule across every serve — the screen's top-level "this keeps happening"
    /// read, above the per-serve detail.
    let aggregatedCues: [AssessmentAggregateRow]
    /// Per-serve sections, each pairing retained phase frames with the cues they produced.
    let sections: [AssessmentServeSectionDisplay]

    var totalMajorCount: Int { serves.flatMap(\.cues).filter { $0.severity == "major" }.count }
    var totalMinorCount: Int { serves.flatMap(\.cues).filter { $0.severity == "minor" }.count }

    init(results: [AssessmentServeResult], inputType: String, videoURL: URL?) {
        self.inputType = inputType
        self.videoURL = videoURL
        self.serves = results.map { result in
            AssessmentServeDisplay(
                serveIndex: result.serveIndex,
                summary: result.coaching.summary,
                cues: result.coaching.cues.sortedByCoachingPriority(),
                phaseFrames: result.phaseFrames
            )
        }

        let cueDisplaysPerServe = serves.map { serve in
            serve.cues.enumerated().map { index, cue in
                AssessmentCueDisplay(
                    // A rule can fire more than once within a serve, so the serve index and the
                    // cue's position both go into the id to keep `ForEach` rows distinct.
                    id: "\(serve.serveIndex)-\(index)-\(cue.ruleId)",
                    message: cue.message,
                    severity: cue.severity,
                    phase: cue.phase,
                    deviationCaption: CueDeviationFormatter.caption(for: cue),
                    cue: cue
                )
            }
        }

        self.aggregatedCues = AssessmentDisplayBuilder.aggregate(cuesPerServe: cueDisplaysPerServe)
        self.sections = zip(serves, cueDisplaysPerServe).map { serve, cueDisplays in
            Self.section(for: serve, cueDisplays: cueDisplays)
        }
    }

    private static func section(
        for serve: AssessmentServeDisplay, cueDisplays: [AssessmentCueDisplay]
    ) -> AssessmentServeSectionDisplay {
        let cuesByPhase = Dictionary(grouping: cueDisplays, by: \.phase)

        let frames = serve.phaseFrames.compactMap { phaseFrame -> AssessmentPhaseFrameDisplay? in
            guard let image = UIImage(data: phaseFrame.imageData) else { return nil }
            return AssessmentPhaseFrameDisplay(
                id: "\(serve.serveIndex)-\(phaseFrame.phase)",
                phaseKey: phaseFrame.phase,
                image: image,
                frame: phaseFrame.frame,
                detections: phaseFrame.detections,
                cues: cuesByPhase[phaseFrame.phase] ?? []
            )
        }

        // Any cue whose phase didn't end up with a rendered frame still gets a row — losing an
        // image must never lose the coaching.
        let shownPhases = Set(frames.map(\.phaseKey))
        return AssessmentServeSectionDisplay(
            id: serve.serveIndex,
            serveIndex: serve.serveIndex,
            summary: serve.summary,
            phaseFrames: frames,
            unpairedCues: cueDisplays.filter { !shownPhases.contains($0.phase) }
        )
    }

    func persist(to context: ModelContext) {
        let encoder = JSONEncoder()
        let session = ServeSession(inputType: inputType, videoURL: videoURL, mode: "pro2d")
        for serve in serves {
            let result = ServeResult(serveIndex: serve.serveIndex, summary: serve.summary)
            result.cues = serve.cues.map {
                CueRecord(
                    ruleId: $0.ruleId,
                    phase: $0.phase,
                    message: $0.message,
                    severity: $0.severity,
                    metric: $0.metric,
                    joints: $0.joints,
                    measuredValue: $0.measuredValue,
                    comparison: $0.comparison,
                    threshold: $0.threshold,
                    thresholdMin: $0.thresholdMin,
                    thresholdMax: $0.thresholdMax
                )
            }
            result.phaseFrames = serve.phaseFrames.compactMap { phaseFrame in
                // An unencodable frame costs its overlay, not the whole session — persist the
                // cues and the remaining frames regardless.
                guard let keypointsJSON = try? encoder.encode(phaseFrame.frame),
                      let detectionsJSON = try? encoder.encode(phaseFrame.detections) else {
                    print("[AssessmentResult] could not encode phase frame \(phaseFrame.phase)")
                    return nil
                }
                return PhaseFrameRecord(
                    phaseKey: phaseFrame.phase,
                    frameTimestamp: phaseFrame.timestamp,
                    frameImageData: phaseFrame.imageData,
                    keypointsJSON: keypointsJSON,
                    detectionsJSON: detectionsJSON
                )
            }
            session.results.append(result)
        }
        context.insert(session)
    }
}
