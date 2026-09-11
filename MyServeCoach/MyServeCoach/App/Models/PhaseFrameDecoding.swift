import Foundation
import UIKit

/// Shared image/keypoints/detections decode for a persisted phase-frame record, used by both
/// Assessment's `AssessmentHistoryPresenter` and Set Goal's `PersistedGoalAttemptDisplay` — the
/// two places that rehydrate a `PhaseFrameRecord`-shaped model back into overlay-ready types.
enum PhaseFrameDecoding {
    struct Decoded {
        let image: UIImage
        /// `nil` when the keypoints won't decode — the still image shows without a skeleton.
        let frame: BackendFrame?
        let detections: [BackendDetection]
    }

    /// Returns `nil` when the image data itself won't decode — nothing to draw on. A keypoints/
    /// detections decode failure degrades gracefully instead (frame `nil`/detections empty).
    static func decode(frameImageData: Data, keypointsJSON: Data, detectionsJSON: Data) -> Decoded? {
        guard let image = UIImage(data: frameImageData) else { return nil }
        let decoder = JSONDecoder()
        return Decoded(
            image: image,
            frame: try? decoder.decode(BackendFrame.self, from: keypointsJSON),
            detections: (try? decoder.decode([BackendDetection].self, from: detectionsJSON)) ?? []
        )
    }
}
