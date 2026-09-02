import AVFoundation
import Testing
@testable import MyServeCoach

// Uses a FakeMovieRecordingOutput injected via CameraService's recordingOutput seam — never
// touches real AVCaptureMovieFileOutput.startRecording, which crashes the process when the
// output isn't attached to a running AVCaptureSession (unavailable on Simulator/CI).
private final class FakeMovieRecordingOutput: MovieRecordingOutput {
    private(set) var startRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0

    func startRecording(to outputFileURL: URL, recordingDelegate: AVCaptureFileOutputRecordingDelegate) {
        startRecordingCallCount += 1
    }

    func stopRecording() {
        stopRecordingCallCount += 1
    }
}

@Suite("CameraService Tests")
struct CameraServiceTests {

    @Test("stopChunkedRecording before any chunk fires still finalizes exactly one isFinal chunk")
    func stopBeforeFirstChunkFiresFinalizesOnce() {
        let fakeOutput = FakeMovieRecordingOutput()
        let service = CameraService(recordingOutput: fakeOutput)
        let semaphore = DispatchSemaphore(value: 0)
        var receivedCalls: [(URL?, Bool)] = []

        service.startChunkedRecording(chunkDuration: 100) { url, isFinal in
            receivedCalls.append((url, isFinal))
            semaphore.signal()
        }
        service.stopChunkedRecording()

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("chunk.mov")
        service.fileOutput(
            AVCaptureMovieFileOutput(), didFinishRecordingTo: outputURL, from: [], error: nil
        )

        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        #expect(receivedCalls.count == 1)
        #expect(receivedCalls.first?.1 == true)
    }

    @Test("a non-final finalize error drops that chunk without calling the handler")
    func chunkFinalizeErrorDropsChunkSilently() {
        let fakeOutput = FakeMovieRecordingOutput()
        let service = CameraService(recordingOutput: fakeOutput)
        let semaphore = DispatchSemaphore(value: 0)
        var chunkCallCount = 0

        service.startChunkedRecording(chunkDuration: 100) { _, _ in
            chunkCallCount += 1
        }
        service.fileOutput(
            AVCaptureMovieFileOutput(),
            didFinishRecordingTo: FileManager.default.temporaryDirectory.appendingPathComponent("bad.mov"),
            from: [],
            error: NSError(domain: "test", code: 1)
        )
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { semaphore.signal() }
        semaphore.wait()

        #expect(chunkCallCount == 0)
    }

    @Test("a final finalize error still calls the handler, with a nil URL, so the session can finish")
    func chunkFinalizeErrorOnFinalChunkStillNotifiesHandler() {
        let fakeOutput = FakeMovieRecordingOutput()
        let service = CameraService(recordingOutput: fakeOutput)
        let semaphore = DispatchSemaphore(value: 0)
        var receivedCalls: [(URL?, Bool)] = []

        service.startChunkedRecording(chunkDuration: 100) { url, isFinal in
            receivedCalls.append((url, isFinal))
            semaphore.signal()
        }
        service.stopChunkedRecording()
        service.fileOutput(
            AVCaptureMovieFileOutput(),
            didFinishRecordingTo: FileManager.default.temporaryDirectory.appendingPathComponent("bad.mov"),
            from: [],
            error: NSError(domain: "test", code: 1)
        )

        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        #expect(receivedCalls.count == 1)
        #expect(receivedCalls.first?.0 == nil)
        #expect(receivedCalls.first?.1 == true)
    }
}
