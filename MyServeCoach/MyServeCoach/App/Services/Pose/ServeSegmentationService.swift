import Foundation

final class ServeSegmentationService {

    /// Splits a flat sequence of pose frames into per-serve segments.
    /// Gaps between serves are detected as runs of `kMinGapFrames` or more consecutive
    /// transitions whose mean joint displacement is below `kVelocityThreshold`.
    /// Segments shorter than `kMinServeFrames` are discarded.
    func segment(frames: [PoseFrame]) -> [[PoseFrame]] {
        guard frames.count > 1 else { return frames.isEmpty ? [] : [frames] }

        let velocities = computeVelocities(from: frames)
        let gaps = findGapRuns(in: velocities)
        return splitFrames(frames, at: gaps)
    }

    // MARK: - Velocity

    private func computeVelocities(from frames: [PoseFrame]) -> [Float] {
        var velocities = [Float]()
        velocities.reserveCapacity(frames.count - 1)
        for i in 0..<frames.count - 1 {
            velocities.append(meanDisplacement(from: frames[i], to: frames[i + 1]))
        }
        return velocities
    }

    private func meanDisplacement(from a: PoseFrame, to b: PoseFrame) -> Float {
        var total: Float = 0
        var count = 0
        for (key, pointA) in a.joints {
            guard let pointB = b.joints[key] else { continue }
            let dx = pointA.x - pointB.x
            let dy = pointA.y - pointB.y
            total += (dx * dx + dy * dy).squareRoot()
            count += 1
        }
        return count > 0 ? total / Float(count) : 0
    }

    // MARK: - Gap detection

    /// Returns index ranges (in velocity space) of runs that qualify as inter-serve gaps.
    private func findGapRuns(in velocities: [Float]) -> [(start: Int, end: Int)] {
        var gaps: [(start: Int, end: Int)] = []
        var i = 0
        while i < velocities.count {
            guard velocities[i] < PoseConstants.kVelocityThreshold else { i += 1; continue }
            let start = i
            while i < velocities.count && velocities[i] < PoseConstants.kVelocityThreshold {
                i += 1
            }
            let end = i - 1
            if end - start + 1 >= PoseConstants.kMinGapFrames {
                gaps.append((start: start, end: end))
            }
        }
        return gaps
    }

    // MARK: - Splitting

    /// Removes gap frames and collects the contiguous active runs as serve segments.
    /// A velocity-space gap [gs, ge] covers frames gs...ge+1, so those frame indices
    /// are excluded from every segment.
    private func splitFrames(_ frames: [PoseFrame], at gaps: [(start: Int, end: Int)]) -> [[PoseFrame]] {
        var gapFrameIndices = Set<Int>()
        for gap in gaps {
            for fi in gap.start...(gap.end + 1) {
                gapFrameIndices.insert(fi)
            }
        }

        var segments: [[PoseFrame]] = []
        var current: [PoseFrame] = []

        for (i, frame) in frames.enumerated() {
            if gapFrameIndices.contains(i) {
                if current.count >= PoseConstants.kMinServeFrames {
                    segments.append(current)
                }
                current = []
            } else {
                current.append(frame)
            }
        }
        if current.count >= PoseConstants.kMinServeFrames {
            segments.append(current)
        }

        return segments
    }
}
