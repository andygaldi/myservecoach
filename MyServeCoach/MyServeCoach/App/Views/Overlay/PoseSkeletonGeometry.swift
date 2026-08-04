import CoreGraphics

/// Maps backend keypoints into drawing space.
///
/// **Coordinate convention:** backend keypoints are normalized 0–1 with *Vision's* convention —
/// origin bottom-left, y increasing **upward** (`backend/app/services/pose_model.py` flips y when
/// it normalizes). SwiftUI's `Canvas` is origin top-left, y increasing **downward**. Every mapping
/// here flips y; drawing a raw keypoint straight into a `Canvas` would render the skeleton upside
/// down.
enum PoseSkeletonGeometry {
    /// COCO-17-derived bone pairs, shared by the RTMPose backend output
    /// (`COCO17_KEYPOINT_NAMES`) and the Vision-mapped joint names (`VisionJointMapper`).
    static let bones: [(String, String)] = [
        ("left_shoulder", "right_shoulder"),
        ("left_shoulder", "left_elbow"),
        ("left_elbow", "left_wrist"),
        ("right_shoulder", "right_elbow"),
        ("right_elbow", "right_wrist"),
        ("left_shoulder", "left_hip"),
        ("right_shoulder", "right_hip"),
        ("left_hip", "right_hip"),
        ("left_hip", "left_knee"),
        ("left_knee", "left_ankle"),
        ("right_hip", "right_knee"),
        ("right_knee", "right_ankle"),
    ]

    /// Matches `MIN_CONFIDENCE` in `backend/app/engine/angles.py`, so the overlay draws exactly
    /// the joints the rule engine was willing to measure.
    static let minConfidence: Float = 0.4

    /// Maps a normalized Vision-convention point (origin bottom-left, y up) into a point inside
    /// `rect` in `Canvas` space (origin top-left, y down).
    static func point(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: rect.minY + (1 - normalized.y) * rect.height
        )
    }

    /// The rect an image of `imageSize` occupies when aspect-fitted inside `bounds`.
    ///
    /// The overlay must draw into this, not into `bounds` — otherwise the skeleton is offset by
    /// the letterbox bars whenever the image and the view disagree on aspect ratio.
    static func fittedRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.minX + (bounds.width - size.width) / 2,
            y: bounds.minY + (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The normalized position of a joint, or `nil` when it is missing or below confidence.
    static func joint(_ name: String, in frame: BackendFrame) -> CGPoint? {
        guard let keypoint = frame.keypoints[name], keypoint.confidence >= minConfidence else {
            return nil
        }
        return CGPoint(x: CGFloat(keypoint.x), y: CGFloat(keypoint.y))
    }

    /// Bone endpoint pairs, in normalized coordinates, for every bone whose both ends resolve.
    static func boneSegments(in frame: BackendFrame) -> [(CGPoint, CGPoint)] {
        bones.compactMap { bone in
            guard let a = joint(bone.0, in: frame), let b = joint(bone.1, in: frame) else { return nil }
            return (a, b)
        }
    }

    /// The distinct joints referenced by `bones`, in a stable order.
    ///
    /// Deduplicated on purpose: a joint appears in up to three bones (shoulders and hips do), and
    /// iterating `bones` directly would composite its translucent dot once per incident bone —
    /// rendering hubs near-opaque while wrists and ankles stay dim, which inverts the flat,
    /// dimmed look the skeleton is going for.
    static let jointNames: [String] = {
        var seen: Set<String> = []
        return bones.flatMap { [$0.0, $0.1] }.filter { seen.insert($0).inserted }
    }()

    /// Normalized positions of every distinct joint that resolves in `frame`.
    static func jointPoints(in frame: BackendFrame) -> [CGPoint] {
        jointNames.compactMap { joint($0, in: frame) }
    }
}
