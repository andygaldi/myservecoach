import Foundation

struct GoalResult: Codable, Sendable {
    let passed: Bool
    let spokenCue: String
    enum CodingKeys: String, CodingKey { case passed; case spokenCue = "spoken_cue" }
}

struct GoalChunkResult: Decodable, Sendable {
    let segmentIndex: Int
    let goalResult: GoalResult
    enum CodingKeys: String, CodingKey { case segmentIndex = "segment_index"; case goalResult = "goal_result" }
}
