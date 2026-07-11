import Foundation
import Observation
import SwiftData

struct AssessmentServeDisplay: Identifiable {
    let id = UUID()
    let serveIndex: Int
    let summary: String?
    let cues: [Cue]  // pre-sorted: major before minor, then Kovacs phase order
}

@MainActor
@Observable
final class AssessmentResultViewModel {
    let serves: [AssessmentServeDisplay]
    let inputType: String
    private let videoURL: URL?

    var totalMajorCount: Int { serves.flatMap(\.cues).filter { $0.severity == "major" }.count }
    var totalMinorCount: Int { serves.flatMap(\.cues).filter { $0.severity == "minor" }.count }

    init(results: [AssessmentServeResult], inputType: String, videoURL: URL?) {
        self.inputType = inputType
        self.videoURL = videoURL
        self.serves = results.map { result in
            AssessmentServeDisplay(
                serveIndex: result.serveIndex,
                summary: result.coaching.summary,
                cues: result.coaching.cues.sortedByCoachingPriority()
            )
        }
    }

    func persist(to context: ModelContext) {
        let session = ServeSession(inputType: inputType, videoURL: videoURL, mode: "pro2d")
        for serve in serves {
            let result = ServeResult(serveIndex: serve.serveIndex, summary: serve.summary)
            result.cues = serve.cues.map {
                CueRecord(ruleId: $0.ruleId, phase: $0.phase, message: $0.message, severity: $0.severity)
            }
            session.results.append(result)
        }
        context.insert(session)
    }
}
