import Foundation
import SwiftData
import Testing
import UIKit
@testable import MyServeCoach

@Suite("AssessmentResultViewModel Tests")
@MainActor
struct AssessmentResultViewModelTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ServeSession.self, PhaseRecord.self, ServeResult.self, CueRecord.self,
            PhaseFrameRecord.self,
        ])
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

    // MARK: - Aggregation & sections (P6c)

    private func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        }
        return image.jpegData(compressionQuality: 0.7)!
    }

    private func phaseFrame(_ phase: String, timestamp: Double = 0) -> AssessmentPhaseFrame {
        AssessmentPhaseFrame(
            phase: phase,
            timestamp: timestamp,
            imageData: jpeg(),
            frame: BackendFrame(timestamp: timestamp, keypoints: [
                "left_shoulder": BackendKeypoint(x: 0.4, y: 0.6, confidence: 0.9),
            ]),
            detections: []
        )
    }

    private func serve(_ index: Int, cues: [Cue], frames: [AssessmentPhaseFrame] = [], summary: String? = nil) -> AssessmentServeResult {
        AssessmentServeResult(
            serveIndex: index,
            coaching: CoachingResult(cues: cues, summary: summary),
            phaseFrames: frames
        )
    }

    @Test("aggregates cues by ruleId across serves with a distinct-serve count")
    func aggregatesCuesByRuleIdAcrossServes() throws {
        let flagged = cue("trophy_toss_arm_vertical", phase: "trophy_pose", severity: "major")
        let vm = AssessmentResultViewModel(
            results: [
                serve(0, cues: [flagged]),
                serve(1, cues: [flagged]),
                serve(2, cues: [flagged]),
                serve(3, cues: []),
            ],
            inputType: "recorded", videoURL: nil
        )

        #expect(vm.aggregatedCues.count == 1)
        let row = try #require(vm.aggregatedCues.first)
        #expect(row.id == "trophy_toss_arm_vertical")
        #expect(row.flaggedServeCount == 3)
        #expect(row.totalServeCount == 4)
        #expect(row.subtitle == "3 of 4 serves · trophy pose")
    }

    @Test("a ruleId flagged twice within one serve counts that serve once")
    func duplicateRuleWithinServeCountsOnce() throws {
        // The same rule can fire on two phases within a single serve; the aggregate counts
        // *serves flagged*, so this must still read "1 of 2".
        let vm = AssessmentResultViewModel(
            results: [
                serve(0, cues: [
                    cue("r1", phase: "trophy_pose", severity: "major"),
                    cue("r1", phase: "contact", severity: "major"),
                ]),
                serve(1, cues: []),
            ],
            inputType: "recorded", videoURL: nil
        )

        let row = try #require(vm.aggregatedCues.first { $0.id == "r1" })
        #expect(row.flaggedServeCount == 1)
        #expect(row.totalServeCount == 2)
    }

    @Test("aggregated cues sort major-before-minor, then by descending flagged count")
    func aggregatedCuesSortBySeverityThenFrequency() {
        let vm = AssessmentResultViewModel(
            results: [
                serve(0, cues: [
                    cue("minorOften", phase: "contact", severity: "minor"),
                    cue("majorRare", phase: "contact", severity: "major"),
                ]),
                serve(1, cues: [
                    cue("minorOften", phase: "contact", severity: "minor"),
                    cue("majorOften", phase: "release", severity: "major"),
                ]),
                serve(2, cues: [
                    cue("minorOften", phase: "contact", severity: "minor"),
                    cue("majorOften", phase: "release", severity: "major"),
                ]),
            ],
            inputType: "recorded", videoURL: nil
        )

        // Both majors precede the minor even though the minor is the most frequent overall.
        #expect(vm.aggregatedCues.map(\.id) == ["majorOften", "majorRare", "minorOften"])
    }

    @Test("aggregated cues tie-break on Kovacs phase order when severity and count are equal")
    func aggregatedCuesTieBreakOnPhaseOrder() {
        // Same severity, same flagged count — only the phase distinguishes them, so the Kovacs
        // ordering (release → trophy_pose → racket_drop → contact) must decide.
        let vm = AssessmentResultViewModel(
            results: [serve(0, cues: [
                cue("contactRule", phase: "contact", severity: "major"),
                cue("dropRule", phase: "racket_drop", severity: "major"),
                cue("releaseRule", phase: "release", severity: "major"),
                cue("trophyRule", phase: "trophy_pose", severity: "major"),
            ])],
            inputType: "recorded", videoURL: nil
        )

        #expect(vm.aggregatedCues.map(\.id) == ["releaseRule", "trophyRule", "dropRule", "contactRule"])
    }

    @Test("aggregated cues are empty when no serve produced a cue")
    func aggregateIsEmptyForCleanSession() {
        let vm = AssessmentResultViewModel(
            results: [serve(0, cues: [], summary: "clean"), serve(1, cues: [], summary: "clean")],
            inputType: "recorded", videoURL: nil
        )

        #expect(vm.aggregatedCues.isEmpty)
    }

    @Test("a serve's cues are grouped under the phase frame that produced them")
    func cuesGroupUnderTheirPhaseFrame() throws {
        let vm = AssessmentResultViewModel(
            results: [serve(
                0,
                cues: [
                    cue("trophyRule", phase: "trophy_pose", severity: "major"),
                    cue("contactRule", phase: "contact", severity: "minor"),
                ],
                frames: [phaseFrame("trophy_pose"), phaseFrame("contact")]
            )],
            inputType: "recorded", videoURL: nil
        )

        let section = try #require(vm.sections.first)
        let trophy = try #require(section.phaseFrames.first { $0.phaseKey == "trophy_pose" })
        let contact = try #require(section.phaseFrames.first { $0.phaseKey == "contact" })

        #expect(trophy.cues.map(\.cue.ruleId) == ["trophyRule"])
        #expect(contact.cues.map(\.cue.ruleId) == ["contactRule"])
        #expect(section.unpairedCues.isEmpty)
    }

    @Test("a phase frame with no cues is still shown, with no highlight")
    func uncuedPhaseFrameStillShownWithoutHighlight() throws {
        let vm = AssessmentResultViewModel(
            results: [serve(0, cues: [], frames: [phaseFrame("release")], summary: "clean")],
            inputType: "recorded", videoURL: nil
        )

        let section = try #require(vm.sections.first)
        #expect(section.phaseFrames.count == 1)
        #expect(section.phaseFrames[0].highlightedCue == nil)
        #expect(section.hasNoCues)
    }

    @Test("a cue whose phase has no retained frame is still surfaced as an unpaired row")
    func cueWithoutFrameBecomesUnpairedRow() throws {
        let vm = AssessmentResultViewModel(
            results: [serve(
                0,
                cues: [cue("contactRule", phase: "contact", severity: "major")],
                frames: [phaseFrame("trophy_pose")]  // no contact frame retained
            )],
            inputType: "recorded", videoURL: nil
        )

        let section = try #require(vm.sections.first)
        #expect(section.unpairedCues.map(\.cue.ruleId) == ["contactRule"])
        #expect(section.hasNoCues == false)
    }

    @Test("phase frames carry the deviation caption for their cues")
    func phaseFramesCarryDeviationCaption() throws {
        let deviation = Cue(
            ruleId: "trophy_toss_arm_vertical", phase: "trophy_pose", message: "m", severity: "major",
            metric: "angle_from_vertical", joints: ["left_shoulder", "left_wrist"],
            measuredValue: 62.4, comparison: "lte", threshold: 45
        )
        let vm = AssessmentResultViewModel(
            results: [serve(0, cues: [deviation], frames: [phaseFrame("trophy_pose")])],
            inputType: "recorded", videoURL: nil
        )

        let caption = try #require(vm.sections.first?.phaseFrames.first?.cues.first?.deviationCaption)
        #expect(caption == "measured 62° · target ≤45°")
    }

    @Test("a cue without deviation detail yields no caption")
    func cueWithoutDeviationHasNoCaption() throws {
        let vm = AssessmentResultViewModel(
            results: [serve(0, cues: [cue("r1", phase: "trophy_pose", severity: "major")], frames: [phaseFrame("trophy_pose")])],
            inputType: "recorded", videoURL: nil
        )

        let display = try #require(vm.sections.first?.phaseFrames.first?.cues.first)
        #expect(display.deviationCaption == nil)
    }

    @Test("section ids are unique so ForEach cannot collapse rows")
    func sectionAndCueIdsAreUnique() {
        let vm = AssessmentResultViewModel(
            results: [
                serve(0, cues: [cue("r1", phase: "trophy_pose", severity: "major")], frames: [phaseFrame("trophy_pose")]),
                serve(1, cues: [cue("r1", phase: "trophy_pose", severity: "major")], frames: [phaseFrame("trophy_pose")]),
            ],
            inputType: "recorded", videoURL: nil
        )

        let sectionIds = vm.sections.map(\.id)
        let frameIds = vm.sections.flatMap { $0.phaseFrames.map(\.id) }
        let cueIds = vm.sections.flatMap { $0.phaseFrames.flatMap { $0.cues.map(\.id) } }

        #expect(Set(sectionIds).count == sectionIds.count)
        #expect(Set(frameIds).count == frameIds.count)
        #expect(Set(cueIds).count == cueIds.count)
    }
}
