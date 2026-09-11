import AVFoundation
import Testing
import UIKit
@testable import MyServeCoach

@Suite("PhaseFrameImageExtractor Tests")
struct PhaseFrameImageExtractorTests {

    @Test("extracts JPEG data for each requested timestamp")
    func extractsDataForEachTimestamp() async throws {
        let url = try await TestVideoFixture.make(width: 320, height: 240, frameCount: 60, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await PhaseFrameImageExtractor().imageData(at: [0.0, 0.5, 1.0], from: url)

        #expect(Set(result.keys) == [0.0, 0.5, 1.0])
        for data in result.values {
            #expect(UIImage(data: data) != nil)
        }
    }

    @Test("an empty timestamp list returns an empty result without touching the asset")
    func emptyRequestReturnsEmpty() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).mov")

        let result = try await PhaseFrameImageExtractor().imageData(at: [], from: missing)

        #expect(result.isEmpty)
    }

    @Test("an unreadable source yields no images rather than throwing")
    func unreadableSourceYieldsNoImages() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).mov")

        let result = try await PhaseFrameImageExtractor().imageData(at: [0.0, 0.5], from: missing)

        #expect(result.isEmpty)
    }

    @Test("timestamps that do not round-trip exactly through CMTime are still keyed correctly")
    func lossyTimestampsAreKeyedByOriginalValue() async throws {
        let url = try await TestVideoFixture.make(width: 320, height: 240, frameCount: 60, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: url) }

        // 1.0/3.0 is not exactly representable at timescale 600 — the extractor must key the
        // result on the requested Double, not on CMTime.seconds round-tripped back.
        let requested = 1.0 / 3.0
        let result = try await PhaseFrameImageExtractor().imageData(at: [requested], from: url)

        #expect(result[requested] != nil)
    }

    @Test("an explicit nonzero tolerance still extracts a valid frame")
    func nonzeroToleranceStillExtractsFrame() async throws {
        let url = try await TestVideoFixture.make(width: 320, height: 240, frameCount: 60, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: url) }

        // Set Goal passes a small nonzero tolerance to absorb its backend timestamp's known
        // drift (requirements.md's "Known timing-precision limitation"), unlike Assessment's
        // exact-seek (`.zero`) default — this just confirms the explicit-tolerance path works.
        let requested = 0.5
        let result = try await PhaseFrameImageExtractor().imageData(
            at: [requested], from: url, tolerance: CMTime(seconds: 0.15, preferredTimescale: 600)
        )

        let data = try #require(result[requested])
        #expect(UIImage(data: data) != nil)
    }
}
