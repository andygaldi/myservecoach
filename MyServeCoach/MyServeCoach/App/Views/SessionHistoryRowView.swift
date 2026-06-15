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

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = thumbnail {
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
                Text(inputTypeBadge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
