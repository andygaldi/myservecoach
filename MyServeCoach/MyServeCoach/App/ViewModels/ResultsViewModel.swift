import Foundation
import Observation
import SwiftData

@Observable
final class ResultsViewModel {
    var serves: [Serve] = []
    var selectedServe: Serve?

    func loadServes(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<Serve>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            serves = try context.fetch(descriptor)
        } catch {
            serves = []
        }
    }

    func deleteServe(_ serve: Serve, context: ModelContext) {
        context.delete(serve)
        loadServes(context: context)
    }
}
