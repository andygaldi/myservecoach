import Foundation
import SwiftData
import Testing
@testable import MyServeCoach

@Suite("ServeResult / CueRecord Persistence Tests")
@MainActor
struct ServeResultPersistenceTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ServeSession.self, PhaseRecord.self, ServeResult.self, CueRecord.self,
            PhaseFrameRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("a pro2d ServeSession with nested ServeResults and CueRecords round-trips correctly")
    func roundTripsProSessionWithResultsAndCues() throws {
        let context = try makeInMemoryContext()

        let session = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        let result1 = ServeResult(serveIndex: 0, summary: "clean")
        result1.cues = [CueRecord(ruleId: "r1", phase: "trophy_pose", message: "m1", severity: "major")]
        let result2 = ServeResult(serveIndex: 1, summary: nil)
        result2.cues = [
            CueRecord(ruleId: "r2", phase: "contact", message: "m2", severity: "minor"),
            CueRecord(ruleId: "r3", phase: "racket_drop", message: "m3", severity: "major"),
        ]
        session.results = [result1, result2]
        context.insert(session)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ServeSession>()).first
        let unwrapped = try #require(fetched)

        #expect(unwrapped.mode == "pro2d")
        #expect(unwrapped.results.count == 2)
        let sortedResults = unwrapped.results.sorted { $0.serveIndex < $1.serveIndex }
        #expect(sortedResults[0].cues.count == 1)
        #expect(sortedResults[1].cues.count == 2)
        #expect(sortedResults[0].summary == "clean")
        #expect(sortedResults[1].summary == nil)
    }

    @Test("deleting the session cascades to delete its results and cues")
    func cascadeDeleteRemovesResultsAndCues() throws {
        let context = try makeInMemoryContext()

        let session = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        let result = ServeResult(serveIndex: 0, summary: nil)
        result.cues = [CueRecord(ruleId: "r1", phase: "trophy_pose", message: "m1", severity: "major")]
        session.results = [result]
        context.insert(session)
        try context.save()

        context.delete(session)
        try context.save()

        let remainingResults = try context.fetch(FetchDescriptor<ServeResult>())
        let remainingCues = try context.fetch(FetchDescriptor<CueRecord>())
        #expect(remainingResults.isEmpty)
        #expect(remainingCues.isEmpty)
    }

    @Test("a session constructed without an explicit mode defaults to lite")
    func defaultModeIsLite() throws {
        let context = try makeInMemoryContext()
        let session = ServeSession(inputType: "recorded", videoURL: nil)
        context.insert(session)
        try context.save()

        #expect(session.mode == "lite")
        #expect(session.results.isEmpty)
    }

    // MARK: - Phase frames & cue deviation detail (P6c)

    private func makePhaseFrame(_ phase: String, timestamp: Double) -> AssessmentPhaseFrame {
        AssessmentPhaseFrame(
            phase: phase,
            timestamp: timestamp,
            imageData: Data("jpeg-\(phase)".utf8),
            frame: BackendFrame(timestamp: timestamp, keypoints: [
                "left_shoulder": BackendKeypoint(x: 0.4, y: 0.6, confidence: 0.9),
                "left_wrist": BackendKeypoint(x: 0.8, y: 0.9, confidence: 0.8),
            ]),
            detections: [BackendDetection(
                label: "ball", confidence: 0.9,
                bbox: BackendBoundingBox(xMin: 0.43, yMin: 0.93, xMax: 0.47, yMax: 0.97)
            )]
        )
    }

    private func deviationCue() -> Cue {
        Cue(
            ruleId: "trophy_toss_arm_vertical",
            phase: "trophy_pose",
            message: "Keep your tossing arm more vertical.",
            severity: "major",
            metric: "angle_from_vertical",
            joints: ["left_shoulder", "left_wrist"],
            measuredValue: 62.4,
            comparison: "lte",
            threshold: 45.0
        )
    }

    @Test("persisted phase frames round-trip their phase key, timestamp, image and keypoints")
    func phaseFramesRoundTrip() throws {
        let context = try makeInMemoryContext()
        let viewModel = AssessmentResultViewModel(
            results: [AssessmentServeResult(
                serveIndex: 0,
                coaching: CoachingResult(cues: [deviationCue()], summary: nil),
                phaseFrames: [
                    makePhaseFrame("release", timestamp: 0.1),
                    makePhaseFrame("trophy_pose", timestamp: 0.7),
                ]
            )],
            inputType: "recorded",
            videoURL: nil
        )

        viewModel.persist(to: context)
        try context.save()

        let session = try #require(try context.fetch(FetchDescriptor<ServeSession>()).first)
        let result = try #require(session.results.first)
        let frames = result.phaseFrames.sorted { $0.frameTimestamp < $1.frameTimestamp }

        #expect(frames.map(\.phaseKey) == ["release", "trophy_pose"])
        #expect(frames[1].frameTimestamp == 0.7)
        #expect(!frames[1].frameImageData.isEmpty)

        let decoded = try JSONDecoder().decode(BackendFrame.self, from: frames[1].keypointsJSON)
        #expect(decoded.timestamp == 0.7)
        #expect(decoded.keypoints["left_shoulder"]?.x == 0.4)
        #expect(decoded.keypoints["left_wrist"]?.confidence == 0.8)

        let decodedDetections = try JSONDecoder().decode([BackendDetection].self, from: frames[1].detectionsJSON)
        #expect(decodedDetections.count == 1)
        #expect(decodedDetections[0].label == "ball")
    }

    @Test("persisted cues round-trip their deviation detail")
    func cueDeviationDetailRoundTrips() throws {
        let context = try makeInMemoryContext()
        let viewModel = AssessmentResultViewModel(
            results: [AssessmentServeResult(
                serveIndex: 0,
                coaching: CoachingResult(cues: [deviationCue()], summary: nil)
            )],
            inputType: "recorded",
            videoURL: nil
        )

        viewModel.persist(to: context)
        try context.save()

        let session = try #require(try context.fetch(FetchDescriptor<ServeSession>()).first)
        let cue = try #require(session.results.first?.cues.first)

        #expect(cue.metric == "angle_from_vertical")
        #expect(cue.joints == ["left_shoulder", "left_wrist"])
        #expect(cue.measuredValue == 62.4)
        #expect(cue.comparison == "lte")
        #expect(cue.threshold == 45.0)
        #expect(cue.thresholdMin == nil)
        #expect(cue.thresholdMax == nil)
    }

    @Test("a cue persisted without deviation detail keeps nil fields")
    func cueWithoutDeviationDetailPersistsNils() throws {
        let context = try makeInMemoryContext()
        let cue = Cue(ruleId: "r1", phase: "contact", message: "m1", severity: "minor")
        let viewModel = AssessmentResultViewModel(
            results: [AssessmentServeResult(serveIndex: 0, coaching: CoachingResult(cues: [cue], summary: nil))],
            inputType: "recorded",
            videoURL: nil
        )

        viewModel.persist(to: context)
        try context.save()

        let session = try #require(try context.fetch(FetchDescriptor<ServeSession>()).first)
        let persisted = try #require(session.results.first?.cues.first)

        #expect(persisted.metric == nil)
        #expect(persisted.joints.isEmpty)
        #expect(persisted.measuredValue == nil)
    }

    @Test("deleting the session cascades to delete its phase frames")
    func cascadeDeleteRemovesPhaseFrames() throws {
        let context = try makeInMemoryContext()
        let viewModel = AssessmentResultViewModel(
            results: [AssessmentServeResult(
                serveIndex: 0,
                coaching: CoachingResult(cues: [], summary: nil),
                phaseFrames: [makePhaseFrame("contact", timestamp: 1.2)]
            )],
            inputType: "recorded",
            videoURL: nil
        )
        viewModel.persist(to: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<PhaseFrameRecord>()).count == 1)

        let session = try #require(try context.fetch(FetchDescriptor<ServeSession>()).first)
        context.delete(session)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PhaseFrameRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ServeResult>()).isEmpty)
    }
}
