import SwiftUI

/// Minimal read-only replay of a persisted Set Goal session — no aggregate stats section, but
/// does show the skeleton overlay + failing-joint highlight when the attempt has a persisted
/// `GoalPhaseFrameRecord` (older sessions saved before this existed simply have none).
struct GoalSessionHistoryDetailView: View {
    let session: GoalSession

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · h:mm a"
        return f
    }()

    private var sortedAttempts: [GoalAttemptRecord] {
        session.attempts.sorted { $0.segmentIndex < $1.segmentIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.goalDisplayName)
                .font(.title3.weight(.semibold))
            Text(Self.dateFormatter.string(from: session.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding([.horizontal, .top])

        List(sortedAttempts, id: \.id) { attempt in
            let display = PersistedGoalAttemptDisplay(attempt)
            GoalAttemptRowView(
                segmentIndex: display.segmentIndex,
                passed: display.passed,
                spokenCue: display.spokenCue,
                stillImage: display.stillImage,
                poseFrame: display.poseFrame,
                detections: display.detections,
                highlightedCue: display.highlightedCue
            )
        }
        .navigationTitle("Set Goal Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}
