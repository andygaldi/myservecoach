import SwiftUI

/// One attempt's pass/fail + spoken cue, shared by the live session summary
/// (`SetGoalRecordingView`) and the saved-session replay (`GoalSessionHistoryDetailView`).
struct GoalAttemptRowView: View {
    let segmentIndex: Int
    let passed: Bool
    let spokenCue: String

    var body: some View {
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
