import SwiftData
import SwiftUI

struct AssessmentResultView: View {
    let viewModel: AssessmentResultViewModel
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var didPersist = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(viewModel.serves) { serve in
                    serveSection(serve)
                }
            }
            .padding()
        }
        .navigationTitle("Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onDone()
                    dismiss()
                }
            }
        }
        .task {
            guard !didPersist else { return }
            didPersist = true
            viewModel.persist(to: modelContext)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(viewModel.serves.count) serve\(viewModel.serves.count == 1 ? "" : "s") analyzed")
                .font(.title2.weight(.bold))
            Text("\(viewModel.totalMajorCount) major · \(viewModel.totalMinorCount) minor")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func serveSection(_ serve: AssessmentServeDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Serve \(serve.serveIndex + 1)")
                .font(.headline)

            if serve.cues.isEmpty, let summary = serve.summary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            } else {
                ForEach(serve.cues, id: \.ruleId) { cue in
                    cueRow(cue)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func cueRow(_ cue: Cue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(cue.severity == "major" ? Color.red : Color.orange)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(cue.message)
                .font(.subheadline)
        }
    }
}
