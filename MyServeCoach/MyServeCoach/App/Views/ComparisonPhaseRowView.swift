import SwiftUI

struct ComparisonPhaseRowView: View {
    let phaseLabel: String
    let userImage: UIImage?
    let referenceFrames: [ReferenceFrame]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(phaseLabel)
                .font(.headline)
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Group {
                        if let image = userImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Rectangle()
                                .fill(Color(.systemGray5))
                        }
                    }
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    Text("You")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    ReferenceCarouselView(frames: referenceFrames)
                    Text("Reference")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
        }
    }
}
