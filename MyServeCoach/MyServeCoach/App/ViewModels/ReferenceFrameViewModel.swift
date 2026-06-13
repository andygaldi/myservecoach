import Foundation
import Observation

@MainActor
@Observable
final class ReferenceFrameViewModel: Identifiable {
    let id = UUID()
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
            for frame in result.referenceFrames {
                print("[ReferenceFrameFetch] \(frame.phase.backendKey): \(frame.imageURL)")
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
