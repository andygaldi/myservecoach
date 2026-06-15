import SwiftUI

struct ReferenceFrameFetchView: View {
    let viewModel: ReferenceFrameViewModel
    var onFinish: () -> Void = {}

    @State private var showComparison = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if viewModel.isFetching {
                ProgressView("Loading reference frames…")
            } else if viewModel.library != nil {
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
        .navigationTitle("Reference Frames")
        .navigationBarTitleDisplayMode(.inline)
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
        .alert(
            "Could not load reference frames. Check your connection and try again.",
            isPresented: Binding(
                get: { viewModel.fetchError != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("Retry") { Task { await viewModel.fetch() } }
            Button("Dismiss", role: .cancel) { viewModel.clearError() }
        }
    }
}
