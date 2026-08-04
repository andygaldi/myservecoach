import Foundation
import SwiftData

@Model
final class ServeResult {
    var id: UUID = UUID()
    var serveIndex: Int = 0
    var summary: String?
    @Relationship(deleteRule: .cascade) var cues: [CueRecord] = []
    @Relationship(deleteRule: .cascade) var phaseFrames: [PhaseFrameRecord] = []
    var session: ServeSession?

    init(serveIndex: Int, summary: String?) {
        self.serveIndex = serveIndex
        self.summary = summary
    }
}
