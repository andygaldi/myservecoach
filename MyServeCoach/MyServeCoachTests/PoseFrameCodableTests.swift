import Foundation
import Testing
@testable import MyServeCoach

@Suite("PoseFrame Codable Tests")
struct PoseFrameCodableTests {

    @Test("PoseFrame encodes and decodes back to equal value")
    func roundTrip() throws {
        let original = PoseFrame(
            timestamp: 1.5,
            joints: [
                "left_wrist_joint": JointPoint(x: 0.3, y: 0.7, confidence: 0.9),
                "right_shoulder_1_joint": JointPoint(x: 0.6, y: 0.2, confidence: 0.85)
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PoseFrame.self, from: data)

        #expect(decoded.timestamp == original.timestamp)
        #expect(decoded.joints.count == original.joints.count)

        for (key, point) in original.joints {
            let decodedPoint = try #require(decoded.joints[key])
            #expect(decodedPoint.x == point.x)
            #expect(decodedPoint.y == point.y)
            #expect(decodedPoint.confidence == point.confidence)
        }
    }
}
