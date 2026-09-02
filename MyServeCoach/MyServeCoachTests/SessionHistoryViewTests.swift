import Foundation
import SwiftData
import Testing
@testable import MyServeCoach

@Suite("SessionHistoryView merge Tests")
struct SessionHistoryViewTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([ServeSession.self, GoalSession.self, GoalAttemptRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("merge() interleaves ServeSession and GoalSession entries sorted by date, newest first")
    func mergeSortsAcrossBothTypes() {
        let now = Date.now
        let oldServe = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        oldServe.date = now.addingTimeInterval(-3600)
        let midGoal = GoalSession(goalRuleId: "release_toss_arm_straight", goalDisplayName: "Toss arm straight", videoURL: nil)
        midGoal.date = now.addingTimeInterval(-1800)
        let newServe = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        newServe.date = now

        let entries = SessionHistoryView.merge(sessions: [oldServe, newServe], goalSessions: [midGoal])

        #expect(entries.map(\.id) == [newServe.id, midGoal.id, oldServe.id])
        #expect(entries.map(\.isGoal) == [false, true, false])
    }

    @Test("deleting a GoalSession row leaves other sessions intact")
    func deletingGoalSessionLeavesOthersIntact() throws {
        let context = try makeInMemoryContext()
        let now = Date.now
        let serve = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        serve.date = now.addingTimeInterval(-60)
        let goal = GoalSession(goalRuleId: "release_toss_arm_straight", goalDisplayName: "Toss arm straight", videoURL: nil)
        goal.date = now
        context.insert(serve)
        context.insert(goal)
        try context.save()

        let entries = SessionHistoryView.merge(sessions: [serve], goalSessions: [goal])
        // Mirrors SessionHistoryView's .onDelete: map an offset in the merged list back to the
        // underlying model before deleting.
        let indexToDelete = 0
        #expect(entries[indexToDelete].isGoal == true)
        switch entries[indexToDelete] {
        case .serve(let s): context.delete(s)
        case .goal(let g): context.delete(g)
        }
        try context.save()

        let remainingServes = try context.fetch(FetchDescriptor<ServeSession>())
        let remainingGoals = try context.fetch(FetchDescriptor<GoalSession>())
        #expect(remainingServes.count == 1)
        #expect(remainingServes.first?.id == serve.id)
        #expect(remainingGoals.isEmpty)
    }
}
