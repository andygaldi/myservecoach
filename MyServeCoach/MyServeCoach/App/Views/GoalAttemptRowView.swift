import SwiftUI

/// One attempt's pass/fail + spoken cue, shared by the live session summary
/// (`SetGoalRecordingView`) and the saved-session replay (`GoalSessionHistoryDetailView`).
struct GoalAttemptRowView: View {
    let segmentIndex: Int
    let passed: Bool
    let spokenCue: String
    /// `nil` when no still was extracted/persisted for this attempt — the overlay is skipped
    /// rather than shown broken.
    var stillImage: UIImage? = nil
    var poseFrame: BackendFrame? = nil
    var detections: [BackendDetection] = []
    /// The failing-joint highlight, `nil` on a pass (skeleton draws alone).
    var highlightedCue: Cue? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stillImage {
                PhaseFrameOverlayView(
                    image: stillImage, frame: poseFrame, detections: detections, highlightedCue: highlightedCue
                )
            }
            HStack {
                Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(passed ? .green : .red)
                VStack(alignment: .leading) {
                    Text("Serve \(segmentIndex + 1)")
                        .font(.subheadline.weight(.semibold))
                    Text(spokenCue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
