import AVFoundation
import CoreVideo
import Testing
@testable import MyServeCoach

@Suite("VideoReencoder Tests")
struct VideoReencoderTests {

    @Test("reencode produces output matching the target size and frame rate")
    func reencodeProducesOutputMatchingTargetSizeAndFrameRate() async throws {
        let sourceURL = try await makeTestVideo(width: 1920, height: 1080, frameCount: 30, frameRate: 60)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let outputURL = try await VideoReencoder().reencode(sourceURL: sourceURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let outputAsset = AVURLAsset(url: outputURL)
        let track = try #require(try await outputAsset.loadTracks(withMediaType: .video).first)
        let naturalSize = try await track.load(.naturalSize)
        let nominalFrameRate = try await track.load(.nominalFrameRate)

        #expect(naturalSize.width == VideoReencoder.targetSize.width)
        #expect(naturalSize.height == VideoReencoder.targetSize.height)
        #expect(abs(nominalFrameRate - Float(VideoReencoder.targetFPS)) < 0.5)
    }

    @Test("reencode preserves duration within tolerance")
    func reencodePreservesDuration() async throws {
        let sourceURL = try await makeTestVideo(width: 1920, height: 1080, frameCount: 30, frameRate: 60)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let sourceDuration = try await AVURLAsset(url: sourceURL).load(.duration)

        let outputURL = try await VideoReencoder().reencode(sourceURL: sourceURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let outputDuration = try await AVURLAsset(url: outputURL).load(.duration)

        let delta = abs(CMTimeGetSeconds(outputDuration) - CMTimeGetSeconds(sourceDuration))
        #expect(delta < 0.2)
    }

    @Test("reencode throws on a source with no video track")
    func reencodeThrowsOnInvalidSource() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        try Data("not a real video file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) {
            _ = try await VideoReencoder().reencode(sourceURL: url)
        }
    }

    // MARK: - Helpers

    private func makeTestVideo(width: Int, height: Int, frameCount: Int, frameRate: Float) async throws -> URL {
        try await TestVideoFixture.make(width: width, height: height, frameCount: frameCount, frameRate: frameRate)
    }
}
