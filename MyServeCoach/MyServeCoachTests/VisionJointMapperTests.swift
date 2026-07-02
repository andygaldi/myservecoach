import Foundation
import Testing
@testable import MyServeCoach

@Suite("VisionJointMapper Tests")
struct VisionJointMapperTests {

    @Test("translate maps all 14 documented keys and drops unmapped keys")
    func translateMapsDocumentedKeysAndDropsUnmapped() throws {
        let joints: [String: JointPoint] = [
            "right_wrist_joint": JointPoint(x: 0.1, y: 0.11, confidence: 0.91),
            "left_wrist_joint": JointPoint(x: 0.2, y: 0.21, confidence: 0.92),
            "right_elbow_joint": JointPoint(x: 0.3, y: 0.31, confidence: 0.93),
            "left_elbow_joint": JointPoint(x: 0.4, y: 0.41, confidence: 0.94),
            "right_shoulder_1_joint": JointPoint(x: 0.5, y: 0.51, confidence: 0.95),
            "left_shoulder_1_joint": JointPoint(x: 0.6, y: 0.61, confidence: 0.96),
            "right_hip_joint": JointPoint(x: 0.7, y: 0.71, confidence: 0.97),
            "left_hip_joint": JointPoint(x: 0.8, y: 0.81, confidence: 0.98),
            "right_knee_joint": JointPoint(x: 0.05, y: 0.15, confidence: 0.81),
            "left_knee_joint": JointPoint(x: 0.06, y: 0.16, confidence: 0.82),
            "right_ankle_joint": JointPoint(x: 0.07, y: 0.17, confidence: 0.83),
            "left_ankle_joint": JointPoint(x: 0.08, y: 0.18, confidence: 0.84),
            "neck_joint": JointPoint(x: 0.09, y: 0.19, confidence: 0.85),
            "root_joint": JointPoint(x: 0.10, y: 0.20, confidence: 0.86),
            "top_head_joint": JointPoint(x: 0.99, y: 0.99, confidence: 0.99),
        ]
        let frame = PoseFrame(timestamp: 2.5, joints: joints)

        let translated = VisionJointMapper.translate(frame)

        #expect(translated.timestamp == 2.5)
        #expect(translated.keypoints.count == 14)
        #expect(translated.keypoints["top_head"] == nil)

        for (visionKey, backendKey) in VisionJointMapper.jointNameMap {
            let original = try #require(joints[visionKey])
            let mapped = try #require(translated.keypoints[backendKey])
            #expect(mapped.x == original.x)
            #expect(mapped.y == original.y)
            #expect(mapped.confidence == original.confidence)
        }
    }
}
