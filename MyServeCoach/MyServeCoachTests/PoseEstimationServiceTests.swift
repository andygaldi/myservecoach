import Testing
@testable import MyServeCoach

@Suite("PoseEstimationService Tests")
struct PoseEstimationServiceTests {

    private typealias Raw = [String: (x: Float, y: Float, confidence: Float)]

    @Test("joints above threshold → PoseFrame returned with correct timestamp and joints")
    func happyPath() {
        let raw: Raw = [
            "left_wrist_joint":       (x: 0.1, y: 0.5, confidence: 0.9),
            "right_wrist_joint":      (x: 0.9, y: 0.5, confidence: 0.8),
            "left_shoulder_1_joint":  (x: 0.2, y: 0.3, confidence: 0.7),
            "right_shoulder_1_joint": (x: 0.8, y: 0.3, confidence: 0.6),
        ]
        let frame = PoseEstimationService.assembleFrame(at: 1.5, from: raw, confidenceThreshold: 0.3)
        #expect(frame != nil)
        #expect(frame?.timestamp == 1.5)
        #expect(frame?.joints.count == 4)
    }

    @Test("joints below confidence threshold are excluded; high-confidence ones kept")
    func confidenceFiltering() {
        let raw: Raw = [
            "left_wrist_joint":       (x: 0.1, y: 0.5, confidence: 0.9),
            "right_wrist_joint":      (x: 0.9, y: 0.5, confidence: 0.8),
            "left_shoulder_1_joint":  (x: 0.2, y: 0.3, confidence: 0.7),
            "right_shoulder_1_joint": (x: 0.8, y: 0.3, confidence: 0.6),
            "left_elbow_1_joint":     (x: 0.3, y: 0.4, confidence: 0.1),  // below threshold
            "right_elbow_1_joint":    (x: 0.7, y: 0.4, confidence: 0.2),  // below threshold
        ]
        let frame = PoseEstimationService.assembleFrame(at: 0.5, from: raw, confidenceThreshold: 0.3)
        #expect(frame != nil)
        #expect(frame?.joints.count == 4)
        #expect(frame?.joints["left_elbow_1_joint"] == nil)
        #expect(frame?.joints["right_elbow_1_joint"] == nil)
    }

    @Test("exactly kMinJointCount joints → frame returned; one fewer → nil")
    func jointCountBoundary() {
        let makeRaw: (Int) -> Raw = { count in
            Dictionary(uniqueKeysWithValues: (0..<count).map { i in
                ("joint_\(i)", (x: Float(i) * 0.1, y: 0.5, confidence: 0.9))
            })
        }
        let atMin = PoseEstimationService.assembleFrame(
            at: 0, from: makeRaw(PoseConstants.kMinJointCount), confidenceThreshold: 0.3)
        let belowMin = PoseEstimationService.assembleFrame(
            at: 0, from: makeRaw(PoseConstants.kMinJointCount - 1), confidenceThreshold: 0.3)
        #expect(atMin != nil)
        #expect(belowMin == nil)
    }
}
