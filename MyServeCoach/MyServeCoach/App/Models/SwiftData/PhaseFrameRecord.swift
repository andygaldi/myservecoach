import Foundation
import SwiftData

/// A retained Pro 2D phase frame — the Pro counterpart to Lite's `PhaseRecord`, adding the
/// keypoints and detections the results-screen overlay renderer draws from.
///
/// Keypoints/detections are stored JSON-encoded rather than as SwiftData relationships: they are
/// opaque display payload, never queried, filtered, or sorted on, and modelling ~17 keypoints per
/// frame as entities would multiply the row count for no benefit.
@Model
final class PhaseFrameRecord {
    var id: UUID = UUID()
    var phaseKey: String = ""
    var frameTimestamp: Double = 0
    var frameImageData: Data = Data()
    /// JSON-encoded `BackendFrame`.
    var keypointsJSON: Data = Data()
    /// JSON-encoded `[BackendDetection]` at the same frame (ball/racket boxes).
    var detectionsJSON: Data = Data()
    var result: ServeResult?

    init(
        phaseKey: String,
        frameTimestamp: Double,
        frameImageData: Data,
        keypointsJSON: Data,
        detectionsJSON: Data
    ) {
        self.phaseKey = phaseKey
        self.frameTimestamp = frameTimestamp
        self.frameImageData = frameImageData
        self.keypointsJSON = keypointsJSON
        self.detectionsJSON = detectionsJSON
    }
}
