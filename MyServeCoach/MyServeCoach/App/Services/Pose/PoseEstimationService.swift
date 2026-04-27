import AVFoundation
import Vision

final class PoseEstimationService {

    /// Runs body pose detection on each sampled frame and returns the filtered results.
    /// Frames with no observation, or with fewer than 4 joints above the confidence
    /// threshold, are dropped silently.
    func estimatePoses(from frames: [(time: CMTime, image: CGImage)]) async -> [PoseFrame] {
        var poseFrames: [PoseFrame] = []
        poseFrames.reserveCapacity(frames.count)

        for (time, image) in frames {
            guard let frame = detectPose(at: time, in: image) else { continue }
            poseFrames.append(frame)
        }

        return poseFrames
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
        var joints: [String: JointPoint] = [:]

        for (jointName, point) in allPoints {
            guard point.confidence >= 0.3 else { continue }
            joints[jointName.rawValue.rawValue] = JointPoint(
                x: Float(point.x),
                y: Float(point.y),
                confidence: point.confidence
            )
        }

        guard joints.count >= 4 else { return nil }

        return PoseFrame(
            timestamp: CMTimeGetSeconds(time),
            joints: joints
        )
    }
}
