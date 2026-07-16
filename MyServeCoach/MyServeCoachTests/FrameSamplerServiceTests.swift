import AVFoundation
import CoreVideo
import Testing
@testable import MyServeCoach

@Suite("FrameSamplerService Tests")
struct FrameSamplerServiceTests {

    @Test("sample time count matches floor(totalFrames / stride)")
    func sampleTimeCount() async throws {
        let frameCount = 30
        let frameRate: Float = 30
        let url = try await makeTestVideo(frameCount: frameCount, frameRate: frameRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let (_, times) = try await FrameSamplerService().makeSampler(for: asset)

        #expect(times.count == frameCount / PoseConstants.kPoseSampleStride)
    }

    // MARK: - Helpers

    private func makeTestVideo(frameCount: Int, frameRate: Float) async throws -> URL {
        try await TestVideoFixture.make(width: 32, height: 32, frameCount: frameCount, frameRate: frameRate)
    }
}
