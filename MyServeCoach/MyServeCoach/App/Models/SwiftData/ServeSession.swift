import Foundation
import SwiftData

@Model
final class ServeSession {
    var id: UUID = UUID()
    var date: Date = Date.now
    var inputType: String = ""
    var videoURL: URL?
    var mode: String = "lite"
    @Relationship(deleteRule: .cascade) var phases: [PhaseRecord] = []
    @Relationship(deleteRule: .cascade) var results: [ServeResult] = []

    init(inputType: String, videoURL: URL?, mode: String = "lite") {
        self.inputType = inputType
        self.videoURL = videoURL
        self.mode = mode
    }
}
