import Foundation

/// Renders a cue's measured value and target into the "measured 62° · target ≤45°" caption shown
/// beneath a phase frame.
enum CueDeviationFormatter {
    private static let angleMetrics: Set<String> = ["angle", "angle_from_vertical"]

    /// `nil` when the cue carries no deviation detail — a cue persisted before P6c, or one from
    /// an older backend. Callers show no caption rather than a placeholder.
    static func caption(for cue: any CueDeviationDescribing) -> String? {
        guard let measured = cue.measuredValue, let target = target(for: cue) else { return nil }
        return "measured \(format(measured, metric: cue.metric)) · target \(target)"
    }

    private static func target(for cue: any CueDeviationDescribing) -> String? {
        let metric = cue.metric
        switch cue.comparison {
        case "gte":
            guard let threshold = cue.threshold else { return nil }
            return "≥\(format(threshold, metric: metric))"
        case "lte":
            guard let threshold = cue.threshold else { return nil }
            return "≤\(format(threshold, metric: metric))"
        case "range":
            guard let min = cue.thresholdMin, let max = cue.thresholdMax else { return nil }
            // The unit belongs on the range as a whole — "155–180°", not "155°–180°".
            return "\(format(min, metric: metric, includeUnit: false))–\(format(max, metric: metric))"
        default:
            return nil
        }
    }

    private static func format(_ value: Double, metric: String?, includeUnit: Bool = true) -> String {
        guard let metric, angleMetrics.contains(metric) else {
            // The diff/offset metrics are in normalized frame units — 2 decimals, no unit,
            // because "0.31 of the frame's height" has no natural real-world unit to show.
            return String(format: "%.2f", value)
        }
        return "\(Int(value.rounded()))\(includeUnit ? "°" : "")"
    }
}

/// The deviation fields shared by the network `Cue` and the persisted `CueRecord`, so the
/// formatter serves the live results screen and history replay identically.
protocol CueDeviationDescribing {
    var metric: String? { get }
    var measuredValue: Double? { get }
    var comparison: String? { get }
    var threshold: Double? { get }
    var thresholdMin: Double? { get }
    var thresholdMax: Double? { get }
}

extension Cue: CueDeviationDescribing {}
extension CueRecord: CueDeviationDescribing {}
