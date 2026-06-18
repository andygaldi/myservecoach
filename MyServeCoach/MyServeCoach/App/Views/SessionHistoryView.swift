import SwiftData
import SwiftUI

struct SessionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ServeSession.date, order: .reverse) private var sessions: [ServeSession]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.clipboard",
                        headline: "No sessions yet",
                        subheadline: "Record or import a serve to get started."
                    )
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                SessionHistoryRowView(session: session)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                modelContext.delete(sessions[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: ServeSession.self) { session in
                HistoryComparisonView(session: session)
            }
        }
    }
}
