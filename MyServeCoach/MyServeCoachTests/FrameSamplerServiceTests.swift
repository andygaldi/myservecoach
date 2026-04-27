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

    /// Writes a minimal H264 video with black frames to a temp file.
    private func makeTestVideo(frameCount: Int, frameRate: Float) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 32,
            AVVideoHeightKey: 32
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 32 as Int,
                kCVPixelBufferHeightKey as String: 32 as Int
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let timeScale = CMTimeScale(frameRate)
        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pb)
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: timeScale))
        }

        input.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }

        return url
    }
}
