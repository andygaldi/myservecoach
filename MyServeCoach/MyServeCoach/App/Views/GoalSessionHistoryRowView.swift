import SwiftUI

struct GoalSessionHistoryRowView: View {
    let session: GoalSession

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · h:mm a"
        return f
    }()

    var passCount: Int { session.attempts.filter(\.passed).count }

    var subtitle: String {
        "\(passCount)/\(session.attempts.count) passed"
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay {
                    Text("Set Goal")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateFormatter.string(from: session.date))
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
