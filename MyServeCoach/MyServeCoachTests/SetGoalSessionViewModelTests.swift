import AVFoundation
import Foundation
import SwiftData
import UIKit
import Testing
@testable import MyServeCoach

/// Gates async `uploadChunk` calls so the test can control exactly when each in-flight upload
/// resolves, in order — needed to exercise the backlog guard deterministically.
actor UploadGate {
    private var continuations: [CheckedContinuation<[GoalChunkResult], Error>] = []

    func wait() async throws -> [GoalChunkResult] {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func resolveNext(with result: Result<[GoalChunkResult], Error>) {
        guard !continuations.isEmpty else { return }
        let continuation = continuations.removeFirst()
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    var pendingCount: Int { continuations.count }
}

@Suite("SetGoalSessionViewModel Tests")
@MainActor
struct SetGoalSessionViewModelTests {

    private let goal = GoalCatalog.all[0]

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition(), Date() < deadline {
            await Task.yield()
        }
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([GoalSession.self, GoalAttemptRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        }
        return image.jpegData(compressionQuality: 0.7)!
    }

    @Test("chunk finalize uploads with correct params and processes results")
    func chunkFinalizeUploadsAndProcessesResults() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        goalService.handler = { _, _, _, _ in
            [GoalChunkResult(segmentIndex: 0, goalResult: GoalResult(passed: false, spokenCue: "Keep arm straighter", phase: "contact"))]
        }
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator
        )

        vm.startSession()
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk1.mov"), isFinal: false)
        await waitUntil { vm.attempts.count == 1 }

        #expect(goalService.calls.count == 1)
        #expect(goalService.calls[0].isFinal == false)
        #expect(goalService.calls[0].goalRuleId == goal.ruleId)
        #expect(!goalService.calls[0].sessionId.isEmpty)
        #expect(vm.attempts[0].passed == false)
        #expect(vm.attempts[0].spokenCue == "Keep arm straighter")
        #expect(spoken.spokenTexts == ["Keep arm straighter"])
    }

    @Test("a failed chunk upload sets errorMessage without appending a bogus attempt or touching isRecording")
    func failedUploadSetsErrorMessageOnly() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        goalService.handler = { _, _, _, _ in throw ProUploadError.networkError("boom") }
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator
        )

        vm.startSession()
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk1.mov"), isFinal: false)
        await waitUntil { vm.errorMessage != nil }

        #expect(vm.attempts.isEmpty)
        #expect(vm.isRecording == true)
        #expect(spoken.spokenTexts.isEmpty)

        // A subsequent successful chunk still processes normally.
        goalService.handler = { _, _, _, _ in
            [GoalChunkResult(segmentIndex: 1, goalResult: GoalResult(passed: true, spokenCue: "Nice serve", phase: "contact"))]
        }
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk2.mov"), isFinal: false)
        await waitUntil { vm.attempts.count == 1 }
        #expect(vm.attempts[0].spokenCue == "Nice serve")
    }

    @Test("stop finalizes video via the concatenator with accumulated chunk URLs")
    func stopFinalizesVideo() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator
        )

        vm.startSession()
        let url1 = URL(fileURLWithPath: "/tmp/chunk1.mov")
        mockCamera.triggerChunk(url: url1, isFinal: false)
        await waitUntil { goalService.calls.count == 1 }

        vm.stopSession()
        #expect(mockCamera.stopChunkedRecordingCallCount == 1)

        let url2 = URL(fileURLWithPath: "/tmp/chunk2.mov")
        mockCamera.triggerChunk(url: url2, isFinal: true)
        await waitUntil { vm.videoURL != nil }

        #expect(concatenator.concatenateCallCount == 1)
        #expect(concatenator.lastChunkURLs == [url1, url2])
        #expect(vm.videoURL == concatenator.resultURL)
        #expect(vm.isFinalizing == false)
    }

    @Test("persist(to:) builds a GoalSession with matching GoalAttemptRecords")
    func persistBuildsCorrectSwiftDataObjects() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        goalService.handler = { _, _, _, _ in
            [GoalChunkResult(segmentIndex: 0, goalResult: GoalResult(passed: false, spokenCue: "Keep arm straighter", phase: "contact"))]
        }
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator
        )

        vm.startSession()
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk1.mov"), isFinal: false)
        await waitUntil { vm.attempts.count == 1 }

        let context = try makeInMemoryContext()
        vm.persist(to: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GoalSession>()).first
        let session = try #require(fetched)
        #expect(session.goalRuleId == goal.ruleId)
        #expect(session.goalDisplayName == goal.displayName)
        #expect(session.attempts.count == 1)
        #expect(session.attempts[0].segmentIndex == 0)
        #expect(session.attempts[0].passed == false)
        #expect(session.attempts[0].spokenCue == "Keep arm straighter")
    }

    @Test("backlog guard drops the oldest in-flight upload's result once outstanding exceeds the bound")
    func backlogGuardDropsOldestInFlightUpload() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        let gate = UploadGate()
        goalService.handler = { _, _, _, _ in try await gate.wait() }
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator
        )

        vm.startSession()
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk1.mov"), isFinal: false)
        await waitUntil { await gate.pendingCount == 1 }
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk2.mov"), isFinal: false)
        await waitUntil { await gate.pendingCount == 2 }
        // maxOutstandingUploads is 2 — this third chunk pushes the count over the bound, dropping
        // chunk1's in-flight upload from tracking.
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk3.mov"), isFinal: false)
        await waitUntil { await gate.pendingCount == 3 }

        // Resolve in order: chunk1 (dropped — should be ignored), chunk2, chunk3.
        await gate.resolveNext(with: .success([
            GoalChunkResult(segmentIndex: 0, goalResult: GoalResult(passed: true, spokenCue: "should be ignored", phase: "contact"))
        ]))
        await gate.resolveNext(with: .success([
            GoalChunkResult(segmentIndex: 1, goalResult: GoalResult(passed: true, spokenCue: "kept 2", phase: "contact"))
        ]))
        await gate.resolveNext(with: .success([
            GoalChunkResult(segmentIndex: 2, goalResult: GoalResult(passed: false, spokenCue: "kept 3", phase: "contact"))
        ]))
        await waitUntil { vm.attempts.count == 2 }

        #expect(vm.attempts.map(\.spokenCue) == ["kept 2", "kept 3"])
    }

    @Test("a nil final chunk URL (finalize write failure) still finalizes the session instead of hanging")
    func nilFinalChunkURLStillFinalizes() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator
        )

        vm.startSession()
        vm.stopSession()
        mockCamera.triggerChunk(url: nil, isFinal: true)
        await waitUntil { vm.isFinalizing == false }

        #expect(vm.errorMessage != nil)
        #expect(goalService.calls.isEmpty)
        #expect(concatenator.concatenateCallCount == 1)
        #expect(vm.videoURL == concatenator.resultURL)
    }

    // `discard()` takes no `ModelContext` — it structurally cannot call `context.insert(_:)`, so
    // there's nothing to assert about persistence here beyond the type signature itself. "Doesn't
    // persist" is actually a caller-side contract (`SetGoalRecordingView`'s Discard button calls
    // `discard()` then `onDone()`, never `persist(to:)`) verified by Group 7's manual device pass.
    @Test("discard() removes the concatenated video and chunk files from disk")
    func discardRemovesFiles() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        let tempDir = FileManager.default.temporaryDirectory
        let chunkURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
        let concatenatedURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
        try Data().write(to: chunkURL)
        try Data().write(to: concatenatedURL)
        concatenator.resultURL = concatenatedURL
        goalService.handler = { _, _, _, _ in
            [GoalChunkResult(segmentIndex: 0, goalResult: GoalResult(passed: true, spokenCue: "Nice serve", phase: "contact"))]
        }
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator
        )

        vm.startSession()
        vm.stopSession()
        mockCamera.triggerChunk(url: chunkURL, isFinal: true)
        await waitUntil { vm.videoURL != nil }

        #expect(FileManager.default.fileExists(atPath: chunkURL.path))
        #expect(FileManager.default.fileExists(atPath: concatenatedURL.path))

        vm.discard()

        #expect(!FileManager.default.fileExists(atPath: chunkURL.path))
        #expect(!FileManager.default.fileExists(atPath: concatenatedURL.path))
    }

    @Test("finalizing the session resets the camera view model's recordingState to idle")
    func finalizeResetsRecordingState() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        let cameraViewModel = CameraViewModel(cameraService: mockCamera)
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: cameraViewModel,
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator
        )

        vm.startSession()
        #expect(cameraViewModel.recordingState == .recording)
        vm.stopSession()
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk1.mov"), isFinal: true)
        await waitUntil { vm.isFinalizing == false }

        #expect(cameraViewModel.recordingState == .idle)
    }

    @Test("finalizing extracts a stillImage for every attempt with a phaseFrame")
    func finalizeExtractsStillImages() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        let imageProvider = MockPhaseFrameImageProvider()
        let frame = BackendFrame(timestamp: 1.5, keypoints: [:])
        let stillData = jpeg()
        imageProvider.dataBySeconds = [1.5: stillData]
        goalService.handler = { _, _, _, _ in
            [GoalChunkResult(
                segmentIndex: 0,
                goalResult: GoalResult(passed: false, spokenCue: "Keep arm straighter", phase: "contact"),
                phaseFrame: GoalPhaseFrame(frame: frame, detections: [])
            )]
        }
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator,
            imageProvider: imageProvider
        )

        vm.startSession()
        vm.stopSession()
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk1.mov"), isFinal: true)
        await waitUntil { vm.isFinalizing == false }

        #expect(imageProvider.lastRequestedSeconds == [1.5])
        #expect(vm.attempts[0].stillImage != nil)
    }

    @Test("persist(to:) attaches a GoalPhaseFrameRecord with cueJSON on a miss, nil on a pass")
    func persistAttachesGoalPhaseFrameRecord() async throws {
        let mockCamera = MockCameraService()
        let goalService = MockGoalSessionService()
        let spoken = MockSpokenFeedbackService()
        let concatenator = MockChunkVideoConcatenator()
        let imageProvider = MockPhaseFrameImageProvider()
        let missFrame = BackendFrame(timestamp: 1.0, keypoints: [:])
        let passFrame = BackendFrame(timestamp: 2.0, keypoints: [:])
        imageProvider.dataBySeconds = [1.0: jpeg(), 2.0: jpeg()]
        let missCue = Cue(
            ruleId: "trophy_toss_arm_straight", phase: "trophy_pose", message: "Straighten your arm",
            severity: "major", metric: nil, joints: ["left_elbow"], measuredValue: nil,
            comparison: nil, threshold: nil, thresholdMin: nil, thresholdMax: nil
        )
        goalService.handler = { _, _, _, _ in
            [
                GoalChunkResult(
                    segmentIndex: 0,
                    goalResult: GoalResult(passed: false, spokenCue: "Keep arm straighter", phase: "contact", cue: missCue),
                    phaseFrame: GoalPhaseFrame(frame: missFrame, detections: [])
                ),
                GoalChunkResult(
                    segmentIndex: 1,
                    goalResult: GoalResult(passed: true, spokenCue: "Nice serve", phase: "contact"),
                    phaseFrame: GoalPhaseFrame(frame: passFrame, detections: [])
                ),
            ]
        }
        let vm = SetGoalSessionViewModel(
            goal: goal,
            cameraViewModel: CameraViewModel(cameraService: mockCamera),
            goalSessionService: goalService,
            spokenFeedback: spoken,
            concatenator: concatenator,
            imageProvider: imageProvider
        )

        vm.startSession()
        vm.stopSession()
        mockCamera.triggerChunk(url: URL(fileURLWithPath: "/tmp/chunk1.mov"), isFinal: true)
        await waitUntil { vm.isFinalizing == false }
        #expect(vm.attempts.count == 2)

        let context = try makeInMemoryContext()
        vm.persist(to: context)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<GoalSession>()).first)
        let attempts = fetched.attempts.sorted { $0.segmentIndex < $1.segmentIndex }
        let missRecord = try #require(attempts[0].phaseFrame)
        #expect(missRecord.frameTimestamp == 1.0)
        #expect(missRecord.cueJSON != nil)
        let passRecord = try #require(attempts[1].phaseFrame)
        #expect(passRecord.frameTimestamp == 2.0)
        #expect(passRecord.cueJSON == nil)
    }
}
