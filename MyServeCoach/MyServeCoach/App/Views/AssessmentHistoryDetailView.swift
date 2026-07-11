import SwiftUI

/// Read-only replay of a persisted Pro 2D Assessment session — reads `ServeResult`/`CueRecord`
/// directly from SwiftData rather than a fresh `[AssessmentServeResult]`, which no longer exists
/// once the session has been saved. No `persist()` call here.
struct AssessmentHistoryDetailView: View {
    let session: ServeSession

    private var sortedResults: [ServeResult] {
        session.results.sorted { $0.serveIndex < $1.serveIndex }
    }

    private var totalMajorCount: Int {
        session.results.flatMap(\.cues).filter { $0.severity == "major" }.count
    }

    private var totalMinorCount: Int {
        session.results.flatMap(\.cues).filter { $0.severity == "minor" }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(sortedResults) { result in
                    resultSection(result)
                }
            }
            .padding()
        }
        .navigationTitle("Assessment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(session.results.count) serve\(session.results.count == 1 ? "" : "s") analyzed")
                .font(.title2.weight(.bold))
            Text("\(totalMajorCount) major · \(totalMinorCount) minor")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func resultSection(_ result: ServeResult) -> some View {
        let cues = result.cues.sortedByCoachingPriority()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Serve \(result.serveIndex + 1)")
                .font(.headline)

            if cues.isEmpty, let summary = result.summary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            } else {
                ForEach(cues) { cue in
                    cueRow(cue)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func cueRow(_ cue: CueRecord) -> some View {
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
