import AVFoundation
import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class SetGoalSessionViewModel {
    let goal: GoalDefinition
    let cameraViewModel: CameraViewModel
    private(set) var attempts: [GoalAttemptDisplay] = []
    private(set) var isRecording = false
    private(set) var isFinalizing = false  // true between "stop tapped" and the summary being ready
    private(set) var videoURL: URL?
    var errorMessage: String?

    private let sessionId = UUID().uuidString
    private let goalSessionService: any GoalSessionServicing
    private let spokenFeedback: any SpokenFeedbackServicing
    private let concatenator: any ChunkVideoConcatenating
    private let imageProvider: any PhaseFrameImageProviding
    private var chunkURLs: [URL] = []

    init(
        goal: GoalDefinition,
        cameraViewModel: CameraViewModel = CameraViewModel(sessionMode: .pro2D),
        goalSessionService: any GoalSessionServicing = LiveGoalSessionService(),
        spokenFeedback: any SpokenFeedbackServicing = SpokenFeedbackService(),
        concatenator: any ChunkVideoConcatenating = ChunkVideoConcatenator(),
        imageProvider: any PhaseFrameImageProviding = PhaseFrameImageExtractor()
    ) {
        self.goal = goal
        self.cameraViewModel = cameraViewModel
        self.goalSessionService = goalSessionService
        self.spokenFeedback = spokenFeedback
        self.concatenator = concatenator
        self.imageProvider = imageProvider
    }

    var passCount: Int { attempts.filter(\.passed).count }
    var attemptCount: Int { attempts.count }

    func startSession() {
        isRecording = true
        // chunkDuration: 2, not 4 — halves the 0-4s chunk-quantization term in the cue-latency
        // budget (latency-findings.md's "Resulting latency budget" table).
        cameraViewModel.startChunkedRecording(chunkDuration: 2) { [weak self] url, isFinal in
            Task { @MainActor [weak self] in await self?.handleChunk(url: url, isFinal: isFinal) }
        }
    }

    func stopSession() {
        isRecording = false
        isFinalizing = true
        cameraViewModel.stopChunkedRecording()
    }

    // Backlog guard (latency-findings.md): with 2s chunks, a slow/stalled upload must not let
    // outstanding chunk uploads queue unboundedly — that drifts every later cue later and later
    // instead of degrading predictably. Cap outstanding (in-flight, not-yet-responded) uploads
    // at a small bound; a new chunk finalizing while already at the bound drops the oldest
    // still-in-flight upload (abandons awaiting its result; a stray late response is ignored)
    // rather than letting the queue grow — losing an occasional serve's cue under sustained
    // backlog is the accepted degradation mode, not silence or unbounded lateness.
    private let maxOutstandingUploads = 2
    private var outstandingUploadIDs: [UUID] = []

    private func handleChunk(url: URL?, isFinal: Bool) async {
        // A nil url means this chunk's file write itself failed (see CameraService's delegate
        // branch) — only possible when isFinal, since a non-final write failure is never reported
        // here at all (rotation just continues with the next chunk). Skip straight to finalizing
        // rather than uploading a chunk that doesn't exist.
        if let url {
            chunkURLs.append(url)
            let uploadID = UUID()
            if !isFinal, outstandingUploadIDs.count >= maxOutstandingUploads {
                outstandingUploadIDs.removeFirst()  // drop oldest in-flight upload
            }
            outstandingUploadIDs.append(uploadID)
            defer { outstandingUploadIDs.removeAll { $0 == uploadID } }
            do {
                let results = try await goalSessionService.uploadChunk(
                    fileURL: url, sessionId: sessionId, goalRuleId: goal.ruleId, isFinal: isFinal
                )
                // This upload's own ID may have been evicted (dropped) by a later chunk's
                // handleChunk call while this one was in flight — a stray late response is ignored.
                guard outstandingUploadIDs.contains(uploadID) else { return }
                for result in results {
                    let display = GoalAttemptDisplay(
                        segmentIndex: result.segmentIndex,
                        passed: result.goalResult.passed,
                        spokenCue: result.goalResult.spokenCue,
                        phaseFrame: result.phaseFrame,
                        cue: result.goalResult.cue
                    )
                    attempts.append(display)
                    spokenFeedback.speak(display.spokenCue)
                }
            } catch {
                guard outstandingUploadIDs.contains(uploadID) else { return }
                errorMessage = "Could not analyze that serve. Continuing session."
                print("[SetGoalSession] chunk upload failed: \(error)")
            }
        } else {
            errorMessage = "Could not save the final part of your recording."
        }
        if isFinal { await finalizeVideo() }
    }

    private func finalizeVideo() async {
        defer {
            isFinalizing = false
            cameraViewModel.recordingState = .idle
        }
        videoURL = try? await concatenator.concatenate(chunkURLs: chunkURLs)
        guard let videoURL else { return }

        let timestamps = attempts.compactMap(\.phaseFrame?.frame.timestamp)
        guard !timestamps.isEmpty else { return }
        // Set Goal tolerance absorbs the backend's own timestamp drift (see
        // PhaseFrameImageProviding's doc comment) — Assessment stays exact-seek (`.zero`).
        let tolerance = CMTime(seconds: 0.15, preferredTimescale: 600)
        guard let stills = try? await imageProvider.imageData(at: timestamps, from: videoURL, tolerance: tolerance)
        else { return }

        for index in attempts.indices {
            guard let timestamp = attempts[index].phaseFrame?.frame.timestamp,
                  let data = stills[timestamp] else { continue }
            attempts[index].stillImage = UIImage(data: data)
        }
    }

    func discard() {
        if let videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        for url in chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func persist(to context: ModelContext) {
        let encoder = JSONEncoder()
        let session = GoalSession(goalRuleId: goal.ruleId, goalDisplayName: goal.displayName, videoURL: videoURL)
        session.attempts = attempts.map { attempt in
            let record = GoalAttemptRecord(
                segmentIndex: attempt.segmentIndex, passed: attempt.passed, spokenCue: attempt.spokenCue
            )
            // A missing phaseFrame/stillImage (never extracted, or extraction failed) just costs
            // the overlay, not the attempt itself — the pass/fail row still persists above.
            if let phaseFrame = attempt.phaseFrame, let stillImage = attempt.stillImage,
               let keypointsJSON = try? encoder.encode(phaseFrame.frame),
               let detectionsJSON = try? encoder.encode(phaseFrame.detections),
               let frameImageData = PhaseFrameImageEncoder.encode(stillImage) {
                let cueJSON = attempt.cue.flatMap { try? encoder.encode($0) }
                record.phaseFrame = GoalPhaseFrameRecord(
                    frameTimestamp: phaseFrame.frame.timestamp,
                    frameImageData: frameImageData,
                    keypointsJSON: keypointsJSON,
                    detectionsJSON: detectionsJSON,
                    cueJSON: cueJSON
                )
            }
            return record
        }
        context.insert(session)
    }
}
