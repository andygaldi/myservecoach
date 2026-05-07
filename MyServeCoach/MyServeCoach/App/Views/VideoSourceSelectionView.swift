import SwiftUI

struct VideoSourceSelectionView: View {
    @State private var viewModel = VideoSourceSelectionViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "figure.tennis")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                    Text("Add a Serve")
                        .font(.largeTitle.weight(.bold))
                    Text("Record a new serve or pick a clip from your library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    sourceButton(
                        title: "Record New",
                        subtitle: "Use the camera",
                        icon: "video.circle.fill",
                        action: { viewModel.navigateToRecord = true }
                    )

                    sourceButton(
                        title: "Choose from Library",
                        subtitle: "Pick an existing clip",
                        icon: "photo.on.rectangle.angled",
                        action: { viewModel.showPhotoPicker = true }
                    )
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("New Serve")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $viewModel.navigateToRecord) {
                RecordServeView()
            }
        }
    }

    private func sourceButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
