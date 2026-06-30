import AVFoundation
import CoreMedia
import Observation
import UIKit

@MainActor
@Observable
final class PhaseReviewViewModel {
    private(set) var guessedFrames: [PhaseFrame]
    private(set) var confirmedTimestamps: [ServePhase: CMTime] = [:]
    private(set) var confirmedThumbnails: [ServePhase: UIImage] = [:]
    private(set) var currentStepIndex: Int = 0

    var currentPhase: ServePhase {
        ServePhase.allCases[currentStepIndex]
    }

    var isDoneEnabled: Bool {
        ServePhase.allCases.allSatisfy { confirmedTimestamps[$0] != nil }
    }

    var allPhasesAreFallback: Bool {
        guessedFrames.isEmpty
    }

    let videoAsset: AVAsset
    let inputType: String
    private let thumbnailGenerator: FrameThumbnailGenerator

    // Overridable in tests: returns the CMTime used when no guess exists for a phase.
    private let seekFallback: (AVAsset) -> CMTime

    init(
        guessedFrames: [PhaseFrame],
        videoAsset: AVAsset,
        inputType: String = "imported",
        thumbnailGenerator: FrameThumbnailGenerator? = nil,
        seekFallback: ((AVAsset) -> CMTime)? = nil
    ) {
        self.guessedFrames = guessedFrames
        self.videoAsset = videoAsset
        self.inputType = inputType
        // Defaults created here (inside the @MainActor init body) to avoid
        // main-actor isolation warnings on default parameter expressions.
        self.thumbnailGenerator = thumbnailGenerator ?? FrameThumbnailGenerator()
        self.seekFallback = seekFallback ?? { _ in .zero }
    }

    func setFrame(at time: CMTime) {
        let phase = currentPhase
        confirmedTimestamps[phase] = time
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let image = try? await self.thumbnailGenerator.thumbnail(at: time, for: self.videoAsset) {
                self.confirmedThumbnails[phase] = image
            }
        }
    }

    // Awaits the thumbnail before returning — use on the final phase so
    // confirmedPhaseFrames() captures the image rather than racing it.
    func setFrameAndAwaitThumbnail(at time: CMTime) async {
        let phase = currentPhase
        confirmedTimestamps[phase] = time
        if let image = try? await thumbnailGenerator.thumbnail(at: time, for: videoAsset) {
            confirmedThumbnails[phase] = image
        }
    }

    func advance() {
        guard currentStepIndex < ServePhase.allCases.count - 1 else { return }
        currentStepIndex += 1
    }

    func retreat() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
    }

    func initialSeekTime(for phase: ServePhase) -> CMTime {
        if let guessed = guessedFrames.first(where: { $0.phase == phase }) {
            return guessed.timestamp
        }
        return seekFallback(videoAsset)
    }

    func confirmedPhaseFrames() -> [PhaseFrame] {
        ServePhase.allCases.compactMap { phase in
            guard let time = confirmedTimestamps[phase] else { return nil }
            return PhaseFrame(phase: phase, timestamp: time, thumbnail: confirmedThumbnails[phase])
        }
    }
}
