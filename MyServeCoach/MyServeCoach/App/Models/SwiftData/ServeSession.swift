import Foundation
import SwiftData

@Model
final class ServeSession {
    var id: UUID = UUID()
    var date: Date = Date.now
    var inputType: String = ""
    var videoURL: URL?
    @Relationship(deleteRule: .cascade) var phases: [PhaseRecord] = []

    init(inputType: String, videoURL: URL?) {
        self.inputType = inputType
        self.videoURL = videoURL
    }
}
