import Foundation
import SwiftData

@Model
final class CueRecord {
    var id: UUID = UUID()
    var ruleId: String = ""
    var phase: String = ""
    var message: String = ""
    var severity: String = ""
    var result: ServeResult?

    init(ruleId: String, phase: String, message: String, severity: String) {
        self.ruleId = ruleId
        self.phase = phase
        self.message = message
        self.severity = severity
    }
}
