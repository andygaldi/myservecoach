import Testing
import CoreGraphics
@testable import MyServeCoach

@Suite("CueOverlayGeometry Tests")
struct CueOverlayGeometryTests {

    private func frame(_ keypoints: [String: (Float, Float)]) -> BackendFrame {
        BackendFrame(timestamp: 0, keypoints: keypoints.mapValues {
            BackendKeypoint(x: $0.0, y: $0.1, confidence: 0.9)
        })
    }

    private func cue(
        metric: String, joints: [String], comparison: String,
        threshold: Double? = nil, min: Double? = nil, max: Double? = nil,
        measured: Double? = 0
    ) -> Cue {
        Cue(
            ruleId: "r", phase: "trophy_pose", message: "m", severity: "major",
            metric: metric, joints: joints, measuredValue: measured, comparison: comparison,
            threshold: threshold, thresholdMin: min, thresholdMax: max
        )
    }

    /// Keypoints are `Float` on the wire and `CGFloat` (Double) in geometry, so values like 0.6
    /// don't survive the widening exactly — every point comparison here is tolerance-based.
    private func isClose(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 0.0001) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    private func ball(x: Float, y: Float) -> BackendDetection {
        BackendDetection(label: "ball", confidence: 0.9, bbox: BackendBoundingBox(
            xMin: x - 0.02, yMin: y - 0.02, xMax: x + 0.02, yMax: y + 0.02
        ))
    }

    // MARK: - Highlighted segment

    @Test("the highlighted polyline is the rule's joints in order")
    func highlightsRuleJointsInOrder() {
        let f = frame(["left_shoulder": (0.4, 0.6), "left_wrist": (0.8, 0.9)])
        let points = CueOverlayGeometry.highlightedPolyline(
            for: cue(metric: "angle_from_vertical", joints: ["left_shoulder", "left_wrist"], comparison: "lte", threshold: 45),
            in: f
        )

        #expect(points.count == 2)
        #expect(isClose(points[0], CGPoint(x: 0.4, y: 0.6)))
        #expect(isClose(points[1], CGPoint(x: 0.8, y: 0.9)))
    }

    @Test("a highlight with any unresolvable joint is dropped entirely, not shortened")
    func partialJointsYieldNoHighlight() {
        // Shortening would redraw the limb as something it isn't: drop the elbow from a
        // three-joint arm rule and shoulder→wrist reads as a perfectly straight arm, directly
        // under a cue saying the arm is bent.
        let f = BackendFrame(timestamp: 0, keypoints: [
            "left_shoulder": BackendKeypoint(x: 0.4, y: 0.6, confidence: 0.9),
            "left_elbow": BackendKeypoint(x: 0.5, y: 0.75, confidence: 0.1),  // below floor
            "left_wrist": BackendKeypoint(x: 0.4, y: 0.9, confidence: 0.9),
        ])
        let points = CueOverlayGeometry.highlightedPolyline(
            for: cue(metric: "angle", joints: ["left_shoulder", "left_elbow", "left_wrist"],
                     comparison: "gte", threshold: 155),
            in: f
        )

        #expect(points.isEmpty)
    }

    @Test("a highlight resolves fully when every joint is confident")
    func allConfidentJointsYieldFullPolyline() {
        let f = frame(["left_shoulder": (0.4, 0.6), "left_elbow": (0.5, 0.75), "left_wrist": (0.4, 0.9)])
        let points = CueOverlayGeometry.highlightedPolyline(
            for: cue(metric: "angle", joints: ["left_shoulder", "left_elbow", "left_wrist"],
                     comparison: "gte", threshold: 155),
            in: f
        )

        #expect(points.count == 3)
    }

    // MARK: - angle_from_vertical

    @Test("an angle_from_vertical ideal ray sits at the threshold angle off vertical, on the arm's side")
    func angleFromVerticalRayIsOnTheArmsSide() throws {
        // Shoulder at (0.4,0.6), wrist up-and-right at 45° → arm is on the +x side of vertical.
        let f = frame(["left_shoulder": (0.4, 0.6), "left_wrist": (0.7, 0.9)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "angle_from_vertical", joints: ["left_shoulder", "left_wrist"],
                     comparison: "lte", threshold: 30, measured: 45),
            in: f, detections: []
        )

        guard case let .rays(origin, endpoints, _) = try #require(indicator) else {
            Issue.record("expected .rays"); return
        }
        #expect(isClose(origin, CGPoint(x: 0.4, y: 0.6)))
        // First endpoint is the vertical datum, second the 30° ideal.
        #expect(endpoints.count == 2)
        #expect(abs(endpoints[0].x - origin.x) < 0.0001)   // straight up: same x
        #expect(endpoints[0].y > origin.y)            // and above the shoulder
        #expect(endpoints[1].x > origin.x)            // ideal leans to the arm's side, not mirrored
        #expect(endpoints[1].y > origin.y)

        // 30° off vertical at the arm's length: verify the angle actually is 30°.
        let armLength = hypot(0.3, 0.3)
        let dx = endpoints[1].x - origin.x
        let dy = endpoints[1].y - origin.y
        #expect(abs(hypot(dx, dy) - armLength) < 0.0001)
        #expect(abs(atan2(dx, dy) * 180 / .pi - 30) < 0.0001)
    }

    @Test("an arm on the left of vertical gets its ideal ray mirrored to the left")
    func angleFromVerticalMirrorsForLeftLeaningArm() throws {
        let f = frame(["left_shoulder": (0.4, 0.6), "left_wrist": (0.1, 0.9)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "angle_from_vertical", joints: ["left_shoulder", "left_wrist"],
                     comparison: "lte", threshold: 30, measured: 45),
            in: f, detections: []
        )

        guard case let .rays(origin, endpoints, _) = try #require(indicator) else {
            Issue.record("expected .rays"); return
        }
        #expect(endpoints[1].x < origin.x)
    }

    // MARK: - angle

    @Test("an angle range rule produces one ideal ray per bound")
    func angleRangeProducesTwoRays() throws {
        let f = frame([
            "left_shoulder": (0.2, 0.6), "right_shoulder": (0.5, 0.6), "right_elbow": (0.8, 0.5),
        ])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "angle", joints: ["left_shoulder", "right_shoulder", "right_elbow"],
                     comparison: "range", min: 155, max: 180, measured: 135),
            in: f, detections: []
        )

        guard case let .rays(origin, endpoints, _) = try #require(indicator) else {
            Issue.record("expected .rays"); return
        }
        #expect(isClose(origin, CGPoint(x: 0.5, y: 0.6)))  // vertex is joints[1]
        #expect(endpoints.count == 2)
    }

    @Test("an ideal ray keeps the measured segment's length so it reads as the same limb")
    func idealRayMatchesLimbLength() throws {
        let f = frame([
            "left_shoulder": (0.2, 0.6), "right_shoulder": (0.5, 0.6), "right_elbow": (0.8, 0.6),
        ])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "angle", joints: ["left_shoulder", "right_shoulder", "right_elbow"],
                     comparison: "gte", threshold: 155, measured: 180),
            in: f, detections: []
        )

        guard case let .rays(origin, endpoints, _) = try #require(indicator) else {
            Issue.record("expected .rays"); return
        }
        let length = hypot(endpoints[0].x - origin.x, endpoints[0].y - origin.y)
        #expect(abs(length - 0.3) < 0.0001)  // |right_shoulder → right_elbow| == 0.3
    }

    @Test("a degenerate zero-length segment yields no indicator rather than dividing by zero")
    func degenerateSegmentYieldsNoIndicator() {
        let f = frame(["left_shoulder": (0.4, 0.6), "left_wrist": (0.4, 0.6)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "angle_from_vertical", joints: ["left_shoulder", "left_wrist"], comparison: "lte", threshold: 45),
            in: f, detections: []
        )

        #expect(indicator == nil)
    }

    // MARK: - Bands

    @Test("a y_diff range band is offset from the reference joint on the y axis")
    func yDiffBandOffsetFromReference() throws {
        // y_diff = y(joints[0]) - y(joints[1]); reference joint is joints[1].
        let f = frame(["left_wrist": (0.4, 0.95), "nose": (0.4, 0.9)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "y_diff", joints: ["left_wrist", "nose"],
                     comparison: "range", min: -0.04, max: 0.10, measured: 0.05),
            in: f, detections: []
        )

        guard case let .horizontalBand(minY, maxY) = try #require(indicator) else {
            Issue.record("expected .horizontalBand"); return
        }
        #expect(abs(try #require(minY) - (0.9 - 0.04)) < 0.0001)
        #expect(abs(try #require(maxY) - (0.9 + 0.10)) < 0.0001)
    }

    @Test("an lte band is open at the lower edge and a gte band open at the upper")
    func openEndedBands() throws {
        let f = frame(["left_wrist": (0.4, 0.95), "nose": (0.4, 0.9)])

        let lte = CueOverlayGeometry.indicator(
            for: cue(metric: "y_diff", joints: ["left_wrist", "nose"], comparison: "lte", threshold: 0.1),
            in: f, detections: []
        )
        guard case let .horizontalBand(lteMin, lteMax) = try #require(lte) else {
            Issue.record("expected .horizontalBand"); return
        }
        #expect(lteMin == nil)
        #expect(abs(try #require(lteMax) - 1.0) < 0.0001)

        let gte = CueOverlayGeometry.indicator(
            for: cue(metric: "y_diff", joints: ["left_wrist", "nose"], comparison: "gte", threshold: 0.1),
            in: f, detections: []
        )
        guard case let .horizontalBand(gteMin, gteMax) = try #require(gte) else {
            Issue.record("expected .horizontalBand"); return
        }
        #expect(abs(try #require(gteMin) - 1.0) < 0.0001)
        #expect(gteMax == nil)
    }

    @Test("an x_diff rule produces a vertical band")
    func xDiffProducesVerticalBand() throws {
        let f = frame(["right_shoulder": (0.41, 0.62), "left_shoulder": (0.4, 0.6)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "x_diff", joints: ["right_shoulder", "left_shoulder"],
                     comparison: "range", min: -0.09, max: 0.04, measured: 0.01),
            in: f, detections: []
        )

        guard case let .verticalBand(minX, maxX) = try #require(indicator) else {
            Issue.record("expected .verticalBand"); return
        }
        #expect(abs(try #require(minX) - (0.4 - 0.09)) < 0.0001)
        #expect(abs(try #require(maxX) - (0.4 + 0.04)) < 0.0001)
    }

    // MARK: - Ball offsets

    @Test("a ball_offset_y box spans the threshold range above the reference joint")
    func ballOffsetYBoxSpansRange() throws {
        let f = frame(["left_shoulder": (0.4, 0.6)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "ball_offset_y", joints: ["left_shoulder"],
                     comparison: "range", min: 0.28, max: 0.40, measured: 0.6),
            in: f, detections: [ball(x: 0.45, y: 1.2)]
        )

        guard case let .box(rect, ballCentre) = try #require(indicator) else {
            Issue.record("expected .box"); return
        }
        #expect(abs(rect.minY - (0.6 + 0.28)) < 0.0001)
        #expect(abs(rect.maxY - (0.6 + 0.40)) < 0.0001)
        #expect(abs(try #require(ballCentre).y - 1.2) < 0.0001)
        #expect(abs(try #require(ballCentre).x - 0.45) < 0.0001)
    }

    @Test("a ball_offset_x box spans the threshold range beside the reference joint")
    func ballOffsetXBoxSpansRange() throws {
        let f = frame(["left_shoulder": (0.4, 0.6)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "ball_offset_x", joints: ["left_shoulder"],
                     comparison: "range", min: -0.01, max: 0.12, measured: 0.3),
            in: f, detections: [ball(x: 0.7, y: 0.9)]
        )

        guard case let .box(rect, _) = try #require(indicator) else {
            Issue.record("expected .box"); return
        }
        #expect(abs(rect.minX - (0.4 - 0.01)) < 0.0001)
        #expect(abs(rect.maxX - (0.4 + 0.12)) < 0.0001)
    }

    @Test("an open-ended ball-offset rule runs its box to the frame edge, not an arbitrary width")
    func openEndedBallOffsetBoxIsNotClosed() throws {
        // A `gte 0.30` rule accepts 0.50; closing the box at a fixed width would draw a target
        // zone implying otherwise. Latent today (both ball rules are `range`) but wrong if a
        // future rules.json adds an open-ended one.
        let f = frame(["left_shoulder": (0.4, 0.6)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "ball_offset_y", joints: ["left_shoulder"],
                     comparison: "gte", threshold: 0.30, measured: 0.15),
            in: f, detections: []
        )

        guard case let .box(rect, _) = try #require(indicator) else {
            Issue.record("expected .box"); return
        }
        #expect(abs(rect.minY - (0.6 + 0.30)) < 0.0001)
        #expect(rect.maxY >= 1.0)  // open upward, past the top of the frame
    }

    @Test("a ball offset with no ball detected still draws the target box")
    func ballOffsetWithoutDetectionStillDrawsBox() throws {
        let f = frame(["left_shoulder": (0.4, 0.6)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "ball_offset_y", joints: ["left_shoulder"],
                     comparison: "range", min: 0.28, max: 0.40, measured: 0.6),
            in: f, detections: [BackendDetection(
                label: "racket", confidence: 0.9,
                bbox: BackendBoundingBox(xMin: 0, yMin: 0, xMax: 0.1, yMax: 0.1)
            )]
        )

        guard case let .box(_, ballCentre) = try #require(indicator) else {
            Issue.record("expected .box"); return
        }
        #expect(ballCentre == nil)
    }

    // MARK: - Degradation

    @Test("an unrecognized metric yields no indicator rather than crashing")
    func unknownMetricYieldsNoIndicator() {
        let f = frame(["left_shoulder": (0.4, 0.6)])
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "future_metric_from_p15", joints: ["left_shoulder"], comparison: "gte", threshold: 1),
            in: f, detections: []
        )

        #expect(indicator == nil)
    }

    @Test("a cue with no deviation detail yields no indicator")
    func cueWithoutMetricYieldsNoIndicator() {
        let bare = Cue(ruleId: "r", phase: "contact", message: "m", severity: "major")

        #expect(CueOverlayGeometry.indicator(for: bare, in: frame(["left_shoulder": (0.4, 0.6)]), detections: []) == nil)
    }

    @Test("a cue whose joints are missing from the frame yields no indicator")
    func missingJointsYieldNoIndicator() {
        let indicator = CueOverlayGeometry.indicator(
            for: cue(metric: "angle_from_vertical", joints: ["left_shoulder", "left_wrist"], comparison: "lte", threshold: 45),
            in: frame([:]), detections: []
        )

        #expect(indicator == nil)
    }

    @Test("every metric in the backend rule set produces an indicator")
    func allBackendMetricsAreHandled() {
        // Mirrors the `metric` Literal set in backend/app/engine/rules.py.
        let f = frame([
            "left_shoulder": (0.4, 0.6), "left_elbow": (0.5, 0.7), "left_wrist": (0.7, 0.9),
            "right_shoulder": (0.6, 0.6), "nose": (0.4, 0.9),
        ])
        let specs: [(String, [String])] = [
            ("angle", ["left_shoulder", "left_elbow", "left_wrist"]),
            ("angle_from_vertical", ["left_shoulder", "left_wrist"]),
            ("y_diff", ["left_wrist", "nose"]),
            ("x_diff", ["right_shoulder", "left_shoulder"]),
            ("ball_offset_x", ["left_shoulder"]),
            ("ball_offset_y", ["left_shoulder"]),
        ]

        for (metric, joints) in specs {
            let indicator = CueOverlayGeometry.indicator(
                for: cue(metric: metric, joints: joints, comparison: "range", min: 0.1, max: 0.2, measured: 0.5),
                in: f, detections: [ball(x: 0.5, y: 1.0)]
            )
            #expect(indicator != nil, "metric \(metric) produced no indicator")
        }
    }
}
