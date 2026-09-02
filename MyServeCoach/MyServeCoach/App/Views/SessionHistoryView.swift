import SwiftData
import SwiftUI

struct SessionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ServeSession.date, order: .reverse) private var sessions: [ServeSession]
    @Query(sort: \GoalSession.date, order: .reverse) private var goalSessions: [GoalSession]

    // Internal (not private), and merge() a static function over plain arrays, so tests can
    // exercise the merge/sort logic directly without needing a live @Query/environment.
    enum HistoryEntry: Identifiable {
        case serve(ServeSession)
        case goal(GoalSession)

        var id: UUID {
            switch self {
            case .serve(let s): s.id
            case .goal(let g): g.id
            }
        }

        var date: Date {
            switch self {
            case .serve(let s): s.date
            case .goal(let g): g.date
            }
        }

        var isGoal: Bool {
            if case .goal = self { true } else { false }
        }
    }

    static func merge(sessions: [ServeSession], goalSessions: [GoalSession]) -> [HistoryEntry] {
        (sessions.map(HistoryEntry.serve) + goalSessions.map(HistoryEntry.goal))
            .sorted { $0.date > $1.date }
    }

    private var entries: [HistoryEntry] {
        Self.merge(sessions: sessions, goalSessions: goalSessions)
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.clipboard",
                        headline: "No sessions yet",
                        subheadline: "Record or import a serve to get started."
                    )
                } else {
                    List {
                        ForEach(entries) { entry in
                            switch entry {
                            case .serve(let session):
                                NavigationLink(value: session) {
                                    SessionHistoryRowView(session: session)
                                }
                            case .goal(let goalSession):
                                NavigationLink(value: goalSession) {
                                    GoalSessionHistoryRowView(session: goalSession)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                switch entries[index] {
                                case .serve(let session):
                                    modelContext.delete(session)
                                case .goal(let goalSession):
                                    modelContext.delete(goalSession)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: ServeSession.self) { session in
                if session.mode == "lite" {
                    HistoryComparisonView(session: session)
                } else {
                    AssessmentHistoryDetailView(session: session)
                }
            }
            .navigationDestination(for: GoalSession.self) { session in
                GoalSessionHistoryDetailView(session: session)
            }
        }
    }
}
