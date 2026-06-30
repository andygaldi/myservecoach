import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import MyServeCoach

@Suite("PhaseReviewViewModel Tests")
@MainActor
struct PhaseReviewViewModelTests {

    // Inject a fixed seek fallback so midpoint tests don't depend on asset duration.
    private func makeViewModel(
        guessedFrames: [PhaseFrame] = [],
        seekFallback: ((AVAsset) -> CMTime)? = nil
    ) -> PhaseReviewViewModel {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/dev/null"))
        return PhaseReviewViewModel(
            guessedFrames: guessedFrames,
            videoAsset: asset,
            seekFallback: seekFallback
        )
    }

    private let t1 = CMTime(seconds: 1.0, preferredTimescale: 600)
    private let t2 = CMTime(seconds: 2.0, preferredTimescale: 600)
    private let t3 = CMTime(seconds: 3.0, preferredTimescale: 600)

    // MARK: - setFrame

    @Test("setFrame stores timestamp for the current phase")
    func setFrameStoresTimestamp() {
        let vm = makeViewModel()
        vm.setFrame(at: t1)
        #expect(vm.confirmedTimestamps[.trophyPose] == t1)
    }

    @Test("setFrame for step 2 stores timestamp under the correct phase")
    func setFrameStoresTimestampForSecondPhase() {
        let vm = makeViewModel()
        vm.advance()
        vm.setFrame(at: t2)
        #expect(vm.confirmedTimestamps[.racketDrop] == t2)
        #expect(vm.confirmedTimestamps[.trophyPose] == nil)
    }

    // MARK: - isDoneEnabled

    @Test("isDoneEnabled is false when no frames confirmed")
    func isDoneEnabledFalseWhenEmpty() {
        let vm = makeViewModel()
        #expect(vm.isDoneEnabled == false)
    }

    @Test("isDoneEnabled is false after confirming only two phases")
    func isDoneEnabledFalseAfterTwoPhases() {
        let vm = makeViewModel()
        vm.setFrame(at: t1)
        vm.advance()
        vm.setFrame(at: t2)
        #expect(vm.isDoneEnabled == false)
    }

    @Test("isDoneEnabled becomes true after all three phases are confirmed")
    func isDoneEnabledTrueWhenAllConfirmed() {
        let vm = makeViewModel()
        vm.setFrame(at: t1)
        vm.advance()
        vm.setFrame(at: t2)
        vm.advance()
        vm.setFrame(at: t3)
        #expect(vm.isDoneEnabled == true)
    }

    // MARK: - advance

    @Test("advance increments currentStepIndex")
    func advanceIncrementsIndex() {
        let vm = makeViewModel()
        vm.advance()
        #expect(vm.currentStepIndex == 1)
    }

    @Test("advance is blocked at the last step (index 2)")
    func advanceBlockedAtLastStep() {
        let vm = makeViewModel()
        vm.advance()
        vm.advance()
        vm.advance()  // no-op: already at last step
        #expect(vm.currentStepIndex == 2)
    }

    // MARK: - retreat

    @Test("retreat decrements currentStepIndex")
    func retreatDecrementsIndex() {
        let vm = makeViewModel()
        vm.advance()
        vm.retreat()
        #expect(vm.currentStepIndex == 0)
    }

    @Test("retreat is blocked at step 0")
    func retreatBlockedAtZero() {
        let vm = makeViewModel()
        vm.retreat()  // no-op: already at step 0
        #expect(vm.currentStepIndex == 0)
    }

    // MARK: - initialSeekTime

    @Test("initialSeekTime returns guessed timestamp when confident")
    func initialSeekTimeReturnsGuessWhenConfident() {
        let guessedFrames = [PhaseFrame(phase: .trophyPose, timestamp: t1)]
        let vm = makeViewModel(guessedFrames: guessedFrames)
        #expect(vm.initialSeekTime(for: .trophyPose) == t1)
    }

    @Test("initialSeekTime returns the seekFallback value when no guess for phase")
    func initialSeekTimeReturnsFallbackWhenNoGuess() {
        let midpoint = CMTime(seconds: 5.0, preferredTimescale: 600)
        let vm = makeViewModel(guessedFrames: [], seekFallback: { _ in midpoint })
        #expect(vm.initialSeekTime(for: .trophyPose) == midpoint)
        #expect(vm.initialSeekTime(for: .racketDrop) == midpoint)
        #expect(vm.initialSeekTime(for: .contactPoint) == midpoint)
    }

    @Test("initialSeekTime returns guessed time for a phase that has a guess, fallback for one that does not")
    func initialSeekTimeMixedGuesses() {
        let midpoint = CMTime(seconds: 5.0, preferredTimescale: 600)
        let guessedFrames = [PhaseFrame(phase: .racketDrop, timestamp: t2)]
        let vm = makeViewModel(guessedFrames: guessedFrames, seekFallback: { _ in midpoint })
        #expect(vm.initialSeekTime(for: .trophyPose) == midpoint)    // no guess → fallback
        #expect(vm.initialSeekTime(for: .racketDrop) == t2)           // has guess → returned
        #expect(vm.initialSeekTime(for: .contactPoint) == midpoint)   // no guess → fallback
    }
}
