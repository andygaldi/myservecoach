import SwiftUI

struct GoalSelectionView: View {
    var onGoalSelected: (GoalDefinition) -> Void

    var body: some View {
        List(GoalCatalog.all) { goal in
            Button(action: { onGoalSelected(goal) }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(goal.phase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Choose a Goal")
    }
}
