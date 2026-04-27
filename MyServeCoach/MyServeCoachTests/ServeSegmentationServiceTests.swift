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

    // MARK: - Boundary conditions

    @Test("gap of exactly kMinGapFrames transitions → gap detected, 2 segments")
    func gapAtExactMinimum() {
        // 16 quiet frames produce exactly 15 quiet-to-quiet transitions = kMinGapFrames.
        let frames = activeFrames(count: 20) + quietFrames(count: 16) + activeFrames(count: 20)
        let segments = service.segment(frames: frames)
        #expect(segments.count == 2)
        #expect(segments[0].count == 20)
        #expect(segments[1].count == 20)
    }

    @Test("gap of kMinGapFrames − 1 transitions → no gap, 1 segment")
    func gapJustBelowMinimum() {
        // 15 quiet frames produce 14 transitions, one short of kMinGapFrames.
        let frames = activeFrames(count: 20) + quietFrames(count: 15) + activeFrames(count: 20)
        let segments = service.segment(frames: frames)
        #expect(segments.count == 1)
    }

    @Test("segment of exactly kMinServeFrames → included")
    func segmentAtExactMinimum() {
        // First burst is exactly kMinServeFrames long — must not be dropped.
        let frames = activeFrames(count: PoseConstants.kMinServeFrames) + quietFrames(count: 16) + activeFrames(count: 20)
        let segments = service.segment(frames: frames)
        #expect(segments.count == 2)
        #expect(segments[0].count == PoseConstants.kMinServeFrames)
    }

    @Test("segment of kMinServeFrames − 1 → excluded")
    func segmentJustBelowMinimum() {
        // First burst is one frame too short — should be discarded.
        let frames = activeFrames(count: PoseConstants.kMinServeFrames - 1) + quietFrames(count: 16) + activeFrames(count: 20)
        let segments = service.segment(frames: frames)
        #expect(segments.count == 1)
        #expect(segments[0].count == 20)
    }

    @Test("zero-joint frames produce velocity=0 but do not cause false gaps")
    func zeroJointFramesNoFalseGap() {
        // Frames with empty joints have no shared joints with neighbours, so
        // meanDisplacement returns 0 — identical to a quiet frame. Two such frames
        // produce only 3 zero-velocity transitions (well below kMinGapFrames=15),
        // so no gap is detected and the whole sequence stays as one segment.
        let emptyFrame = PoseFrame(timestamp: 0, joints: [:])
        let frames = activeFrames(count: 20) + [emptyFrame, emptyFrame] + activeFrames(count: 20)
        let segments = service.segment(frames: frames)
        #expect(segments.count == 1)
        #expect(segments[0].count == 42)
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
