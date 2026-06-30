import Foundation
import Testing
@testable import MyServeCoach

@Suite("ReferenceFrame Codable Tests")
struct ReferenceFrameCodableTests {

    private let sampleJSON = """
    {
      "reference_frames": {
        "trophy_pose": [
          {
            "phase": "trophy_pose",
            "label": "Trophy Pose",
            "image_url": "http://localhost:8000/static/reference_frames/trophy_pose.jpg"
          }
        ],
        "racket_drop": [
          {
            "phase": "racket_drop",
            "label": "Racket Drop",
            "image_url": "http://localhost:8000/static/reference_frames/racket_drop.jpg"
          }
        ],
        "contact": [
          {
            "phase": "contact",
            "label": "Contact Point",
            "image_url": "http://localhost:8000/static/reference_frames/contact.jpg"
          }
        ]
      }
    }
    """

    @Test("ReferenceFrameLibrary decodes three phases")
    func decodesThreePhases() throws {
        let data = try #require(sampleJSON.data(using: .utf8))
        let library = try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
        #expect(library.referenceFrames.count == 3)
        #expect(library.referenceFrames["trophy_pose"]?.count == 1)
        #expect(library.referenceFrames["racket_drop"]?.count == 1)
        #expect(library.referenceFrames["contact"]?.count == 1)
    }

    @Test("ReferenceFrame fields decode correctly")
    func decodesFields() throws {
        let data = try #require(sampleJSON.data(using: .utf8))
        let library = try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
        let frame = try #require(library.referenceFrames["trophy_pose"]?.first)
        #expect(frame.phase == .trophyPose)
        #expect(frame.label == "Trophy Pose")
        #expect(frame.imageURL.lastPathComponent == "trophy_pose.jpg")
    }

    @Test("Unknown phase key throws DecodingError")
    func unknownPhaseKeyThrows() throws {
        let bad = """
        {"reference_frames": {"trophy_pose": [{"phase": "unknown", "label": "X", "image_url": "http://x/x.jpg"}]}}
        """
        let data = try #require(bad.data(using: .utf8))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
        }
    }
}
