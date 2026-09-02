import Foundation
import SwiftData

@Model
final class GoalAttemptRecord {
    var id: UUID = UUID()
    var segmentIndex: Int = 0
    var passed: Bool = false
    var spokenCue: String = ""
    var timestamp: Date = Date.now
    var session: GoalSession?

    init(segmentIndex: Int, passed: Bool, spokenCue: String) {
        self.segmentIndex = segmentIndex
        self.passed = passed
        self.spokenCue = spokenCue
    }
}
