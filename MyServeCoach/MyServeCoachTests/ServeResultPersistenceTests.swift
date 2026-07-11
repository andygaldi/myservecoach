import Foundation
import SwiftData
import Testing
@testable import MyServeCoach

@Suite("ServeResult / CueRecord Persistence Tests")
@MainActor
struct ServeResultPersistenceTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([ServeSession.self, PhaseRecord.self, ServeResult.self, CueRecord.self])
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
}
