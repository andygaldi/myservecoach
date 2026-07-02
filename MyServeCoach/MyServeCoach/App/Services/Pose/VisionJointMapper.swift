import Foundation

/// Translates Vision-derived `PoseFrame.joints` (raw `*_joint` key names) into the
/// backend's keypoint schema (`right_wrist`, `left_shoulder`, etc.), per the mapping
/// table in `specs/offdevice-pipeline.md`.
enum VisionJointMapper {
    static let jointNameMap: [String: String] = [
        "right_wrist_joint": "right_wrist",
        "left_wrist_joint": "left_wrist",
        "right_elbow_joint": "right_elbow",
        "left_elbow_joint": "left_elbow",
        "right_shoulder_1_joint": "right_shoulder",
        "left_shoulder_1_joint": "left_shoulder",
        "right_hip_joint": "right_hip",
        "left_hip_joint": "left_hip",
        "right_knee_joint": "right_knee",
        "left_knee_joint": "left_knee",
        "right_ankle_joint": "right_ankle",
        "left_ankle_joint": "left_ankle",
        "neck_joint": "neck",
        "root_joint": "pelvis",
    ]

    static func translate(_ frame: PoseFrame) -> BackendFrame {
        var keypoints: [String: BackendKeypoint] = [:]
        for (visionKey, point) in frame.joints {
            guard let backendKey = jointNameMap[visionKey] else { continue }
            keypoints[backendKey] = BackendKeypoint(x: point.x, y: point.y, confidence: point.confidence)
        }
        return BackendFrame(timestamp: frame.timestamp, keypoints: keypoints)
    }
}
