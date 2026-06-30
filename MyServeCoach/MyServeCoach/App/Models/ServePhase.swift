import CoreMedia
import UIKit

enum ServePhase: String, CaseIterable {
    case trophyPose = "Trophy Pose"
    case racketDrop = "Racket Drop"
    case contactPoint = "Contact Point"

    var backendKey: String {
        switch self {
        case .trophyPose: return "trophy_pose"
        case .racketDrop: return "racket_drop"
        case .contactPoint: return "contact"
        }
    }

    init?(backendKey: String) {
        guard let match = ServePhase.allCases.first(where: { $0.backendKey == backendKey }) else {
            return nil
        }
        self = match
    }
}

struct PhaseFrame {
    let phase: ServePhase
    let timestamp: CMTime
    var thumbnail: UIImage?
}
