import Foundation

struct GoalDefinition: Identifiable, Hashable, Sendable {
    let ruleId: String
    let displayName: String
    let phase: String
    var id: String { ruleId }
}

/// Every `ruleId` here must match a `backend/rules.json` id verbatim — checked manually (Group 8's
/// cross-cutting verification), not synced automatically. The backend's `/v1/goal/session/chunk`
/// and `/v1/analyze` both 400 on an unrecognized `goal_rule_id`, so a drift here fails loudly at
/// runtime rather than silently.
enum GoalCatalog {
    static let all: [GoalDefinition] = [
        GoalDefinition(ruleId: "release_toss_arm_straight", displayName: "Toss arm straight at release", phase: "release"),
        GoalDefinition(ruleId: "release_toss_hand_eye_height", displayName: "Toss height at eye level", phase: "release"),
        GoalDefinition(ruleId: "trophy_hitting_elbow_shoulder_line", displayName: "Trophy pose elbow line", phase: "trophy_pose"),
        GoalDefinition(ruleId: "trophy_toss_arm_straight", displayName: "Trophy pose toss arm straight", phase: "trophy_pose"),
        GoalDefinition(ruleId: "trophy_toss_arm_vertical", displayName: "Trophy pose toss arm vertical", phase: "trophy_pose"),
        GoalDefinition(ruleId: "racket_drop_ball_height", displayName: "Racket drop toss height", phase: "racket_drop"),
        GoalDefinition(ruleId: "racket_drop_ball_front", displayName: "Racket drop toss placement", phase: "racket_drop"),
        GoalDefinition(ruleId: "contact_left_hip_angle", displayName: "Hip drive at contact", phase: "contact"),
        GoalDefinition(ruleId: "contact_shoulders_stacked", displayName: "Shoulders stacked at contact", phase: "contact"),
    ]
}
