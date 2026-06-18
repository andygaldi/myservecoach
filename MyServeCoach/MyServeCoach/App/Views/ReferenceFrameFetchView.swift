import SwiftUI

struct ReferenceFrameFetchView: View {
    let viewModel: ReferenceFrameViewModel
    var onFinish: () -> Void = {}

    @State private var showComparison = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if viewModel.fetchError != nil {
                ErrorView(
                    systemImage: "wifi.exclamationmark",
                    title: "Couldn't Connect",
                    message: "Could not reach the server. Check your connection and try again.",
                    primaryActionLabel: "Retry",
                    primaryAction: {
                        viewModel.clearError()
                        Task { await viewModel.fetch() }
                    },
                    secondaryActionLabel: "Cancel",
                    secondaryAction: {
                        viewModel.clearError()
                        dismiss()
                    }
                )
            } else {
                VStack(spacing: 20) {
                    Spacer()
                    if viewModel.library != nil {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("Reference Frames Ready")
                            .font(.title2.weight(.bold))
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                        Text("Fetching Reference Frames…")
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("Reference Frames")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isFetching {
                LoadingOverlayView(message: "Fetching reference frames…")
            }
        }
        .task { await viewModel.fetch() }
        .onChange(of: viewModel.library != nil) { _, isReady in
            if isReady { showComparison = true }
        }
        .navigationDestination(isPresented: $showComparison) {
            if let library = viewModel.library {
                ComparisonView(
                    confirmedFrames: viewModel.confirmedFrames,
                    referenceLibrary: library,
                    inputType: viewModel.inputType,
                    videoURL: viewModel.videoURL,
                    onFinish: onFinish
                )
            }
        }
    }
}
