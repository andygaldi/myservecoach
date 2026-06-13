import CoreMedia
import SwiftUI

struct ReferenceFrameFetchView: View {
    let confirmedFrames: [PhaseFrame]

    private let service = ReferenceFrameService()

    @State private var library: ReferenceFrameLibrary?
    @State private var fetchError: Error?
    @State private var isFetching = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if isFetching {
                ProgressView("Loading reference frames…")
            } else if let library {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Reference Frames Ready")
                    .font(.title2.weight(.bold))
                Divider().padding(.horizontal)
                ForEach(Array(library.referenceFrames.keys.sorted()), id: \.self) { key in
                    if let frame = library.referenceFrames[key] {
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
        .task { await fetch() }
        .alert("Could not load reference frames. Check your connection and try again.", isPresented: Binding(
            get: { fetchError != nil },
            set: { if !$0 { fetchError = nil } }
        )) {
            Button("Retry") { Task { await fetch() } }
            Button("Dismiss", role: .cancel) { fetchError = nil }
        }
    }

    private func fetch() async {
        isFetching = true
        fetchError = nil
        do {
            let result = try await service.fetchReferenceFrames()
            library = result
            for (_, frame) in result.referenceFrames {
                print("[ReferenceFrameFetch] \(frame.phase): \(frame.imageURL)")
            }
        } catch {
            fetchError = error
        }
        isFetching = false
    }
}
