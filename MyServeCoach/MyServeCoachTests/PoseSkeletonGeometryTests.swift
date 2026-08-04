import Testing
import CoreGraphics
@testable import MyServeCoach

@Suite("PoseSkeletonGeometry Tests")
struct PoseSkeletonGeometryTests {

    private let bounds = CGRect(x: 0, y: 0, width: 200, height: 400)

    // MARK: - Coordinate mapping

    @Test("normalized y is flipped: y=0 is the bottom of the rect, y=1 the top")
    func flipsYAxis() {
        let bottom = PoseSkeletonGeometry.point(CGPoint(x: 0.5, y: 0.0), in: bounds)
        let top = PoseSkeletonGeometry.point(CGPoint(x: 0.5, y: 1.0), in: bounds)

        #expect(bottom.y == bounds.maxY)
        #expect(top.y == bounds.minY)
    }

    @Test("normalized x is not flipped: x=0 is the left edge, x=1 the right")
    func doesNotFlipXAxis() {
        let left = PoseSkeletonGeometry.point(CGPoint(x: 0.0, y: 0.5), in: bounds)
        let right = PoseSkeletonGeometry.point(CGPoint(x: 1.0, y: 0.5), in: bounds)

        #expect(left.x == bounds.minX)
        #expect(right.x == bounds.maxX)
    }

    @Test("mapping is relative to the given rect's origin, not the view origin")
    func respectsRectOrigin() {
        let offset = CGRect(x: 50, y: 30, width: 100, height: 200)
        let point = PoseSkeletonGeometry.point(CGPoint(x: 0.0, y: 1.0), in: offset)

        #expect(point.x == 50)
        #expect(point.y == 30)
    }

    @Test("the centre maps to the rect's centre")
    func centreMapsToCentre() {
        let point = PoseSkeletonGeometry.point(CGPoint(x: 0.5, y: 0.5), in: bounds)

        #expect(point.x == bounds.midX)
        #expect(point.y == bounds.midY)
    }

    // MARK: - Aspect fit

    @Test("a portrait image in landscape bounds is letterboxed horizontally")
    func portraitImageInLandscapeBounds() {
        let rect = PoseSkeletonGeometry.fittedRect(
            imageSize: CGSize(width: 720, height: 1280),
            in: CGRect(x: 0, y: 0, width: 400, height: 200)
        )

        #expect(rect.height == 200)
        #expect(abs(rect.width - 200 * (720.0 / 1280.0)) < 0.001)
        #expect(abs(rect.midX - 200) < 0.001)  // horizontally centred in the 400-wide bounds
        #expect(rect.minY == 0)
    }

    @Test("a landscape image in portrait bounds is letterboxed vertically")
    func landscapeImageInPortraitBounds() {
        let rect = PoseSkeletonGeometry.fittedRect(
            imageSize: CGSize(width: 1280, height: 720),
            in: CGRect(x: 0, y: 0, width: 200, height: 400)
        )

        #expect(rect.width == 200)
        #expect(abs(rect.height - 200 * (720.0 / 1280.0)) < 0.001)
        #expect(abs(rect.midY - 200) < 0.001)
        #expect(rect.minX == 0)
    }

    @Test("a matching aspect ratio fills the bounds exactly")
    func matchingAspectRatioFillsBounds() {
        let rect = PoseSkeletonGeometry.fittedRect(
            imageSize: CGSize(width: 360, height: 720),
            in: bounds
        )

        #expect(rect == bounds)
    }

    @Test("a degenerate image size falls back to the bounds rather than dividing by zero")
    func degenerateImageSizeFallsBack() {
        let rect = PoseSkeletonGeometry.fittedRect(imageSize: .zero, in: bounds)

        #expect(rect == bounds)
    }

    // MARK: - Joints & bones

    private func frame(_ keypoints: [String: (Float, Float, Float)]) -> BackendFrame {
        BackendFrame(timestamp: 0, keypoints: keypoints.mapValues {
            BackendKeypoint(x: $0.0, y: $0.1, confidence: $0.2)
        })
    }

    @Test("a joint below the confidence floor does not resolve")
    func lowConfidenceJointIsSkipped() {
        let f = frame([
            "left_wrist": (0.4, 0.6, PoseSkeletonGeometry.minConfidence - 0.1),
            "left_elbow": (0.4, 0.5, 0.9),
        ])

        #expect(PoseSkeletonGeometry.joint("left_wrist", in: f) == nil)
        #expect(PoseSkeletonGeometry.joint("left_elbow", in: f) != nil)
    }

    @Test("a missing joint does not resolve")
    func missingJointIsNil() {
        #expect(PoseSkeletonGeometry.joint("left_wrist", in: frame([:])) == nil)
    }

    @Test("a bone is only drawn when both of its endpoints resolve")
    func boneRequiresBothEndpoints() {
        let f = frame([
            "left_shoulder": (0.4, 0.6, 0.9),
            "left_elbow": (0.4, 0.5, 0.9),
            "left_wrist": (0.4, 0.4, 0.1),  // below confidence → elbow–wrist bone dropped
        ])

        let segments = PoseSkeletonGeometry.boneSegments(in: f)

        // Float→CGFloat widening makes 0.6 inexact, so compare with tolerance.
        #expect(segments.count == 1)
        #expect(abs(segments[0].0.x - 0.4) < 0.0001)
        #expect(abs(segments[0].0.y - 0.6) < 0.0001)
        #expect(abs(segments[0].1.y - 0.5) < 0.0001)
    }

    @Test("an empty frame yields no bones rather than crashing")
    func emptyFrameYieldsNoBones() {
        #expect(PoseSkeletonGeometry.boneSegments(in: frame([:])).isEmpty)
    }

    @Test("the confidence floor is pinned to the value the backend rule engine uses")
    func confidenceFloorIsPinned() {
        // A change-detector, not a cross-language check: this asserts the iOS constant hasn't
        // been altered casually. It cannot observe `MIN_CONFIDENCE` in
        // backend/app/engine/angles.py drifting — if that value changes, this test keeps passing
        // and the overlay silently starts drawing joints the rule engine ignored. Keeping the
        // two in step is a manual obligation.
        #expect(PoseSkeletonGeometry.minConfidence == 0.4)
    }

    @Test("only joints at or above the floor are drawn, and the boundary value is included")
    func confidenceFloorBoundaryIsInclusive() {
        let f = frame([
            "left_shoulder": (0.4, 0.6, PoseSkeletonGeometry.minConfidence),
            "left_elbow": (0.4, 0.5, PoseSkeletonGeometry.minConfidence - 0.0001),
        ])

        #expect(PoseSkeletonGeometry.joint("left_shoulder", in: f) != nil)
        #expect(PoseSkeletonGeometry.joint("left_elbow", in: f) == nil)
    }

    // MARK: - Joint deduplication

    @Test("jointNames deduplicates joints shared by several bones")
    func jointNamesAreDeduplicated() {
        // `bones` names 24 endpoints across 12 distinct joints; shoulders and hips each appear in
        // three bones. Drawing per-bone would composite their dots three times.
        #expect(PoseSkeletonGeometry.jointNames.count == 12)
        #expect(Set(PoseSkeletonGeometry.jointNames).count == PoseSkeletonGeometry.jointNames.count)
        #expect(PoseSkeletonGeometry.jointNames.contains("left_shoulder"))
    }

    @Test("jointPoints returns one point per resolvable distinct joint")
    func jointPointsAreDeduplicated() {
        let f = frame([
            "left_shoulder": (0.4, 0.6, 0.9),   // appears in 3 bones
            "right_shoulder": (0.6, 0.6, 0.9),  // appears in 3 bones
            "left_elbow": (0.3, 0.5, 0.9),
        ])

        #expect(PoseSkeletonGeometry.jointPoints(in: f).count == 3)
    }
}
