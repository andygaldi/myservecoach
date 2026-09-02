import SwiftUI

/// Minimal read-only replay of a persisted Set Goal session — no aggregate stats section, no
/// skeleton overlay: Set Goal never had phase-frame imagery to show, unlike Assessment.
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
            GoalAttemptRowView(
                segmentIndex: attempt.segmentIndex, passed: attempt.passed, spokenCue: attempt.spokenCue
            )
        }
        .navigationTitle("Set Goal Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}
