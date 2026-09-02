import Foundation
import SwiftData

@Model
final class GoalSession {
    var id: UUID = UUID()
    var date: Date = Date.now
    var goalRuleId: String = ""
    var goalDisplayName: String = ""
    var videoURL: URL?
    @Relationship(deleteRule: .cascade) var attempts: [GoalAttemptRecord] = []

    init(goalRuleId: String, goalDisplayName: String, videoURL: URL?) {
        self.goalRuleId = goalRuleId
        self.goalDisplayName = goalDisplayName
        self.videoURL = videoURL
    }
}
