import SwiftUI
import PhotosUI

struct VideoSourceSelectionView: View {
    @State private var viewModel = VideoSourceSelectionViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @Environment(\.openURL) private var openURL

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
                        action: { viewModel.handleLibraryButtonTap() }
                    )

                    if viewModel.photoPermissionDenied {
                        photoPermissionDeniedBanner
                    }

                    if let message = viewModel.errorMessage {
                        errorBanner(message: message)
                    }
                }
                .padding(.horizontal)
                .disabled(viewModel.isProcessing)

                if viewModel.isProcessing {
                    ProgressView("Analyzing…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .navigationTitle("New Serve")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $viewModel.navigateToRecord) {
                RecordServeView()
            }
            .photosPicker(
                isPresented: $viewModel.showPhotoPicker,
                selection: $pickerItem,
                matching: .videos
            )
            .onChange(of: pickerItem) { _, newItem in
                viewModel.handlePickerSelection(newItem)
                pickerItem = nil  // allow re-selecting the same clip
            }
        }
    }

    private var photoPermissionDeniedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.fill")
            Text("Photos access denied.")
                .font(.subheadline)
            Spacer()
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding()
        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding()
        .background(.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
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
