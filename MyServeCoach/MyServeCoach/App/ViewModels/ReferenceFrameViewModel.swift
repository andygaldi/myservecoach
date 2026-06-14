import Foundation
import Observation

@MainActor
@Observable
final class ReferenceFrameViewModel: Identifiable, Hashable {
    let id = UUID()

    static func == (lhs: ReferenceFrameViewModel, rhs: ReferenceFrameViewModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let confirmedFrames: [PhaseFrame]

    private(set) var library: ReferenceFrameLibrary?
    private(set) var fetchError: Error?
    private(set) var isFetching = false

    private let service: ReferenceFrameService

    init(confirmedFrames: [PhaseFrame], service: ReferenceFrameService = ReferenceFrameService()) {
        self.confirmedFrames = confirmedFrames
        self.service = service
    }

    func fetch() async {
        isFetching = true
        fetchError = nil
        do {
            let result = try await service.fetchReferenceFrames()
            library = result
            for (key, frames) in result.referenceFrames {
                for frame in frames {
                    print("[ReferenceFrameFetch] \(key): \(frame.imageURL)")
                }
            }
        } catch {
            fetchError = error
        }
        isFetching = false
    }

    func clearError() {
        fetchError = nil
    }
}
