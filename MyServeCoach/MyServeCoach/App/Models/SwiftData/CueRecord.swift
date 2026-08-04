import Foundation
import SwiftData

@Model
final class CueRecord {
    var id: UUID = UUID()
    var ruleId: String = ""
    var phase: String = ""
    var message: String = ""
    var severity: String = ""
    // Deviation detail (P6c). Optional/defaulted so sessions persisted before P6c open unchanged
    // and simply render without a "measured X · target Y" line.
    var metric: String?
    var joints: [String] = []
    var measuredValue: Double?
    var comparison: String?
    var threshold: Double?
    var thresholdMin: Double?
    var thresholdMax: Double?
    var result: ServeResult?

    init(
        ruleId: String,
        phase: String,
        message: String,
        severity: String,
        metric: String? = nil,
        joints: [String] = [],
        measuredValue: Double? = nil,
        comparison: String? = nil,
        threshold: Double? = nil,
        thresholdMin: Double? = nil,
        thresholdMax: Double? = nil
    ) {
        self.ruleId = ruleId
        self.phase = phase
        self.message = message
        self.severity = severity
        self.metric = metric
        self.joints = joints
        self.measuredValue = measuredValue
        self.comparison = comparison
        self.threshold = threshold
        self.thresholdMin = thresholdMin
        self.thresholdMax = thresholdMax
    }
}
