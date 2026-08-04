import Foundation
import SwiftData
import Testing
import UIKit
@testable import MyServeCoach

@Suite("AssessmentHistoryPresenter Tests")
@MainActor
struct AssessmentHistoryPresenterTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ServeSession.self, PhaseRecord.self, ServeResult.self, CueRecord.self,
            PhaseFrameRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        }
        return image.jpegData(compressionQuality: 0.7)!
    }

    private func keypointsJSON() throws -> Data {
        try JSONEncoder().encode(BackendFrame(timestamp: 0.7, keypoints: [
            "left_shoulder": BackendKeypoint(x: 0.4, y: 0.6, confidence: 0.9),
            "left_wrist": BackendKeypoint(x: 0.8, y: 0.9, confidence: 0.9),
        ]))
    }

    private func cueRecord(
        _ ruleId: String, phase: String, severity: String = "major", withDeviation: Bool = false
    ) -> CueRecord {
        CueRecord(
            ruleId: ruleId, phase: phase, message: "\(ruleId) message", severity: severity,
            metric: withDeviation ? "angle_from_vertical" : nil,
            joints: withDeviation ? ["left_shoulder", "left_wrist"] : [],
            measuredValue: withDeviation ? 62.4 : nil,
            comparison: withDeviation ? "lte" : nil,
            threshold: withDeviation ? 45 : nil
        )
    }

    private func phaseFrameRecord(
        _ phase: String, imageData: Data? = nil, keypoints: Data? = nil
    ) throws -> PhaseFrameRecord {
        PhaseFrameRecord(
            phaseKey: phase,
            frameTimestamp: 0.7,
            frameImageData: imageData ?? jpeg(),
            keypointsJSON: try keypoints ?? keypointsJSON(),
            detectionsJSON: try JSONEncoder().encode([BackendDetection]())
        )
    }

    /// Builds and persists a session so the presenter is exercised against real SwiftData
    /// objects, not in-memory structs.
    private func persist(_ results: [ServeResult], in context: ModelContext) throws -> ServeSession {
        let session = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        session.results = results
        context.insert(session)
        try context.save()
        return session
    }

    // MARK: - Aggregation parity

    @Test("aggregates persisted CueRecords across serves with a distinct-serve count")
    func aggregatesPersistedCuesAcrossServes() throws {
        let context = try makeInMemoryContext()
        let results = (0..<3).map { index -> ServeResult in
            let result = ServeResult(serveIndex: index, summary: nil)
            result.cues = index < 2
                ? [cueRecord("trophy_toss_arm_vertical", phase: "trophy_pose")]
                : []
            return result
        }
        let session = try persist(results, in: context)

        let presenter = AssessmentHistoryPresenter(session: session)

        #expect(presenter.serveCount == 3)
        #expect(presenter.majorCount == 2)
        let row = try #require(presenter.aggregatedCues.first)
        #expect(row.id == "trophy_toss_arm_vertical")
        #expect(row.flaggedServeCount == 2)
        #expect(row.totalServeCount == 3)
    }

    @Test("sections are ordered by serve index regardless of stored relationship order")
    func sectionsOrderedByServeIndex() throws {
        let context = try makeInMemoryContext()
        let results = [2, 0, 1].map { ServeResult(serveIndex: $0, summary: nil) }
        let session = try persist(results, in: context)

        let presenter = AssessmentHistoryPresenter(session: session)

        #expect(presenter.sections.map(\.serveIndex) == [0, 1, 2])
    }

    // MARK: - Phase frames

    @Test("persisted phase frames rebuild with their image, keypoints and cues")
    func phaseFramesRebuildWithKeypointsAndCues() throws {
        let context = try makeInMemoryContext()
        let result = ServeResult(serveIndex: 0, summary: nil)
        result.cues = [cueRecord("trophy_toss_arm_vertical", phase: "trophy_pose", withDeviation: true)]
        result.phaseFrames = [try phaseFrameRecord("trophy_pose")]
        let session = try persist([result], in: context)

        let presenter = AssessmentHistoryPresenter(session: session)
        let frame = try #require(presenter.sections.first?.phaseFrames.first)

        #expect(frame.phaseKey == "trophy_pose")
        #expect(frame.label == "Trophy pose")
        #expect(frame.frame?.keypoints["left_shoulder"] != nil)
        #expect(frame.cues.count == 1)
        #expect(frame.highlightedCue?.ruleId == "trophy_toss_arm_vertical")
        #expect(frame.cues.first?.deviationCaption == "measured 62° · target ≤45°")
        #expect(presenter.sections.first?.unpairedCues.isEmpty == true)
    }

    @Test("phase frames are ordered by the Kovacs displayed-phase order, not storage order")
    func phaseFramesOrderedByDisplayOrder() throws {
        let context = try makeInMemoryContext()
        let result = ServeResult(serveIndex: 0, summary: nil)
        result.phaseFrames = [
            try phaseFrameRecord("contact"),
            try phaseFrameRecord("release"),
            try phaseFrameRecord("trophy_pose"),
        ]
        let session = try persist([result], in: context)

        let presenter = AssessmentHistoryPresenter(session: session)

        #expect(presenter.sections.first?.phaseFrames.map(\.phaseKey) == ["release", "trophy_pose", "contact"])
    }

    @Test("the overlay cue is rehydrated with its full deviation detail so the ideal can be drawn")
    func rehydratedCueCarriesDeviationDetail() throws {
        let context = try makeInMemoryContext()
        let result = ServeResult(serveIndex: 0, summary: nil)
        result.cues = [cueRecord("trophy_toss_arm_vertical", phase: "trophy_pose", withDeviation: true)]
        result.phaseFrames = [try phaseFrameRecord("trophy_pose")]
        let session = try persist([result], in: context)

        let presenter = AssessmentHistoryPresenter(session: session)
        let cue = try #require(presenter.sections.first?.phaseFrames.first?.highlightedCue)
        let frame = try #require(presenter.sections.first?.phaseFrames.first?.frame)

        #expect(cue.metric == "angle_from_vertical")
        #expect(cue.joints == ["left_shoulder", "left_wrist"])
        // The rehydrated cue must be enough to produce an actual indicator, not just carry fields.
        #expect(CueOverlayGeometry.indicator(for: cue, in: frame, detections: []) != nil)
    }

    // MARK: - Graceful degradation

    @Test("a pre-P6c session with no phase frames yields no frame blocks and no captions")
    func preP6cSessionDegradesToTextOnly() throws {
        let context = try makeInMemoryContext()
        let result = ServeResult(serveIndex: 0, summary: nil)
        result.cues = [cueRecord("r1", phase: "trophy_pose")]  // no deviation detail, no frames
        let session = try persist([result], in: context)

        let presenter = AssessmentHistoryPresenter(session: session)
        let section = try #require(presenter.sections.first)

        #expect(section.phaseFrames.isEmpty)
        #expect(section.unpairedCues.count == 1)
        #expect(section.unpairedCues[0].deviationCaption == nil)
        #expect(presenter.aggregatedCues.count == 1)  // aggregation still works without frames
    }

    @Test("undecodable keypoints JSON yields a frame block with no skeleton")
    func undecodableKeypointsYieldFrameWithoutSkeleton() throws {
        let context = try makeInMemoryContext()
        let result = ServeResult(serveIndex: 0, summary: nil)
        result.phaseFrames = [try phaseFrameRecord("contact", keypoints: Data("not json".utf8))]
        let session = try persist([result], in: context)

        let presenter = AssessmentHistoryPresenter(session: session)
        let frame = try #require(presenter.sections.first?.phaseFrames.first)

        #expect(frame.frame == nil)      // no skeleton
        #expect(frame.phaseKey == "contact")  // but the frame block is still rendered
    }

    @Test("an undecodable image drops the frame block but keeps its cues as rows")
    func undecodableImageKeepsCues() throws {
        let context = try makeInMemoryContext()
        let result = ServeResult(serveIndex: 0, summary: nil)
        result.cues = [cueRecord("contactRule", phase: "contact")]
        result.phaseFrames = [try phaseFrameRecord("contact", imageData: Data("not an image".utf8))]
        let session = try persist([result], in: context)

        let presenter = AssessmentHistoryPresenter(session: session)
        let section = try #require(presenter.sections.first)

        #expect(section.phaseFrames.isEmpty)
        #expect(section.unpairedCues.map(\.cue.ruleId) == ["contactRule"])
    }

    @Test("a clean persisted serve keeps its summary and reports no cues")
    func cleanServeKeepsSummary() throws {
        let context = try makeInMemoryContext()
        let result = ServeResult(serveIndex: 0, summary: "No major issues detected — good serve!")
        result.phaseFrames = [try phaseFrameRecord("contact")]
        let session = try persist([result], in: context)

        let presenter = AssessmentHistoryPresenter(session: session)
        let section = try #require(presenter.sections.first)

        #expect(section.hasNoCues)
        #expect(section.summary == "No major issues detected — good serve!")
        #expect(presenter.aggregatedCues.isEmpty)
    }

    @Test("an empty session renders no sections rather than crashing")
    func emptySessionRendersNothing() throws {
        let context = try makeInMemoryContext()
        let session = try persist([], in: context)

        let presenter = AssessmentHistoryPresenter(session: session)

        #expect(presenter.sections.isEmpty)
        #expect(presenter.aggregatedCues.isEmpty)
        #expect(presenter.serveCount == 0)
    }
}
