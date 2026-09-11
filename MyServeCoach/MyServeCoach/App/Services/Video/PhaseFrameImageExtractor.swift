import AVFoundation
import UIKit

/// Extracts JPEG-encoded still frames from a video at a set of timestamps.
///
/// Deliberately batched: `AVAssetImageGenerator.images(for:)` shares one asset and one generator
/// across every requested time, which matters because Pro 2D retains four frames per serve and a
/// multi-serve clip can ask for a couple of dozen at once. The per-call
/// `FrameThumbnailGenerator` (Lite's single-frame path) would rebuild the generator each time.
/// Tolerances match `FrameThumbnailGenerator`'s ±0.1s so both paths land on comparable frames.
protocol PhaseFrameImageProviding: Sendable {
    /// Returns JPEG data keyed by the requested timestamp. Timestamps whose extraction failed are
    /// simply absent from the result — extraction is best-effort per frame.
    ///
    /// `tolerance` defaults to `.zero` (Assessment's exact-seek behavior, unchanged). Set Goal
    /// passes a small nonzero tolerance instead — see `PhaseFrameImageExtractor`'s own comment on
    /// why exact seeks matter for Assessment but not for Set Goal.
    func imageData(at seconds: [Double], from videoURL: URL, tolerance: CMTime) async throws -> [Double: Data]
}

extension PhaseFrameImageProviding {
    func imageData(at seconds: [Double], from videoURL: URL) async throws -> [Double: Data] {
        try await imageData(at: seconds, from: videoURL, tolerance: .zero)
    }
}

struct PhaseFrameImageExtractor: PhaseFrameImageProviding {
    private static let timescale: CMTimeScale = 600

    func imageData(at seconds: [Double], from videoURL: URL, tolerance: CMTime = .zero) async throws -> [Double: Data] {
        guard !seconds.isEmpty else { return [:] }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Exact seeks by default, deliberately unlike Lite's `FrameThumbnailGenerator` (±0.1s).
        // Assessment's overlay draws its keypoints *on top of* this image, so the two must be the
        // same frame. The backend samples at `DEFAULT_STRIDE = 2` (backend/app/routers/segment.py)
        // — ~67ms apart at 30fps — so a ±0.1s tolerance would allow the returned image to be up to
        // 1.5 sampled frames away from the keypoints, floating the highlighted limb off the body
        // at contact, the fastest-moving moment of the serve. Lite can afford the tolerance
        // because it draws nothing over its thumbnails; Assessment cannot. Set Goal passes a
        // small nonzero `tolerance` instead, to absorb its own backend timestamp's known drift
        // (see requirements.md's "Known timing-precision limitation") rather than risk silently
        // returning no frame at all.
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        // Key the round-trip on CMTime.value rather than the Double: CMTime(seconds:) is lossy
        // for values like 1/3, so comparing `requestedTime.seconds` back to the original Double
        // would miss.
        var requestedByTimeValue: [CMTimeValue: Double] = [:]
        var times: [CMTime] = []
        for second in seconds {
            let time = CMTime(seconds: second, preferredTimescale: Self.timescale)
            requestedByTimeValue[time.value] = second
            times.append(time)
        }

        // Measures the phase's ≤2s extraction budget (see validation.md) rather than leaving it
        // to subjective impression — the log line is the evidence for that acceptance row.
        let started = ContinuousClock.now

        var result: [Double: Data] = [:]
        for await item in generator.images(for: times) {
            guard let requested = requestedByTimeValue[item.requestedTime.value] else { continue }
            do {
                let image = UIImage(cgImage: try item.image)
                guard let data = PhaseFrameImageEncoder.encode(image) else { continue }
                result[requested] = data
            } catch {
                print("[PhaseFrameImageExtractor] frame extraction failed at \(requested)s: \(error)")
            }
        }

        let elapsed = ContinuousClock.now - started
        let millis = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        print(String(
            format: "[PhaseFrameImageExtractor] extracted %d/%d frames in %.0f ms (%.0f ms/frame)",
            result.count, times.count, millis, millis / Double(max(times.count, 1))
        ))
        return result
    }
}
