import CoreMedia
import Foundation

/// Derives best-guess timestamps for the three key serve phases from a pose-frame segment.
/// Uses percentile positions within the segment (25 %, 50 %, 75 %) as a starting point.
/// Returns an empty array when no frames are available, which causes PhaseReviewViewModel
/// to fall back to the video midpoint with a "No pose detected" label for every phase.
struct PhaseGuesser {
    func guess(frames: [PoseFrame]) -> [PhaseFrame] {
        guard frames.count >= 3 else { return [] }

        let sorted = frames.sorted { $0.timestamp < $1.timestamp }
        let n = sorted.count

        let positions: [(ServePhase, Int)] = [
            (.trophyPose,    n / 4),
            (.racketDrop,    n / 2),
            (.contactPoint,  min(3 * n / 4, n - 1))
        ]

        return positions.map { phase, idx in
            PhaseFrame(
                phase: phase,
                timestamp: CMTime(seconds: sorted[idx].timestamp, preferredTimescale: 600)
            )
        }
    }
}
