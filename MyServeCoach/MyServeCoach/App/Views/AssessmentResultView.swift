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
                AssessmentHeaderView(
                    serveCount: viewModel.serves.count,
                    majorCount: viewModel.totalMajorCount,
                    minorCount: viewModel.totalMinorCount
                )
                AssessmentAggregateSection(rows: viewModel.aggregatedCues)
                ForEach(viewModel.sections) { section in
                    AssessmentServeSectionView(section: section)
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
}
