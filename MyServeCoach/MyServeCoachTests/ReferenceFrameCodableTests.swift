import Foundation
import Testing
@testable import MyServeCoach

@Suite("ReferenceFrame Codable Tests")
struct ReferenceFrameCodableTests {

    private let sampleJSON = """
    {
      "reference_frames": {
        "trophy_pose": {
          "phase": "trophy_pose",
          "label": "Trophy Pose",
          "image_url": "http://localhost:8000/static/reference_frames/trophy_pose.jpg"
        },
        "racket_drop": {
          "phase": "racket_drop",
          "label": "Racket Drop",
          "image_url": "http://localhost:8000/static/reference_frames/racket_drop.jpg"
        },
        "contact": {
          "phase": "contact",
          "label": "Contact Point",
          "image_url": "http://localhost:8000/static/reference_frames/contact.jpg"
        }
      }
    }
    """

    @Test("ReferenceFrameLibrary decodes three phases from JSON")
    func decodesThreePhases() throws {
        let data = try #require(sampleJSON.data(using: .utf8))
        let library = try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
        #expect(library.referenceFrames.count == 3)
        #expect(library.referenceFrames["trophy_pose"] != nil)
        #expect(library.referenceFrames["racket_drop"] != nil)
        #expect(library.referenceFrames["contact"] != nil)
    }

    @Test("ReferenceFrame fields decode correctly")
    func decodesFields() throws {
        let data = try #require(sampleJSON.data(using: .utf8))
        let library = try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
        let frame = try #require(library.referenceFrames["trophy_pose"])
        #expect(frame.phase == "trophy_pose")
        #expect(frame.label == "Trophy Pose")
        #expect(frame.imageURL.lastPathComponent == "trophy_pose.jpg")
    }
}
