import Foundation
import Testing
@testable import MyServeCoach

@Suite("ServeSegmentationService Tests")
struct ServeSegmentationServiceTests {

    private let service = ServeSegmentationService()

    // MARK: - Segmentation cases

    @Test("two bursts separated by a long gap → 2 segments")
    func twoBurstsWithGap() {
        // 20 active + 17 quiet + 20 active.
        // The 17 quiet frames produce 16 zero-velocity transitions — just above
        // kMinGapFrames (15), so they form exactly one gap boundary.
        let frames = activeFrames(count: 20) + quietFrames(count: 17) + activeFrames(count: 20)
        let segments = service.segment(frames: frames)
        #expect(segments.count == 2)
        #expect(segments[0].count == 20)
        #expect(segments[1].count == 20)
    }

    @Test("single continuous burst → 1 segment")
    func singleBurst() {
        let segments = service.segment(frames: activeFrames(count: 20))
        #expect(segments.count == 1)
    }

    @Test("burst shorter than kMinServeFrames → 0 segments")
    func shortBurst() {
        let frames = activeFrames(count: PoseConstants.kMinServeFrames - 2)
        let segments = service.segment(frames: frames)
        #expect(segments.count == 0)
    }

    @Test("empty input → 0 segments")
    func emptyInput() {
        #expect(service.segment(frames: []).count == 0)
    }

    // MARK: - Frame builders

    /// Joints move 0.05 normalised units per step — well above kVelocityThreshold.
    private func activeFrames(count: Int) -> [PoseFrame] {
        (0..<count).map { i in
            let x = Float(i) * 0.05
            return PoseFrame(
                timestamp: Double(i) * 0.1,
                joints: [
                    "left_wrist_joint":       JointPoint(x: x,           y: 0.5, confidence: 0.9),
                    "right_wrist_joint":      JointPoint(x: 1 - x,       y: 0.5, confidence: 0.9),
                    "left_shoulder_1_joint":  JointPoint(x: x * 0.5,     y: 0.3, confidence: 0.9),
                    "right_shoulder_1_joint": JointPoint(x: 1 - x * 0.5, y: 0.3, confidence: 0.9)
                ]
            )
        }
    }

    /// All joints stationary — velocity between every consecutive pair is exactly 0.
    private func quietFrames(count: Int) -> [PoseFrame] {
        (0..<count).map { i in
            PoseFrame(
                timestamp: Double(i) * 0.1,
                joints: [
                    "left_wrist_joint":       JointPoint(x: 0.5, y: 0.5, confidence: 0.9),
                    "right_wrist_joint":      JointPoint(x: 0.5, y: 0.5, confidence: 0.9),
                    "left_shoulder_1_joint":  JointPoint(x: 0.3, y: 0.3, confidence: 0.9),
                    "right_shoulder_1_joint": JointPoint(x: 0.7, y: 0.3, confidence: 0.9)
                ]
            )
        }
    }
}
