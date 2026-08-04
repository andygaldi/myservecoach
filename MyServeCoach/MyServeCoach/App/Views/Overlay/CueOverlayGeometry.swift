import CoreGraphics
import Foundation

/// What a cue's ideal looks like, expressed entirely in normalized (backend) coordinates so the
/// view layer only has to map points through `PoseSkeletonGeometry.point(_:in:)`.
///
/// Everything here is derived in normalized space on purpose: the backend computes its angles on
/// normalized coordinates (`backend/app/engine/angles.py`), where the image's aspect ratio is
/// squashed into a unit square. Deriving an ideal direction on screen instead would place the
/// dashed ray somewhere the reported number doesn't correspond to.
enum IdealIndicator: Equatable {
    /// Dashed rays from `origin` to each ideal endpoint, plus an arc polyline sweeping from the
    /// measured direction to the nearest ideal one.
    case rays(origin: CGPoint, endpoints: [CGPoint], arc: [CGPoint])
    /// A band of acceptable positions. `nil` bounds are open to that edge of the frame.
    case horizontalBand(minY: CGFloat?, maxY: CGFloat?)
    case verticalBand(minX: CGFloat?, maxX: CGFloat?)
    /// A target region for a ball offset, plus the ball's actual centre when detected.
    case box(CGRect, ball: CGPoint?)
}

enum CueOverlayGeometry {
    /// The joints the rule measured, as a normalized polyline — the segment the overlay
    /// highlights.
    ///
    /// All-or-nothing: if any joint is missing or below confidence, this returns `[]` rather than
    /// a shortened polyline. Skipping a joint would redraw the limb as something it isn't — drop
    /// a low-confidence elbow from `release_toss_arm_straight` and shoulder→wrist renders as a
    /// perfectly *straight* arm directly beneath the cue "Straighten your tossing arm."
    static func highlightedPolyline(for cue: Cue, in frame: BackendFrame) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(cue.joints.count)
        for name in cue.joints {
            guard let joint = PoseSkeletonGeometry.joint(name, in: frame) else { return [] }
            points.append(joint)
        }
        return points
    }

    /// The drawn representation of the cue's ideal, or `nil` when the metric is unrecognized or
    /// its joints aren't available. An unknown metric degrades to skeleton + highlight only.
    static func indicator(
        for cue: Cue, in frame: BackendFrame, detections: [BackendDetection]
    ) -> IdealIndicator? {
        guard let metric = cue.metric else { return nil }

        switch metric {
        case "angle":
            return angleIndicator(for: cue, in: frame)
        case "angle_from_vertical":
            return angleFromVerticalIndicator(for: cue, in: frame)
        case "y_diff":
            guard let reference = joint(cue, 1, frame) else { return nil }
            return .horizontalBand(
                minY: cue.lowerBound.map { reference.y + $0 },
                maxY: cue.upperBound.map { reference.y + $0 }
            )
        case "x_diff":
            guard let reference = joint(cue, 1, frame) else { return nil }
            return .verticalBand(
                minX: cue.lowerBound.map { reference.x + $0 },
                maxX: cue.upperBound.map { reference.x + $0 }
            )
        case "ball_offset_x", "ball_offset_y":
            return ballOffsetIndicator(for: cue, metric: metric, in: frame, detections: detections)
        default:
            return nil
        }
    }

    // MARK: - Per-metric construction

    private static func angleIndicator(for cue: Cue, in frame: BackendFrame) -> IdealIndicator? {
        // joints = [a, b, c]; the angle is measured at vertex b, between b→a and b→c.
        guard cue.joints.count >= 3,
              let a = joint(cue, 0, frame),
              let b = joint(cue, 1, frame),
              let c = joint(cue, 2, frame) else { return nil }

        let reference = vector(from: b, to: a)
        let measured = vector(from: b, to: c)
        let length = magnitude(measured)
        guard length > 0, magnitude(reference) > 0 else { return nil }

        // Rotate away from the reference arm on whichever side `c` actually lies, so the ideal
        // ray reads as "your arm should be here", not mirrored across the body.
        let side: CGFloat = cross(reference, measured) < 0 ? -1 : 1
        let endpoints = cue.bounds.map { bound in
            offset(b, by: scale(rotate(normalize(reference), degrees: side * bound), length))
        }
        guard !endpoints.isEmpty else { return nil }

        let nearestBound = cue.bounds.min { abs($0 - (cue.measuredValue ?? 0)) < abs($1 - (cue.measuredValue ?? 0)) }
        let arcPoints = arc(
            origin: b,
            from: measured,
            toDegreesFromReference: nearestBound,
            reference: reference,
            side: side,
            radius: length * 0.45
        )
        return .rays(origin: b, endpoints: endpoints, arc: arcPoints)
    }

    private static func angleFromVerticalIndicator(for cue: Cue, in frame: BackendFrame) -> IdealIndicator? {
        // joints = [a, b]; the angle is measured between straight-up vertical at `a` and a→b.
        guard cue.joints.count >= 2,
              let a = joint(cue, 0, frame),
              let b = joint(cue, 1, frame) else { return nil }

        let up = CGVector(dx: 0, dy: 1)
        let measured = vector(from: a, to: b)
        let length = magnitude(measured)
        guard length > 0 else { return nil }

        let side: CGFloat = cross(up, measured) < 0 ? -1 : 1
        var endpoints = cue.bounds.map { bound in
            offset(a, by: scale(rotate(up, degrees: side * bound), length))
        }
        // Vertical itself is the thing the rule is asking for, so show it as the datum.
        endpoints.insert(offset(a, by: scale(up, length)), at: 0)

        let nearestBound = cue.bounds.min { abs($0 - (cue.measuredValue ?? 0)) < abs($1 - (cue.measuredValue ?? 0)) }
        let arcPoints = arc(
            origin: a,
            from: measured,
            toDegreesFromReference: nearestBound,
            reference: up,
            side: side,
            radius: length * 0.45
        )
        return .rays(origin: a, endpoints: endpoints, arc: arcPoints)
    }

    private static func ballOffsetIndicator(
        for cue: Cue, metric: String, in frame: BackendFrame, detections: [BackendDetection]
    ) -> IdealIndicator? {
        guard let reference = joint(cue, 0, frame) else { return nil }

        // The rule constrains one axis; the box spans a fixed, readable extent on the other.
        let crossExtent: CGFloat = 0.12
        // An open-ended comparison (gte/lte) has no far edge. Run the box out to the frame
        // boundary rather than closing it at an arbitrary width — a `gte 0.30` rule drawn as
        // 0.30–0.42 would imply 0.50 is out of range when the rule accepts it.
        let lower = cue.lowerBound ?? -1
        let upper = cue.upperBound ?? 1

        let rect: CGRect
        if metric == "ball_offset_y" {
            rect = CGRect(
                x: reference.x - crossExtent, y: reference.y + lower,
                width: crossExtent * 2, height: upper - lower
            )
        } else {
            rect = CGRect(
                x: reference.x + lower, y: reference.y - crossExtent,
                width: upper - lower, height: crossExtent * 2
            )
        }

        let ball = detections.first { $0.label == "ball" }.map {
            CGPoint(
                x: CGFloat($0.bbox.xMin + $0.bbox.xMax) / 2,
                y: CGFloat($0.bbox.yMin + $0.bbox.yMax) / 2
            )
        }
        return .box(rect.standardized, ball: ball)
    }

    // MARK: - Vector helpers (normalized space, y up)

    private static func joint(_ cue: Cue, _ index: Int, _ frame: BackendFrame) -> CGPoint? {
        guard cue.joints.indices.contains(index) else { return nil }
        return PoseSkeletonGeometry.joint(cue.joints[index], in: frame)
    }

    private static func vector(from a: CGPoint, to b: CGPoint) -> CGVector {
        CGVector(dx: b.x - a.x, dy: b.y - a.y)
    }

    private static func magnitude(_ v: CGVector) -> CGFloat { hypot(v.dx, v.dy) }

    private static func normalize(_ v: CGVector) -> CGVector {
        let m = magnitude(v)
        guard m > 0 else { return v }
        return CGVector(dx: v.dx / m, dy: v.dy / m)
    }

    private static func scale(_ v: CGVector, _ factor: CGFloat) -> CGVector {
        CGVector(dx: v.dx * factor, dy: v.dy * factor)
    }

    private static func offset(_ p: CGPoint, by v: CGVector) -> CGPoint {
        CGPoint(x: p.x + v.dx, y: p.y + v.dy)
    }

    private static func cross(_ a: CGVector, _ b: CGVector) -> CGFloat {
        a.dx * b.dy - a.dy * b.dx
    }

    /// Rotates counter-clockwise in normalized space (y up).
    static func rotate(_ v: CGVector, degrees: CGFloat) -> CGVector {
        let r = degrees * .pi / 180
        return CGVector(
            dx: v.dx * cos(r) - v.dy * sin(r),
            dy: v.dx * sin(r) + v.dy * cos(r)
        )
    }

    /// Samples the sweep between the measured direction and the nearest ideal bound as a
    /// polyline. Sampled in normalized space and mapped point-by-point so the drawn arc follows
    /// the same distortion as the skeleton rather than reading as a true circle on screen.
    private static func arc(
        origin: CGPoint,
        from measured: CGVector,
        toDegreesFromReference bound: CGFloat?,
        reference: CGVector,
        side: CGFloat,
        radius: CGFloat
    ) -> [CGPoint] {
        guard let bound, radius > 0, magnitude(measured) > 0 else { return [] }

        let idealDirection = rotate(normalize(reference), degrees: side * bound)
        let measuredDirection = normalize(measured)
        let sweep = signedAngle(from: measuredDirection, to: idealDirection)
        guard abs(sweep) > 0.001 else { return [] }

        let steps = 16
        return (0...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            let direction = rotate(measuredDirection, degrees: sweep * t)
            return offset(origin, by: scale(direction, radius))
        }
    }

    /// Signed angle in degrees from `a` to `b`, in (-180, 180].
    private static func signedAngle(from a: CGVector, to b: CGVector) -> CGFloat {
        atan2(cross(a, b), a.dx * b.dx + a.dy * b.dy) * 180 / .pi
    }
}

extension Cue {
    /// The rule's threshold bound(s), whichever form the comparison uses.
    var bounds: [CGFloat] {
        switch comparison {
        case "range":
            return [thresholdMin, thresholdMax].compactMap { $0.map { CGFloat($0) } }
        case "gte", "lte":
            return threshold.map { [CGFloat($0)] } ?? []
        default:
            return []
        }
    }

    /// Lower/upper bound in the metric's own units — `nil` where the comparison is open-ended.
    var lowerBound: CGFloat? {
        switch comparison {
        case "range": return thresholdMin.map { CGFloat($0) }
        case "gte": return threshold.map { CGFloat($0) }
        default: return nil
        }
    }

    var upperBound: CGFloat? {
        switch comparison {
        case "range": return thresholdMax.map { CGFloat($0) }
        case "lte": return threshold.map { CGFloat($0) }
        default: return nil
        }
    }
}
