import CoreMedia
import UIKit

enum ServePhase: String, CaseIterable {
    case trophyPose = "Trophy Pose"
    case racketDrop = "Racket Drop"
    case contactPoint = "Contact Point"
}

struct PhaseFrame {
    let phase: ServePhase
    let timestamp: CMTime
    var thumbnail: UIImage?
}
