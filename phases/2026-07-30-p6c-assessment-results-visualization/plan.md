# Phase P6c — Plan

> **Lite-isolation note:** every file touched below is on the Pro 2D route introduced in P6. No
> group modifies `PhaseReviewView`, `PoseAnalysisPipeline`, `PoseEstimationService`,
> `ServeSegmentationService`, `PhaseGuesser`, `LibraryVideoExporter`, `ContentView`,
> `ComparisonView`, `HistoryComparisonView`, or Lite's `PhaseRecord`.

> **Coordinate convention (applies to Groups 4–6):** backend keypoints and detection boxes are
> normalized 0–1 with **Vision's** convention — origin bottom-left, y increasing *upward*
> (`backend/app/services/pose_model.py:85`, `object_detection.py:37-47`). SwiftUI `Canvas` is
> origin top-left, y increasing *downward*. Every draw path must y-flip (`1 - y`) and then map into
> the aspect-fit image rect, not the raw view bounds. Getting this wrong renders skeletons upside
> down or offset — assert it in tests, don't eyeball it.

## Group 1 — Backend: Deviation Fields & Phase Timing (surface: `backend`)

1. In `backend/app/models.py`, extend `Cue` with the deviation fields (all optional so any
   non-`evaluate_rules` construction site and existing tests keep working):
   ```python
   class Cue(BaseModel):
       rule_id: str
       phase: ServePhase
       message: str
       severity: Severity
       metric: str | None = None
       joints: list[str] = Field(default_factory=list)
       measured_value: float | None = None
       comparison: str | None = None
       threshold: float | None = None
       threshold_min: float | None = None
       threshold_max: float | None = None
   ```
2. In `backend/app/models.py`, add `PhaseDetection` and extend `AnalyzeResponse`:
   ```python
   class PhaseDetection(BaseModel):
       phase: ServePhase
       frame_index: int
       timestamp: float

   class AnalyzeResponse(BaseModel):
       cues: list[Cue] = Field(default_factory=list)
       summary: str | None = None
       phases: list[PhaseDetection] = Field(default_factory=list)
   ```
3. In `backend/app/engine/rules.py`, populate the new fields in `evaluate_rules`'s `Cue(...)`
   construction (`rules.py:127-132`) from the already-in-hand `value` and `rule`:
   `metric=rule.metric, joints=rule.joints, measured_value=value, comparison=rule.comparison,
   threshold=rule.threshold, threshold_min=rule.threshold_min, threshold_max=rule.threshold_max`.
   **No other change to this file** — `compute_metric_value`, `_passes`, and the rule-matching loop
   are untouched.
4. In `backend/app/routers/analyze.py`, build the `phases` list after `detect_phases` returns.
   Recover each phase frame's index by identity/timestamp against `request.frames` — build one
   `{id(frame): index}` or `{timestamp: index}` lookup before the loop rather than doing a linear
   `.index()` scan per phase. Emit a `PhaseDetection` for every phase whose frame is not `None`, in
   `ServePhase` declaration order (start → finish). Return it on the `AnalyzeResponse`. The
   existing `trophy_detected`/`summary` logic is unchanged.
5. In `backend/tests/`, extend the analyze/rules tests:
   - `test_rules.py` (or wherever `evaluate_rules` is covered): assert a violated rule's returned
     `Cue` carries `measured_value` equal to `compute_metric_value` for that frame/metric/joints,
     and that `metric`, `joints`, `comparison`, and the relevant threshold field(s) match the
     matched rule in `rules.json`. Cover one `gte`/`lte` rule (only `threshold` set) and one
     `range` rule (only `threshold_min`/`threshold_max` set).
   - `test_analyze.py` (or the router's test file): assert `response.phases` contains one entry per
     non-`None` detected phase, that each `frame_index` indexes back to a frame whose `timestamp`
     equals the entry's `timestamp`, and that phases `detect_phases` returned `None` for are absent
     (not emitted with a sentinel index).
6. Run `scripts/verify.sh backend` — confirm green, including every pre-existing test (the new
   `Cue` fields are optional, so no existing assertion should need editing; if one does, that is a
   signal the field defaults are wrong).

## Group 2 — iOS: Retain Phase Frames, Keypoints, Detections & Images (surface: `ios`)

7. In `App/Services/Coaching/CoachingService.swift`, extend the DTOs to match Group 1's wire
   format:
   - `Cue` gains `metric: String?`, `joints: [String]`, `measuredValue: Double?`,
     `comparison: String?`, `threshold: Double?`, `thresholdMin: Double?`, `thresholdMax: Double?`,
     with `CodingKeys` mapping `measured_value`/`threshold_min`/`threshold_max`. Decode `joints`
     with a defaulting fallback so a pre-P6c backend response still decodes.
   - New `PhaseDetection: Codable, Sendable { let phase: String; let frameIndex: Int; let
     timestamp: Double }` with `CodingKeys` for `frame_index`.
   - `CoachingResult` gains `let phases: [PhaseDetection]`, defaulted to `[]` on decode.
8. Create `App/Models/AssessmentPhaseFrame.swift`:
   ```swift
   import Foundation

   /// One retained phase frame for a Pro 2D serve: the image extracted at the backend-reported
   /// timestamp, plus the keypoints and detections the overlay renderer draws from.
   struct AssessmentPhaseFrame: Sendable {
       let phase: String          // "release" | "trophy_pose" | "racket_drop" | "contact"
       let timestamp: Double
       let imageData: Data        // JPEG, downscaled per PhaseFrameImageEncoder
       let frame: BackendFrame
       let detections: [BackendDetection]
   }

   enum AssessmentPhaseConstants {
       /// The four coaching-relevant phases displayed on the results screen. `start` and `finish`
       /// are detected by the backend but have no rules targeting them and are not extracted.
       static let displayedPhases = ["release", "trophy_pose", "racket_drop", "contact"]
   }
   ```
9. Create `App/Services/Video/PhaseFrameImageEncoder.swift` — a small helper that downscales a
   `UIImage` to a 720px long edge (preserving aspect ratio; never upscales a smaller source) and
   returns `jpegData(compressionQuality: 0.7)`. Expose the constants as
   `static let maxLongEdge: CGFloat = 720` and `static let jpegQuality: CGFloat = 0.7` so tests can
   assert against them rather than hardcoded literals.
10. In `App/Services/Pose/ProServeAnalysisPipeline.swift`:
    - Extend `AssessmentServeResult` with `let phaseFrames: [AssessmentPhaseFrame]`.
    - Inject `thumbnailGenerator: FrameThumbnailGenerator = FrameThumbnailGenerator()` via `init`
      alongside the existing dependencies (so tests can exercise the loop without a real asset —
      if `FrameThumbnailGenerator` isn't protocol-backed, introduce a
      `protocol PhaseFrameImageProviding: Sendable { func thumbnail(at: CMTime, for: AVAsset) async throws -> UIImage }`
      conformance rather than making the type itself testable-by-subclassing).
    - In `analyze(videoURL:)`, after each segment's `coachingService.analyze(...)` returns, build
      that serve's `phaseFrames`: for each entry in `coaching.phases` whose `phase` is in
      `AssessmentPhaseConstants.displayedPhases`, look up `segment.frames[frameIndex]` (guard the
      index against `segment.frames.count`; skip the phase if out of range rather than crashing),
      take `segment.detections?[frameIndex] ?? []`, extract the image at
      `CMTime(seconds: timestamp, preferredTimescale: 600)` from a single `AVURLAsset` created once
      outside the segment loop, encode via `PhaseFrameImageEncoder`, and append.
    - **Image-extraction failure must not fail the analysis.** If `thumbnail(at:for:)` throws for a
      given phase, skip that phase frame and continue — the cue text is still valuable without
      imagery. Log the failure via `print("[ProServeAnalysis] frame extraction failed: \(error)")`,
      matching the existing logging style in `VideoSourceSelectionViewModel`.
11. Update `MyServeCoachTests/ProServeAnalysisPipelineTests.swift` (Swift Testing `@Suite`/`@Test`
    style, matching the file's existing structure):
    - Extend `MockCoachingService` to return a configurable `phases:` list.
    - `@Test("retains only the four displayed phases, skipping start and finish")` — mock returns
      all six phases; assert `phaseFrames.map(\.phase)` contains exactly release/trophy_pose/
      racket_drop/contact.
    - `@Test("phase frame carries the keypoints and detections at the reported frame index")` —
      assert the retained `frame`/`detections` match the segment's entries at that index.
    - `@Test("out-of-range frame index is skipped, not fatal")` — mock returns a `frameIndex` past
      the segment's frame count; assert `analyze` returns normally with that phase absent.
    - `@Test("image extraction failure leaves cues intact")` — stub image provider throws; assert
      the serve's cues are unchanged and `phaseFrames` is empty.
    Use `MyServeCoachTests/Support/TestVideoFixture.swift`'s existing fixture-video helper for any
    case that needs a real asset.
12. Add `MyServeCoachTests/PhaseFrameImageEncoderTests.swift`: assert a 1440×2560 source downscales
    to a 720px long edge, that a 400×600 source is returned un-upscaled, and that the output decodes
    back to a valid `UIImage`.
13. Run `scripts/verify.sh ios` — confirm green.

## Group 3 — iOS: SwiftData Persistence (surface: `ios`)

14. Create `App/Models/SwiftData/PhaseFrameRecord.swift`, mirroring Lite's `PhaseRecord` shape and
    the existing Pro models' "every stored property has a default" style:
    ```swift
    @Model
    final class PhaseFrameRecord {
        var id: UUID = UUID()
        var phaseKey: String = ""
        var frameTimestamp: Double = 0
        var frameImageData: Data = Data()
        /// JSON-encoded `BackendFrame` — the keypoints the overlay renderer draws from. Stored
        /// encoded rather than as a SwiftData relationship because it is opaque display payload,
        /// never queried or sorted on.
        var keypointsJSON: Data = Data()
        /// JSON-encoded `[BackendDetection]` at the same frame (ball/racket boxes).
        var detectionsJSON: Data = Data()
        var result: ServeResult?

        init(phaseKey: String, frameTimestamp: Double, frameImageData: Data, keypointsJSON: Data, detectionsJSON: Data) { ... }
    }
    ```
15. In `App/Models/SwiftData/ServeResult.swift`, add
    `@Relationship(deleteRule: .cascade) var phaseFrames: [PhaseFrameRecord] = []`.
16. In `App/Models/SwiftData/CueRecord.swift`, add the deviation fields as optionals/defaults so
    pre-P6c stores open unchanged: `var metric: String?`, `var joints: [String] = []`,
    `var measuredValue: Double?`, `var comparison: String?`, `var threshold: Double?`,
    `var thresholdMin: Double?`, `var thresholdMax: Double?`. Extend `init` with defaulted
    parameters so existing call sites compile untouched.
17. Confirm the `ModelContainer` schema registration (`App/MyServeCoachApp.swift`) includes
    `PhaseFrameRecord` — add it if the schema lists model types explicitly.
18. In `App/ViewModels/AssessmentResultViewModel.swift`, extend `persist(to:)` to write the new
    data: map each `AssessmentPhaseFrame` to a `PhaseFrameRecord` (JSON-encoding `frame` and
    `detections` with a single shared `JSONEncoder`), and pass the cue deviation fields through to
    `CueRecord`.
19. Extend `MyServeCoachTests/ServeResultPersistenceTests.swift` (or
    `AssessmentResultViewModelTests.swift`'s persist test, matching where the existing coverage
    lives): assert a persisted session round-trips `phaseFrames` with correct phase keys,
    timestamps, non-empty image data, and `keypointsJSON` that decodes back to an equal
    `BackendFrame`; assert `CueRecord` round-trips `measuredValue`/`comparison`/thresholds; assert
    cascade delete removes `PhaseFrameRecord`s with their `ServeResult`.
20. Run `scripts/verify.sh ios` — confirm green.

## Group 4 — iOS: Pose Skeleton & Deviation Overlay Renderer (surface: `ios`)

21. Create `App/Views/Overlay/PoseSkeletonGeometry.swift` — pure, view-free geometry so it is unit
    testable without rendering:
    ```swift
    enum PoseSkeletonGeometry {
        /// COCO-17-derived bone pairs shared by the RTMPose backend output and the Vision-mapped
        /// joint names (see backend/app/services/pose_model.py COCO17_KEYPOINT_NAMES and
        /// App/Services/Pose/VisionJointMapper.swift).
        static let bones: [(String, String)] = [
            ("left_shoulder", "right_shoulder"), ("left_shoulder", "left_elbow"),
            ("left_elbow", "left_wrist"), ("right_shoulder", "right_elbow"),
            ("right_elbow", "right_wrist"), ("left_shoulder", "left_hip"),
            ("right_shoulder", "right_hip"), ("left_hip", "right_hip"),
            ("left_hip", "left_knee"), ("left_knee", "left_ankle"),
            ("right_hip", "right_knee"), ("right_knee", "right_ankle"),
        ]

        static let minConfidence: Float = 0.3

        /// Maps a normalized Vision-convention point (origin bottom-left, y up) into a
        /// `Canvas` point inside `rect` (origin top-left, y down).
        static func point(x: Float, y: Float, in rect: CGRect) -> CGPoint

        /// The aspect-fit rect an image of `imageSize` occupies inside `bounds` — the overlay
        /// must draw into this, not into `bounds`, or the skeleton will be offset by the
        /// letterbox bars.
        static func fittedRect(imageSize: CGSize, in bounds: CGRect) -> CGRect
    }
    ```
22. Create `App/Views/Overlay/PhaseFrameOverlayView.swift` — the `Canvas` renderer:
    ```swift
    struct PhaseFrameOverlayView: View {
        let image: UIImage
        let frame: BackendFrame
        let detections: [BackendDetection]
        let highlightedCue: Cue?   // nil → skeleton only, no highlight or ideal indicator
        ...
    }
    ```
    Draw order, inside the `fittedRect`:
    1. The image (`.resizable().scaledToFit()` behind the `Canvas`, or drawn as a `Canvas` symbol —
       either is fine as long as the overlay's rect matches the image's drawn rect exactly).
    2. Dimmed skeleton — every bone in `PoseSkeletonGeometry.bones` whose both endpoints exceed
       `minConfidence`, stroked at ~30% opacity white with a thin dark outline for contrast against
       light court surfaces; joint dots at the same opacity.
    3. Highlighted measured segment — the joints named by `highlightedCue.joints`, stroked in the
       severity color (`.red` for major, `.orange` for minor) at full opacity and heavier width.
    4. The ideal indicator, dispatched on `highlightedCue.metric`:
       - `angle` — dashed ray from `joints[1]` (the vertex) at the threshold angle from the
         `joints[0]` arm, plus an arc annotating the measured angle. For `range`, draw both bounds.
       - `angle_from_vertical` — dashed vertical ray from `joints[0]`, plus a dashed ray at the
         threshold angle off vertical; arc between vertical and the measured segment.
       - `y_diff` / `x_diff` — a shaded target band offset from `joints[1]` (the reference joint)
         spanning the threshold range (for `gte`/`lte`, a half-open band from the single threshold),
         plus a marker at `joints[0]`'s actual position.
       - `ball_offset_x` / `ball_offset_y` — a target box around `joints[0]` spanning the threshold
         range on the relevant axis, plus a circle marker at the `label == "ball"` detection's bbox
         center from `detections`. If no ball detection is present, draw the box only.
    5. A compact "measured 62° · target ≤45°" caption is **not** drawn in the canvas — it is a
       `Text` row rendered below the image by the calling view (Groups 5/6), so it stays legible
       and accessible.
23. Create `App/Views/Overlay/CueDeviationFormatter.swift` — formats a cue's measured value and
    target into display strings (`"measured 62° · target ≤45°"`, `"measured 0.31 · target 0.28–0.40"`).
    Angle-family metrics (`angle`, `angle_from_vertical`) render with a `°` suffix and no decimals;
    the normalized-unit metrics (`y_diff`, `x_diff`, `ball_offset_*`) render to 2 decimals with no
    unit. Returns `nil` when `measuredValue` is `nil` (pre-P6c persisted cues).
24. Add `MyServeCoachTests/PoseSkeletonGeometryTests.swift`:
    - `point(x:y:in:)` y-flips: a normalized `y = 0.0` maps to the **bottom** of the rect and
      `y = 1.0` to the top; `x` is not flipped.
    - `fittedRect` letterboxes correctly for a portrait image in a landscape bounds and vice versa,
      and returns `bounds` when aspect ratios match.
25. Add `MyServeCoachTests/CueDeviationFormatterTests.swift`: `lte`, `gte`, and `range` comparisons
    across an angle metric and a normalized metric; `nil` measured value returns `nil`.
26. Run `scripts/verify.sh ios` — confirm green.

## Group 5 — iOS: Aggregate & Per-Serve Results Screen (surface: `ios`)

27. In `App/ViewModels/AssessmentResultViewModel.swift`:
    - Add `struct AggregatedCue: Identifiable { let id: String /* ruleId */; let message: String;
      let phase: String; let severity: String; let flaggedServeCount: Int; let totalServeCount: Int }`.
    - Add `var aggregatedCues: [AggregatedCue]`, computed once in `init`: group every serve's cues
      by `ruleId`, count distinct serves flagged, and sort major-before-minor then by descending
      `flaggedServeCount`, tie-broken by `CueOrderingConstants.kovacsPhaseOrder` — reuse the
      existing constant rather than redeclaring phase order.
    - Extend `AssessmentServeDisplay` with `let phaseFrames: [AssessmentPhaseFrame]` and a
      `cuesByPhase: [String: [Cue]]` grouping so the view can render each retained phase frame with
      the cues that phase produced.
28. In `App/Views/AssessmentResultView.swift`:
    - Add an aggregate section between `header` and the per-serve sections, titled
      `"Most frequent"`, hidden entirely when `aggregatedCues` is empty. Each row: severity dot,
      `cue.message`, and a secondary line `"\(flaggedServeCount) of \(totalServeCount) serves · \(phaseLabel)"`.
    - Rework `serveSection(_:)` to render, per retained phase frame in
      `AssessmentPhaseConstants.displayedPhases` order: a human phase label ("Release", "Trophy
      pose", "Racket drop", "Contact"), the `PhaseFrameOverlayView` for that frame (highlighting the
      phase's first/most-severe cue), and beneath it the phase's cue rows — each with the existing
      severity dot + message plus a new secondary `CueDeviationFormatter` line.
    - A phase with no cues still renders its image with `highlightedCue: nil` (skeleton only).
    - A serve with no cues at all keeps today's green checkmark summary row, now above its frames.
    - Extract the phase-key → display-label mapping into a single shared place (alongside
      `AssessmentPhaseConstants`) so Group 6 reuses it rather than duplicating the strings.
29. Extract the aggregate section, the phase-frame block, and the cue row into small shared subviews
    (e.g. `App/Views/Assessment/AggregateCueSection.swift`,
    `App/Views/Assessment/PhaseFrameBlockView.swift`, `App/Views/Assessment/CueRowView.swift`)
    parameterized over plain display values — **not** over `Cue` or `CueRecord` — so Group 6's
    history view feeds the same components from SwiftData records without duplicating layout.
    `AssessmentResultView` and `AssessmentHistoryDetailView` today duplicate `header`/`cueRow`; this
    phase should end with that duplication removed, not doubled.
30. Extend `MyServeCoachTests/AssessmentResultViewModelTests.swift`:
    - `@Test("aggregates cues by ruleId across serves with a distinct-serve count")` — same ruleId
      flagged in 3 of 4 serves yields one `AggregatedCue` with `flaggedServeCount == 3`,
      `totalServeCount == 4`.
    - `@Test("a ruleId flagged twice within one serve counts that serve once")` — guards the
      distinct-serve semantics.
    - `@Test("aggregated cues sort major-before-minor, then by descending flagged count")`.
    - `@Test("cuesByPhase groups a serve's cues under the phase that produced them")`.
    - Confirm the three pre-existing tests still pass with unmodified assertion content.
31. Run `scripts/verify.sh ios` — confirm green.

## Group 6 — iOS: History Parity & Graceful Degradation (surface: `ios`)

32. In `App/Views/AssessmentHistoryDetailView.swift`, replace its local `header`/`resultSection`/
    `cueRow` with the Group 29 shared subviews, fed from SwiftData: decode each
    `PhaseFrameRecord.keypointsJSON`/`detectionsJSON` back into `BackendFrame`/`[BackendDetection]`
    and its `frameImageData` into a `UIImage`, and compute the same aggregate grouping over
    `session.results.flatMap(\.cues)`.
33. Put the aggregation and decoding in a small view-model or pure helper rather than inline in the
    view body (CLAUDE.md: views stay thin), so it is unit-testable and so a decode failure is
    handled in one place.
34. **Graceful degradation, explicitly tested.** A session persisted before P6c has zero
    `PhaseFrameRecord`s and `nil` cue deviation fields. That case must render exactly today's
    text-only layout: no empty image wells, no placeholder frames, no "measured — · target —"
    lines. Likewise a `PhaseFrameRecord` whose `keypointsJSON` fails to decode renders the image
    with no skeleton rather than dropping the frame or crashing.
35. Add `MyServeCoachTests/AssessmentHistoryDetailTests.swift` (or extend the persistence suite)
    covering the helper from step 33:
    - `@Test("aggregates persisted CueRecords across serves")` — same grouping semantics as Group 5.
    - `@Test("a pre-P6c session with no phase frames yields no frame blocks")`.
    - `@Test("undecodable keypoints JSON yields a frame block with no skeleton")`.
36. Run `scripts/verify.sh ios` — confirm green.

## Group 7 — Cross-Cutting Verification (surface: `both`)

37. Run `scripts/verify.sh backend` and `scripts/verify.sh ios` — both green.
38. Run `git diff --name-only develop...HEAD` and confirm none of `PhaseReviewView.swift`,
    `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`,
    `PhaseGuesser.swift`, `LibraryVideoExporter.swift`, `ContentView.swift`, `ComparisonView.swift`,
    `ComparisonPhaseRowView.swift`, `HistoryComparisonView.swift`, or `PhaseRecord.swift` appear.
39. Confirm `rules.json`, `backend/app/engine/phases.py`, and `evaluate_rules`' pass/fail logic are
    unchanged — `git diff develop...HEAD -- backend/rules.json backend/app/engine/phases.py` must be
    empty, and the `rules.py` diff must contain only the `Cue(...)` field additions.
40. Confirm backward compatibility of the wire format: a `CoachingResult` decoded from a pre-P6c
    JSON payload (no `phases`, no cue deviation fields) still decodes successfully — add or confirm
    a case in `MyServeCoachTests/CoachingResultDecodingTests.swift`.
41. **Manual verification on a real device** against the Mac-hosted backend — **hard merge gate**,
    unlike P6b's best-effort smoke test. Record or import a multi-serve Pro 2D clip and confirm:
    (a) each serve shows four phase frames with correctly oriented, correctly aligned skeletons —
    verify the y-flip and aspect-fit visually; a mirrored, inverted, or letterbox-offset skeleton is
    the expected failure mode here; (b) a flagged phase's highlighted segment and ideal indicator
    match the cue text, checked for at least one angle-family cue and one `ball_offset_*` cue;
    (c) the aggregate section's counts match a hand tally of the per-serve cues; (d) backing out and
    reopening the session from history renders identically; (e) frame extraction adds **≤ 2 s** to a
    5-serve clip's analysis (~20 frames, ≈100 ms/frame) — time it against a build with the
    extraction step short-circuited, or instrument the loop and log elapsed time.
42. If the step-41(e) budget is exceeded, optimize before merging — batch the extractions via
    `AVAssetImageGenerator.images(for:)` instead of one `await` per frame, or move extraction off
    the critical path so cues render first and frames populate after. Exceeding the budget is a
    blocker, not a disclosable gap.
43. Record all step-41 outcomes in `validation.md` run notes. If a real device/backend pairing is
    unavailable at implementation time, **the phase does not merge** — stop and tell the user rather
    than recording it as a known gap.
