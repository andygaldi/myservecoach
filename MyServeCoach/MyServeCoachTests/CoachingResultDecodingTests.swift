import Foundation
import Testing
@testable import MyServeCoach

@Suite("CoachingResult Decoding Tests")
struct CoachingResultDecodingTests {

    private let sampleJSON = """
    {
      "cues": [
        {
          "rule_id": "trophy_racket_elbow_flexion",
          "phase": "trophy_pose",
          "message": "Elbow is under-flexed at trophy pose.",
          "severity": "minor"
        }
      ],
      "summary": "No major issues detected — good serve!"
    }
    """

    @Test("CoachingResult decodes the backend's AnalyzeResponse shape")
    func decodesAnalyzeResponseShape() throws {
        let data = try #require(sampleJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(CoachingResult.self, from: data)

        #expect(result.cues.count == 1)
        #expect(result.summary == "No major issues detected — good serve!")

        let cue = try #require(result.cues.first)
        #expect(cue.ruleId == "trophy_racket_elbow_flexion")
        #expect(cue.phase == "trophy_pose")
        #expect(cue.message == "Elbow is under-flexed at trophy pose.")
        #expect(cue.severity == "minor")
    }

    @Test("CoachingResult decodes a null summary and empty cues")
    func decodesEmptyCuesAndNullSummary() throws {
        let json = """
        { "cues": [], "summary": null }
        """
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(CoachingResult.self, from: data)

        #expect(result.cues.isEmpty)
        #expect(result.summary == nil)
    }

    // MARK: - P6c wire format

    @Test("a pre-P6c payload decodes with no phases and nil deviation fields")
    func decodesLegacyPayloadWithoutP6cFields() throws {
        // `sampleJSON` is exactly the pre-P6c shape: no `phases`, no cue deviation fields.
        let data = try #require(sampleJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(CoachingResult.self, from: data)

        #expect(result.phases.isEmpty)
        let cue = try #require(result.cues.first)
        #expect(cue.metric == nil)
        #expect(cue.joints.isEmpty)
        #expect(cue.measuredValue == nil)
        #expect(cue.comparison == nil)
        #expect(cue.threshold == nil)
        #expect(cue.thresholdMin == nil)
        #expect(cue.thresholdMax == nil)
    }

    @Test("CoachingResult decodes cue deviation detail and detected phases")
    func decodesDeviationDetailAndPhases() throws {
        let json = """
        {
          "cues": [
            {
              "rule_id": "trophy_toss_arm_vertical",
              "phase": "trophy_pose",
              "message": "Keep your tossing arm more vertical at the trophy pose.",
              "severity": "major",
              "metric": "angle_from_vertical",
              "joints": ["left_shoulder", "left_wrist"],
              "measured_value": 62.4,
              "comparison": "lte",
              "threshold": 45.0,
              "threshold_min": null,
              "threshold_max": null
            },
            {
              "rule_id": "racket_drop_ball_height",
              "phase": "racket_drop",
              "message": "Toss the ball not too high or too low.",
              "severity": "major",
              "metric": "ball_offset_y",
              "joints": ["left_shoulder"],
              "measured_value": 0.52,
              "comparison": "range",
              "threshold": null,
              "threshold_min": 0.28,
              "threshold_max": 0.40
            }
          ],
          "summary": null,
          "phases": [
            { "phase": "release", "frame_index": 3, "timestamp": 0.1 },
            { "phase": "trophy_pose", "frame_index": 7, "timestamp": 0.7 }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(CoachingResult.self, from: data)

        let vertical = try #require(result.cues.first)
        #expect(vertical.metric == "angle_from_vertical")
        #expect(vertical.joints == ["left_shoulder", "left_wrist"])
        #expect(vertical.measuredValue == 62.4)
        #expect(vertical.comparison == "lte")
        #expect(vertical.threshold == 45.0)
        #expect(vertical.thresholdMin == nil)

        let ballHeight = result.cues[1]
        #expect(ballHeight.comparison == "range")
        #expect(ballHeight.threshold == nil)
        #expect(ballHeight.thresholdMin == 0.28)
        #expect(ballHeight.thresholdMax == 0.40)

        #expect(result.phases.count == 2)
        #expect(result.phases[0].phase == "release")
        #expect(result.phases[0].frameIndex == 3)
        #expect(result.phases[1].timestamp == 0.7)
    }
}
