import Foundation
import Testing
import UIKit
@testable import MyServeCoach

@Suite("PersistedGoalAttemptDisplay Tests")
@MainActor
struct GoalSessionHistoryDetailViewTests {

    private func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        }
        return image.jpegData(compressionQuality: 0.7)!
    }

    private func cue(_ ruleId: String = "trophy_toss_arm_straight") -> Cue {
        Cue(
            ruleId: ruleId, phase: "trophy_pose", message: "Straighten your arm", severity: "major",
            metric: nil, joints: ["left_elbow"], measuredValue: nil, comparison: nil,
            threshold: nil, thresholdMin: nil, thresholdMax: nil
        )
    }

    private func attempt(
        segmentIndex: Int = 0, passed: Bool = false, spokenCue: String = "Keep arm straighter",
        phaseFrame: GoalPhaseFrameRecord? = nil
    ) -> GoalAttemptRecord {
        let record = GoalAttemptRecord(segmentIndex: segmentIndex, passed: passed, spokenCue: spokenCue)
        record.phaseFrame = phaseFrame
        return record
    }

    @Test("a missed serve's phase frame carries its still image, skeleton, and failing-joint highlight")
    func missedServeCarriesHighlight() throws {
        let frame = BackendFrame(timestamp: 1.5, keypoints: ["left_elbow": BackendKeypoint(x: 0.5, y: 0.5, confidence: 0.9)])
        let record = GoalPhaseFrameRecord(
            frameTimestamp: 1.5,
            frameImageData: jpeg(),
            keypointsJSON: try JSONEncoder().encode(frame),
            detectionsJSON: try JSONEncoder().encode([BackendDetection]()),
            cueJSON: try JSONEncoder().encode(cue())
        )

        let display = PersistedGoalAttemptDisplay(attempt(passed: false, phaseFrame: record))

        #expect(display.stillImage != nil)
        #expect(display.poseFrame?.keypoints["left_elbow"] != nil)
        #expect(display.highlightedCue?.ruleId == "trophy_toss_arm_straight")
    }

    @Test("a passed serve's phase frame shows the skeleton alone, with no highlight")
    func passedServeShowsSkeletonOnly() throws {
        let frame = BackendFrame(timestamp: 1.5, keypoints: [:])
        let record = GoalPhaseFrameRecord(
            frameTimestamp: 1.5,
            frameImageData: jpeg(),
            keypointsJSON: try JSONEncoder().encode(frame),
            detectionsJSON: try JSONEncoder().encode([BackendDetection]()),
            cueJSON: nil
        )

        let display = PersistedGoalAttemptDisplay(attempt(passed: true, spokenCue: "Nice serve", phaseFrame: record))

        #expect(display.stillImage != nil)
        #expect(display.poseFrame != nil)
        #expect(display.highlightedCue == nil)
    }

    @Test("no persisted phase frame degrades gracefully to a pass/fail-only row")
    func noPhaseFrameDegradesGracefully() {
        let display = PersistedGoalAttemptDisplay(attempt(phaseFrame: nil))

        #expect(display.stillImage == nil)
        #expect(display.poseFrame == nil)
        #expect(display.detections.isEmpty)
        #expect(display.highlightedCue == nil)
        #expect(display.spokenCue == "Keep arm straighter")
    }

    @Test("undecodable image data drops the still image but the row still carries its pass/fail text")
    func undecodableImageDropsStillImage() throws {
        let record = GoalPhaseFrameRecord(
            frameTimestamp: 1.5,
            frameImageData: Data("not an image".utf8),
            keypointsJSON: try JSONEncoder().encode(BackendFrame(timestamp: 1.5, keypoints: [:])),
            detectionsJSON: try JSONEncoder().encode([BackendDetection]()),
            cueJSON: nil
        )

        let display = PersistedGoalAttemptDisplay(attempt(phaseFrame: record))

        #expect(display.stillImage == nil)
        #expect(display.segmentIndex == 0)
        #expect(display.passed == false)
    }

    @Test("undecodable keypoints JSON still shows the image, without a skeleton")
    func undecodableKeypointsYieldsNoSkeleton() throws {
        let record = GoalPhaseFrameRecord(
            frameTimestamp: 1.5,
            frameImageData: jpeg(),
            keypointsJSON: Data("not json".utf8),
            detectionsJSON: try JSONEncoder().encode([BackendDetection]()),
            cueJSON: nil
        )

        let display = PersistedGoalAttemptDisplay(attempt(phaseFrame: record))

        #expect(display.stillImage != nil)
        #expect(display.poseFrame == nil)
    }
}
