import SwiftUI

/// Read-only replay of a persisted Pro 2D Assessment session — reads `ServeResult`/`CueRecord`/
/// `PhaseFrameRecord` from SwiftData rather than a fresh `[AssessmentServeResult]`, which no
/// longer exists once the session has been saved. No `persist()` call here.
///
/// Renders through the same shared subviews as the live results screen. A session saved before
/// Phase P6c has no `PhaseFrameRecord`s and no cue deviation detail, so it degrades to the
/// text-only layout it originally had.
struct AssessmentHistoryDetailView: View {
    /// Built once and held, not recomputed per body evaluation: a 5-serve session costs ~20 JPEG
    /// decodes and ~40 JSON decodes, all on the main actor, so rebuilding it on every scroll or
    /// state change would stutter the screen. The live path does this work once in `init` too.
    ///
    /// Seeding `@State` is safe here because the session is fixed for the view's lifetime — the
    /// caller pushes this via `navigationDestination(for: ServeSession.self)`, so a different
    /// session is a different push and gets its own view identity (and its own presenter).
    @State private var presenter: AssessmentHistoryPresenter

    init(session: ServeSession) {
        _presenter = State(initialValue: AssessmentHistoryPresenter(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AssessmentHeaderView(
                    serveCount: presenter.serveCount,
                    majorCount: presenter.majorCount,
                    minorCount: presenter.minorCount
                )
                AssessmentAggregateSection(rows: presenter.aggregatedCues)
                ForEach(presenter.sections) { section in
                    AssessmentServeSectionView(section: section)
                }
            }
            .padding()
        }
        .navigationTitle("Assessment")
        .navigationBarTitleDisplayMode(.inline)
    }
}
