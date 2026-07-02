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
}
