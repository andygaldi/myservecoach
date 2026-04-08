import SwiftUI
import SwiftData

struct ResultsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ResultsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.serves.isEmpty {
                    ContentUnavailableView(
                        "No Serves Yet",
                        systemImage: "tennis.racket",
                        description: Text("Record a serve to see your analysis here.")
                    )
                } else {
                    List(viewModel.serves, id: \.id) { serve in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(serve.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text(serve.analysisStatus.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Results")
            .onAppear { viewModel.loadServes(context: modelContext) }
        }
    }
}
