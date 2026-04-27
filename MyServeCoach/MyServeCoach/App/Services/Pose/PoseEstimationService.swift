import AVFoundation
import Vision

final class PoseEstimationService {
    let confidenceThreshold: Float

    init(confidenceThreshold: Float = PoseConstants.kConfidenceThreshold) {
        self.confidenceThreshold = confidenceThreshold
    }

    func detectPose(at time: CMTime, in image: CGImage) -> PoseFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let allPoints = (try? observation.recognizedPoints(.all)) ?? [:]
        let raw = allPoints.reduce(into: [String: (x: Float, y: Float, confidence: Float)]()) { dict, pair in
            dict[pair.key.rawValue.rawValue] = (Float(pair.value.x), Float(pair.value.y), pair.value.confidence)
        }
        return Self.assembleFrame(at: CMTimeGetSeconds(time), from: raw, confidenceThreshold: confidenceThreshold)
    }

    /// Filters `raw` by confidence and joint count, then builds a PoseFrame.
    /// Internal so tests can call it directly without going through Vision.
    static func assembleFrame(
        at timestamp: Double,
        from raw: [String: (x: Float, y: Float, confidence: Float)],
        confidenceThreshold: Float = PoseConstants.kConfidenceThreshold
    ) -> PoseFrame? {
        var joints: [String: JointPoint] = [:]
        for (key, point) in raw {
            guard point.confidence >= confidenceThreshold else { continue }
            joints[key] = JointPoint(x: point.x, y: point.y, confidence: point.confidence)
        }
        guard joints.count >= PoseConstants.kMinJointCount else { return nil }
        return PoseFrame(timestamp: timestamp, joints: joints)
    }
}
