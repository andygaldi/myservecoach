import Testing
@testable import MyServeCoach

@Suite("GoalCatalog Tests")
struct GoalCatalogTests {

    @Test("catalog has exactly 9 entries")
    func hasNineEntries() {
        #expect(GoalCatalog.all.count == 9)
    }

    @Test("every entry has a non-empty displayName")
    func everyEntryHasDisplayName() {
        #expect(GoalCatalog.all.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("every ruleId is unique across the list")
    func ruleIdsAreUnique() {
        let ruleIds = GoalCatalog.all.map(\.ruleId)
        #expect(Set(ruleIds).count == ruleIds.count)
    }
}
