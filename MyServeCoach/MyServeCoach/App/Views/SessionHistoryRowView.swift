import SwiftUI

struct SessionHistoryRowView: View {
    let session: ServeSession

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · h:mm a"
        return f
    }()

    private var thumbnail: UIImage? {
        guard
            let data = session.phases.first(where: { $0.phaseKey == "trophy_pose" })?.frameImageData,
            let image = UIImage(data: data)
        else { return nil }
        return image
    }

    private var inputTypeBadge: String {
        session.inputType == "recorded" ? "Recorded" : "Imported"
    }

    // Internal (not private) so tests can exercise this logic directly without ViewInspector.
    var isProSession: Bool {
        session.mode != "lite"
    }

    var proSubtitle: String {
        let cueCount = session.results.flatMap(\.cues).count
        return "\(session.results.count) serve\(session.results.count == 1 ? "" : "s") · \(cueCount) cue\(cueCount == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isProSession {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Text("Pro 2D")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                } else if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
            }
            .frame(width: 56, height: 75)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateFormatter.string(from: session.date))
                    .font(.body)
                Text(isProSession ? proSubtitle : inputTypeBadge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
