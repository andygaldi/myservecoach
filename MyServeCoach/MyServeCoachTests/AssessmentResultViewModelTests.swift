import Foundation
import SwiftData
import Testing
@testable import MyServeCoach

@Suite("AssessmentResultViewModel Tests")
@MainActor
struct AssessmentResultViewModelTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([ServeSession.self, PhaseRecord.self, ServeResult.self, CueRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func cue(_ ruleId: String, phase: String, severity: String) -> Cue {
        Cue(ruleId: ruleId, phase: phase, message: "\(ruleId) message", severity: severity)
    }

    @Test("sorts cues major-before-minor, then by Kovacs phase order, within each serve")
    func sortsCuesMajorBeforeMinorWithinPhaseOrder() {
        let cues = [
            cue("c1", phase: "contact", severity: "minor"),
            cue("c2", phase: "trophy_pose", severity: "major"),
            cue("c3", phase: "release", severity: "major"),
            cue("c4", phase: "racket_drop", severity: "minor"),
        ]
        let results = [AssessmentServeResult(serveIndex: 0, coaching: CoachingResult(cues: cues, summary: nil))]
        let vm = AssessmentResultViewModel(results: results, inputType: "recorded", videoURL: nil)

        let ids = vm.serves[0].cues.map(\.ruleId)
        // Major cues first (release before trophy_pose, per Kovacs order), then minor cues
        // (racket_drop before contact).
        #expect(ids == ["c3", "c2", "c4", "c1"])
    }

    @Test("total major/minor counts sum across all serves")
    func totalCountsSumAcrossAllServes() {
        let results = [
            AssessmentServeResult(serveIndex: 0, coaching: CoachingResult(
                cues: [cue("a", phase: "contact", severity: "major"), cue("b", phase: "contact", severity: "minor")],
                summary: nil
            )),
            AssessmentServeResult(serveIndex: 1, coaching: CoachingResult(
                cues: [cue("c", phase: "contact", severity: "major")],
                summary: nil
            )),
        ]
        let vm = AssessmentResultViewModel(results: results, inputType: "recorded", videoURL: nil)

        #expect(vm.totalMajorCount == 2)
        #expect(vm.totalMinorCount == 1)
    }

    @Test("persist creates a ServeSession with mode pro2d and correctly cascaded results/cues")
    func persistCreatesServeSessionWithModePro2dAndCascadedResults() throws {
        let context = try makeInMemoryContext()
        let results = [
            AssessmentServeResult(serveIndex: 0, coaching: CoachingResult(
                cues: [cue("a", phase: "contact", severity: "major")], summary: nil
            )),
            AssessmentServeResult(serveIndex: 1, coaching: CoachingResult(cues: [], summary: "clean")),
        ]
        let vm = AssessmentResultViewModel(results: results, inputType: "imported", videoURL: nil)

        vm.persist(to: context)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<ServeSession>())
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.mode == "pro2d")
        #expect(session.inputType == "imported")
        #expect(session.results.count == 2)
        let sorted = session.results.sorted { $0.serveIndex < $1.serveIndex }
        #expect(sorted[0].cues.count == 1)
        #expect(sorted[0].cues.first?.ruleId == "a")
        #expect(sorted[1].summary == "clean")
    }
}
