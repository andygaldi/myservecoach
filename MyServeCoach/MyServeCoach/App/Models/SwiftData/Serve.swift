import Foundation
import SwiftData

/// Represents a single recorded and analyzed tennis serve session.
@Model
final class Serve {
    var id: UUID
    var date: Date
    /// Local file URL of the recorded video clip.
    var videoURL: URL
    /// Raw keypoints JSON string posted to and received from the backend.
    /// Stored as String to avoid premature schema commitment while the backend format is in flux.
    var keypointsJSON: String?
    /// Coaching cues returned by the backend analysis.
    var coachingCues: [String]
    /// Tracks where the serve is in the analysis pipeline.
    var analysisStatus: AnalysisStatus

    init(
        id: UUID = UUID(),
        date: Date = .now,
        videoURL: URL,
        keypointsJSON: String? = nil,
        coachingCues: [String] = [],
        analysisStatus: AnalysisStatus = .pending
    ) {
        self.id = id
        self.date = date
        self.videoURL = videoURL
        self.keypointsJSON = keypointsJSON
        self.coachingCues = coachingCues
        self.analysisStatus = analysisStatus
    }
}

enum AnalysisStatus: String, Codable {
    case pending
    case processing
    case complete
    case failed
}
