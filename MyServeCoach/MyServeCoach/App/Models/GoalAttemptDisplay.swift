import Foundation

struct GoalAttemptDisplay: Identifiable, Sendable {
    let id = UUID()
    let segmentIndex: Int
    let passed: Bool
    let spokenCue: String
}
