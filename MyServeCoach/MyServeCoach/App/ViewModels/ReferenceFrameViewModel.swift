import Foundation
import Observation

@MainActor
@Observable
final class ReferenceFrameViewModel: Identifiable, Hashable {
    let id = UUID()

    nonisolated static func == (lhs: ReferenceFrameViewModel, rhs: ReferenceFrameViewModel) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let confirmedFrames: [PhaseFrame]
    let inputType: String
    let videoURL: URL?

    private(set) var library: ReferenceFrameLibrary?
    private(set) var fetchError: Error?
    private(set) var isFetching = false

    private let service: ReferenceFrameService

    init(
        confirmedFrames: [PhaseFrame],
        inputType: String = "imported",
        videoURL: URL? = nil,
        service: ReferenceFrameService = ReferenceFrameService()
    ) {
        self.confirmedFrames = confirmedFrames
        self.inputType = inputType
        self.videoURL = videoURL
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
