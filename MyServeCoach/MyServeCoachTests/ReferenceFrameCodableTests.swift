import Foundation
import Testing
@testable import MyServeCoach

@Suite("ReferenceFrame Codable Tests")
struct ReferenceFrameCodableTests {

    private let sampleJSON = """
    {
      "reference_frames": [
        {
          "phase": "trophy_pose",
          "label": "Trophy Pose",
          "image_url": "http://localhost:8000/static/reference_frames/trophy_pose.jpg"
        },
        {
          "phase": "racket_drop",
          "label": "Racket Drop",
          "image_url": "http://localhost:8000/static/reference_frames/racket_drop.jpg"
        },
        {
          "phase": "contact",
          "label": "Contact Point",
          "image_url": "http://localhost:8000/static/reference_frames/contact.jpg"
        }
      ]
    }
    """

    @Test("ReferenceFrameLibrary decodes three frames in serve order")
    func decodesThreeFrames() throws {
        let data = try #require(sampleJSON.data(using: .utf8))
        let library = try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
        #expect(library.referenceFrames.count == 3)
        #expect(library.referenceFrames[0].phase == .trophyPose)
        #expect(library.referenceFrames[1].phase == .racketDrop)
        #expect(library.referenceFrames[2].phase == .contactPoint)
    }

    @Test("ReferenceFrame fields decode correctly")
    func decodesFields() throws {
        let data = try #require(sampleJSON.data(using: .utf8))
        let library = try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
        let frame = library.referenceFrames[0]
        #expect(frame.phase == .trophyPose)
        #expect(frame.label == "Trophy Pose")
        #expect(frame.imageURL.lastPathComponent == "trophy_pose.jpg")
    }

    @Test("Unknown phase key throws DecodingError")
    func unknownPhaseKeyThrows() throws {
        let bad = """
        {"reference_frames": [{"phase": "unknown", "label": "X", "image_url": "http://x/x.jpg"}]}
        """
        let data = try #require(bad.data(using: .utf8))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
        }
    }
}
