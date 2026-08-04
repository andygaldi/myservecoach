import Foundation

/// One retained phase frame for a Pro 2D serve: the image extracted at the backend-reported
/// timestamp, plus the keypoints and detections the overlay renderer draws from.
struct AssessmentPhaseFrame: Sendable {
    let phase: String
    let timestamp: Double
    /// JPEG, downscaled per `PhaseFrameImageEncoder`.
    let imageData: Data
    let frame: BackendFrame
    let detections: [BackendDetection]
}

enum AssessmentPhaseConstants {
    /// The four coaching-relevant phases shown on the results screen. The backend also detects
    /// `start` and `finish`, but no rule in `rules.json` targets them, so their frames would be
    /// inert — they're deliberately not extracted or displayed.
    static let displayedPhases = ["release", "trophy_pose", "racket_drop", "contact"]

    /// Display labels for the phase keys above, shared by the live results and history screens.
    static func label(for phase: String) -> String {
        switch phase {
        case "start": "Start"
        case "release": "Release"
        case "trophy_pose": "Trophy pose"
        case "racket_drop": "Racket drop"
        case "contact": "Contact"
        case "finish": "Finish"
        default: phase.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
