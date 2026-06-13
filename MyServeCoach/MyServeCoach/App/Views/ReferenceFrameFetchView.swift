import SwiftUI

struct ReferenceFrameFetchView: View {
    let viewModel: ReferenceFrameViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if viewModel.isFetching {
                ProgressView("Loading reference frames…")
            } else if let library = viewModel.library {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Reference Frames Ready")
                    .font(.title2.weight(.bold))
                Divider().padding(.horizontal)
                ForEach(library.referenceFrames, id: \.phase) { frame in
                    HStack {
                        Text(frame.label)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(frame.imageURL.lastPathComponent)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
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
