import Testing
import UIKit
@testable import MyServeCoach

@Suite("PhaseFrameImageEncoder Tests")
struct PhaseFrameImageEncoderTests {

    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test("downscales an oversized portrait source to the target long edge, preserving aspect ratio")
    func downscalesOversizedPortraitSource() {
        let scaled = PhaseFrameImageEncoder.scaled(solidImage(width: 1440, height: 2560))

        #expect(scaled.size.height == PhaseFrameImageEncoder.maxLongEdge)
        #expect(abs(scaled.size.width - PhaseFrameImageEncoder.maxLongEdge * (1440.0 / 2560.0)) < 1)
    }

    @Test("downscales an oversized landscape source on its width")
    func downscalesOversizedLandscapeSource() {
        let scaled = PhaseFrameImageEncoder.scaled(solidImage(width: 2560, height: 1440))

        #expect(scaled.size.width == PhaseFrameImageEncoder.maxLongEdge)
        #expect(abs(scaled.size.height - PhaseFrameImageEncoder.maxLongEdge * (1440.0 / 2560.0)) < 1)
    }

    @Test("a source already below the target is not upscaled")
    func doesNotUpscaleSmallSource() {
        let original = solidImage(width: 400, height: 600)
        let scaled = PhaseFrameImageEncoder.scaled(original)

        #expect(scaled.size == original.size)
    }

    @Test("a source exactly at the target long edge is returned unchanged")
    func doesNotRescaleExactMatch() {
        let original = solidImage(width: 405, height: PhaseFrameImageEncoder.maxLongEdge)
        let scaled = PhaseFrameImageEncoder.scaled(original)

        #expect(scaled.size == original.size)
    }

    @Test("encoded output is valid JPEG data that decodes back to the scaled size")
    func encodesToDecodableJPEG() throws {
        let data = try #require(PhaseFrameImageEncoder.encode(solidImage(width: 1440, height: 2560)))
        let decoded = try #require(UIImage(data: data))

        #expect(!data.isEmpty)
        #expect(decoded.size.height == PhaseFrameImageEncoder.maxLongEdge)
    }
}
