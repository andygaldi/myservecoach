import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import MyServeCoach

@Suite("FrameThumbnailGenerator Tests")
struct FrameThumbnailGeneratorTests {

    @Test("throws when asset URL does not exist")
    func throwsForNonExistentAsset() async {
        let generator = FrameThumbnailGenerator()
        let badURL = URL(fileURLWithPath: "/nonexistent/path/video.mov")
        let asset = AVURLAsset(url: badURL)
        await #expect(throws: (any Error).self) {
            try await generator.thumbnail(
                at: CMTime(seconds: 1.0, preferredTimescale: 600),
                for: asset
            )
        }
    }

    // Valid-asset test: add a `test-video.mov` fixture to the MyServeCoachTests target,
    // then replace the body below to load it via Bundle resources.
    // @Test("returns non-nil UIImage for valid asset at known timestamp")
    // func returnsImageForValidAsset() async throws { ... }
}
