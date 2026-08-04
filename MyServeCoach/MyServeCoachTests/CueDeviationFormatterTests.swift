import Testing
@testable import MyServeCoach

@Suite("CueDeviationFormatter Tests")
struct CueDeviationFormatterTests {

    private func cue(
        metric: String?,
        measured: Double?,
        comparison: String?,
        threshold: Double? = nil,
        min: Double? = nil,
        max: Double? = nil
    ) -> Cue {
        Cue(
            ruleId: "r", phase: "trophy_pose", message: "m", severity: "major",
            metric: metric, joints: [], measuredValue: measured, comparison: comparison,
            threshold: threshold, thresholdMin: min, thresholdMax: max
        )
    }

    @Test("an lte angle rule renders a ≤ target with degrees and no decimals")
    func formatsLteAngle() {
        let caption = CueDeviationFormatter.caption(for: cue(
            metric: "angle_from_vertical", measured: 62.4, comparison: "lte", threshold: 45
        ))

        #expect(caption == "measured 62° · target ≤45°")
    }

    @Test("a gte angle rule renders a ≥ target")
    func formatsGteAngle() {
        let caption = CueDeviationFormatter.caption(for: cue(
            metric: "angle", measured: 98.6, comparison: "gte", threshold: 155
        ))

        #expect(caption == "measured 99° · target ≥155°")
    }

    @Test("a range angle rule renders both bounds")
    func formatsRangeAngle() {
        let caption = CueDeviationFormatter.caption(for: cue(
            metric: "angle", measured: 135.2, comparison: "range", min: 155, max: 180
        ))

        #expect(caption == "measured 135° · target 155–180°")
    }

    @Test("a normalized-unit metric renders 2 decimals with no degree sign")
    func formatsNormalizedMetric() {
        let caption = CueDeviationFormatter.caption(for: cue(
            metric: "ball_offset_y", measured: 0.523, comparison: "range", min: 0.28, max: 0.40
        ))

        #expect(caption == "measured 0.52 · target 0.28–0.40")
    }

    @Test("a y_diff metric renders 2 decimals")
    func formatsYDiff() {
        let caption = CueDeviationFormatter.caption(for: cue(
            metric: "y_diff", measured: -0.135, comparison: "range", min: -0.04, max: 0.10
        ))

        #expect(caption == "measured -0.14 · target -0.04–0.10")
    }

    @Test("a cue with no measured value yields no caption")
    func nilMeasuredValueYieldsNoCaption() {
        #expect(CueDeviationFormatter.caption(for: cue(
            metric: "angle", measured: nil, comparison: "lte", threshold: 45
        )) == nil)
    }

    @Test("a cue with no comparison yields no caption")
    func nilComparisonYieldsNoCaption() {
        #expect(CueDeviationFormatter.caption(for: cue(
            metric: "angle", measured: 62, comparison: nil
        )) == nil)
    }

    @Test("a range comparison missing a bound yields no caption rather than a half target")
    func incompleteRangeYieldsNoCaption() {
        #expect(CueDeviationFormatter.caption(for: cue(
            metric: "angle", measured: 62, comparison: "range", min: 155, max: nil
        )) == nil)
    }

    @Test("a pre-P6c CueRecord formats identically to a live Cue")
    func formatsPersistedCueRecord() {
        let record = CueRecord(
            ruleId: "r", phase: "trophy_pose", message: "m", severity: "major",
            metric: "angle_from_vertical", joints: [], measuredValue: 62.4,
            comparison: "lte", threshold: 45
        )
        let bare = CueRecord(ruleId: "r", phase: "trophy_pose", message: "m", severity: "major")

        #expect(CueDeviationFormatter.caption(for: record) == "measured 62° · target ≤45°")
        #expect(CueDeviationFormatter.caption(for: bare) == nil)
    }
}
