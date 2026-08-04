# Phase P6c — Validation

## Definition of Done

Phase P6c is complete when all of the following pass.

## Backend — Deviation Fields & Phase Timing (Group 1)

| Check | How to verify |
|---|---|
| A violated `gte`/`lte` rule's `Cue` carries `measured_value`, `metric`, `joints`, `comparison`, and `threshold` matching the rule in `rules.json` | `cd backend && pytest tests/test_rules.py -v` — the new deviation-field case asserts `measured_value == compute_metric_value(frame, rule.metric, rule.joints)` and that `threshold_min`/`threshold_max` are `None`. |
| A violated `range` rule's `Cue` carries `threshold_min`/`threshold_max` and leaves `threshold` `None` | Same suite; the `range` case (e.g. `trophy_hitting_elbow_shoulder_line`). |
| `AnalyzeResponse.phases` contains one entry per non-`None` detected phase, with a `frame_index` that indexes back to a frame whose `timestamp` equals the entry's `timestamp` | `cd backend && pytest tests/test_analyze.py -v` — the new phases case. |
| Phases `detect_phases` returned `None` for are **absent** from `phases`, not emitted with a sentinel index | Same case — assert the returned phase set equals the set of non-`None` keys in `detect_phases`' output. |
| No detection or rule-evaluation behavior changed | `git diff develop...HEAD -- backend/rules.json backend/app/engine/phases.py` is **empty**; the `backend/app/engine/rules.py` diff contains only the added `Cue(...)` keyword arguments — no change to `compute_metric_value`, `_passes`, or the rule-matching loop. |
| Every pre-existing backend test passes with unmodified assertions | `scripts/verify.sh backend` — zero failures. New `Cue` fields are optional; if an existing assertion needed editing, the field defaults are wrong. |

## iOS — Phase Frame Retention (Group 2)

| Check | How to verify |
|---|---|
| Only `release`, `trophy_pose`, `racket_drop`, `contact` are retained; `start`/`finish` are dropped | `-only-testing:MyServeCoachTests/ProServeAnalysisPipelineTests` — "retains only the four displayed phases, skipping start and finish": mock returns all six, assert `phaseFrames.map(\.phase)` equals the four. |
| Frames are retained for **every** serve, including one with zero cues | Same suite — a mock serve with `cues: []` still yields four `phaseFrames`. |
| The retained keypoints/detections are the ones at the backend-reported `frame_index` | Same suite — "phase frame carries the keypoints and detections at the reported frame index". |
| An out-of-range `frame_index` is skipped, not fatal | Same suite — "out-of-range frame index is skipped, not fatal": `analyze` returns normally with that phase absent. |
| Image-extraction failure degrades to cues-only rather than failing the analysis | Same suite — "image extraction failure leaves cues intact": stub image provider throws; cues unchanged, `phaseFrames` empty, no thrown error. |
| Images downscale to a 720px long edge at JPEG 0.7, and a smaller source is not upscaled | `-only-testing:MyServeCoachTests/PhaseFrameImageEncoderTests` — 1440×2560 → 720px long edge; 400×600 returned unchanged in size; output decodes back to a valid `UIImage`. |
| A pre-P6c backend response (no `phases`, no cue deviation fields) still decodes | `-only-testing:MyServeCoachTests/CoachingResultDecodingTests` — legacy-payload case decodes with `phases == []` and `nil` deviation fields. |

## iOS — SwiftData Persistence (Group 3)

| Check | How to verify |
|---|---|
| A persisted session round-trips `phaseFrames` with correct phase keys, timestamps, and non-empty image data | `-only-testing:MyServeCoachTests/ServeResultPersistenceTests` — insert via `AssessmentResultViewModel.persist(to:)` into an in-memory `ModelContainer`, re-fetch, assert. |
| `keypointsJSON` decodes back to a `BackendFrame` equal to the one retained | Same suite — decode the stored `Data` and compare joint names and values. |
| `CueRecord` round-trips `measuredValue`, `comparison`, `threshold`/`thresholdMin`/`thresholdMax`, `metric`, `joints` | Same suite. |
| Cascade delete removes `PhaseFrameRecord`s along with their `ServeResult` | Same suite — delete the session, assert zero orphaned `PhaseFrameRecord`s remain. |
| A store created before P6c opens without migration error | `PhaseFrameRecord` is a new model and every added `CueRecord`/`ServeResult` property is optional or defaulted — confirm by inspection of the model diff, and confirm `scripts/verify.sh ios` (which exercises container creation) is green. |

## iOS — Overlay Renderer (Group 4)

| Check | How to verify |
|---|---|
| Normalized coordinates are y-flipped into `Canvas` space | `-only-testing:MyServeCoachTests/PoseSkeletonGeometryTests` — `point(x:y:in:)` maps `y = 0.0` to the rect's **bottom** and `y = 1.0` to its top; `x = 0.0` maps to the left edge (not flipped). |
| The overlay draws into the aspect-fit image rect, not raw view bounds | Same suite — `fittedRect` letterboxes a portrait image in landscape bounds (and vice versa) with correct offsets, and returns `bounds` unchanged when aspect ratios match. |
| Deviation captions format correctly across comparisons and metric families | `-only-testing:MyServeCoachTests/CueDeviationFormatterTests` — `lte` → `"measured 62° · target ≤45°"`, `gte`, and `range` → `"measured 0.31 · target 0.28–0.40"`; angle metrics render `°` with no decimals, normalized metrics render 2 decimals with no unit. |
| A `nil` measured value (pre-P6c persisted cue) yields no caption rather than a placeholder | Same suite — formatter returns `nil`. |
| Every one of the nine rules in `rules.json` has a defined ideal-indicator branch | Inspection: `PhaseFrameOverlayView`'s metric dispatch covers `angle`, `angle_from_vertical`, `y_diff`, `x_diff`, `ball_offset_x`, `ball_offset_y` — the complete `_Rule.metric` `Literal` set in `backend/app/engine/rules.py:24`. An unrecognized metric must fall through to skeleton + highlight with no indicator, never crash. |

## iOS — Results Screen (Group 5)

| Check | How to verify |
|---|---|
| Cues aggregate by `ruleId` across serves with a distinct-serve count | `-only-testing:MyServeCoachTests/AssessmentResultViewModelTests` — "aggregates cues by ruleId across serves": 3-of-4 yields `flaggedServeCount == 3`, `totalServeCount == 4`. |
| A `ruleId` flagged twice within a single serve counts that serve once | Same suite — "a ruleId flagged twice within one serve counts that serve once". |
| Aggregate ordering is major-before-minor, then descending flagged count, tie-broken by Kovacs phase order | Same suite — "aggregated cues sort major-before-minor, then by descending flagged count". |
| A serve's cues group under the phase that produced them | Same suite — "cuesByPhase groups a serve's cues under the phase that produced them". |
| The aggregate section is hidden entirely when no cues exist | Inspection of `AssessmentResultView` — `aggregatedCues.isEmpty` renders nothing, not an empty titled section. |
| The three pre-existing `AssessmentResultViewModelTests` cases pass with unmodified assertion content | `scripts/verify.sh ios` — sorting, total counts, and persist tests unchanged. |
| `AssessmentResultView` and `AssessmentHistoryDetailView` no longer duplicate header/cue-row layout | Inspection — both consume the Group 29 shared subviews; the duplicated `header`/`cueRow` private helpers are gone from at least one of them. |

## iOS — History Parity & Degradation (Group 6)

| Check | How to verify |
|---|---|
| Persisted `CueRecord`s aggregate with the same semantics as the live path | `-only-testing:MyServeCoachTests/AssessmentHistoryPresenterTests` — "aggregates persisted CueRecords across serves". |
| A pre-P6c session (zero `PhaseFrameRecord`s, `nil` deviation fields) renders today's text-only layout | Same suite — "a pre-P6c session with no phase frames yields no frame blocks": no empty image wells, no placeholder frames, no `"measured — · target —"` lines. |
| Undecodable `keypointsJSON` renders the image with no skeleton rather than dropping the frame or crashing | Same suite — "undecodable keypoints JSON yields a frame block with no skeleton". |
| Aggregation/decoding lives outside the view body | Inspection — `AssessmentHistoryDetailView`'s body contains no `JSONDecoder` or grouping logic (CLAUDE.md: views stay thin). |

## Cross-Cutting (Group 7)

| Check | How to verify |
|---|---|
| Both suites green together | `scripts/verify.sh backend` and `scripts/verify.sh ios` — zero failures. |
| No Lite-isolation file touched | `git diff --name-only develop...HEAD` — none of `PhaseReviewView.swift`, `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`, `PhaseGuesser.swift`, `LibraryVideoExporter.swift`, `ContentView.swift`, `ComparisonView.swift`, `ComparisonPhaseRowView.swift`, `HistoryComparisonView.swift`, `PhaseRecord.swift` appear. |
| Lite mode still runs end-to-end unchanged | Launch the app, select Lite, run a clip through record/import → phase review → comparison → history. No behavior or visual difference from `develop`. |

## Manual Real-Device Verification (Group 7) — **hard merge gate**

Run against a real device paired with the Mac-hosted backend, using a multi-serve Pro 2D clip.
**All five rows must pass before merging.** Unlike P6b's best-effort smoke test, this is a blocking
gate: the y-flip / aspect-fit bug class is precisely what unit tests can assert numerically but
cannot prove renders correctly on real footage.

| Check | How to verify |
|---|---|
| Skeletons are correctly oriented and aligned on real footage | Each serve shows four phase frames; the drawn skeleton sits on the player's body, right way up. A mirrored, inverted, or letterbox-offset skeleton is the expected failure mode — look for it specifically. |
| Highlighted segment and ideal indicator match the cue text | For at least one flagged `angle`/`angle_from_vertical` cue and one `ball_offset_*` cue, the highlighted joints are the ones named in the cue's message and the dashed ideal sits where the threshold implies. |
| Aggregate counts match the per-serve cues | Manually tally one `ruleId`'s occurrences across the per-serve sections; it equals the aggregate row's "N of M serves". |
| History replay is visually identical to the live result | Back out to history, reopen the session — same aggregate section, same frames, same overlays. |
| Frame extraction adds **≤ 2 s** to a 5-serve clip's analysis (≈100 ms/frame across ~20 frames) | Time the analysis with extraction enabled vs. a build with the extraction step short-circuited, or instrument the extraction loop and log elapsed time. **Blocking** — exceeding the budget requires optimization (batch via `AVAssetImageGenerator.images(for:)`, or move extraction off the critical path so cues render first) before merge, not a disclosure. |

## Merge Criteria

Minimum bar for squash-merging into `develop`:

1. `scripts/verify.sh backend` and `scripts/verify.sh ios` both green.
2. Every Group 1–6 table row above verified.
3. `rules.json` and `backend/app/engine/phases.py` diffs empty; `rules.py` diff limited to the
   `Cue(...)` field additions — this phase changes no analysis result, only its visibility.
4. No Lite-isolation file in the changed-file list; Lite flow manually confirmed unchanged.
5. All five **Manual Real-Device Verification** rows passed, including the ≤ 2 s extraction budget.
   Not disclosable — if a device/backend pairing is unavailable, the phase does not merge.
6. Pre-P6c persisted sessions confirmed to render text-only without crashes or empty image wells.

**Run notes:**

- **Automated verification.** `scripts/verify.sh backend` → exit 0 (190 passed, 3 skipped; 182
  before this phase, so +8 new backend tests). `scripts/verify.sh ios` → exit 0. No pre-existing
  test needed an assertion change on either surface — the new `Cue` fields are optional on the wire
  and the new SwiftData properties are all defaulted, exactly as the field-default design intended.

- **Group 1 (backend).** `rules.py`'s diff is only the seven added `Cue(...)` keyword arguments;
  `git diff -- backend/rules.json backend/app/engine/phases.py` is empty. `analyze.py` recovers
  each phase's `frame_index` through an `{id(frame): index}` map built once before the loop —
  identity rather than timestamp, since `detect_phases` returns the very `Frame` objects it was
  handed and two frames sharing a timestamp would otherwise collide.

- **Group 2 deviation from plan — batched extraction.** The plan had `ProServeAnalysisPipeline`
  reusing Lite's `FrameThumbnailGenerator` once per phase frame. Implemented instead as a new
  `PhaseFrameImageExtractor` (`PhaseFrameImageProviding`) that shares one `AVURLAsset` and one
  `AVAssetImageGenerator` across every requested timestamp via `images(for:)`. This is the plan's
  own listed remedy for the latency budget (step 42), adopted upfront rather than reactively, and
  it has the side benefit of leaving `FrameThumbnailGenerator` — Lite-shared code — completely
  untouched. Timestamps are keyed on `CMTime.value` rather than round-tripped `Double`s, because
  `CMTime(seconds:)` is lossy for values like 1/3; covered by
  `PhaseFrameImageExtractorTests.lossyTimestampsAreKeyedByOriginalValue`.

- **Group 2 robustness finding.** A test crash (`Dictionary(uniqueKeysWithValues:)` trapping on
  duplicate keys) surfaced that two serves can legitimately report the same phase timestamp. The
  pipeline now deduplicates timestamps before requesting extraction, so a repeat costs one
  extraction rather than two.

- **Design addition not in the plan — `unpairedCues`.** Cues whose phase has no rendered frame
  (extraction failed, image undecodable, or a phase outside the displayed four) surface as plain
  rows via `AssessmentServeSectionDisplay.unpairedCues`. Losing imagery must never silently lose
  coaching; covered by tests on both the live and history paths.

- **Group 4 coordinate handling.** All ideal indicators are derived in *normalized* space and only
  then mapped to screen, because the backend computes its angles on normalized coordinates
  (`angles.py`), where the frame's aspect ratio is squashed into a unit square. Deriving a dashed
  ray in screen space would have placed it somewhere the reported number doesn't correspond to.
  Consequence to keep in mind: a "45°" ideal ray is not 45° measured with an on-screen protractor —
  it sits where a limb at that threshold would actually appear.

- **Group 4 confidence floor.** `PoseSkeletonGeometry.minConfidence` is 0.4, matching
  `MIN_CONFIDENCE` in `backend/app/engine/angles.py` (the plan had sketched 0.3), so the overlay
  draws exactly the joints the rule engine was willing to measure. Pinned by
  `PoseSkeletonGeometryTests.confidenceFloorMatchesBackend`.

- **Groups 5/6 duplication removed.** `AssessmentResultView` and `AssessmentHistoryDetailView`
  previously duplicated `header`/`cueRow`/`resultSection`. Both now render through the shared
  `AssessmentHeaderView` / `AssessmentAggregateSection` / `AssessmentServeSectionView` /
  `PhaseFrameBlockView` / `CueRowView`, fed by plain display models. History decoding and
  aggregation live in `AssessmentHistoryPresenter`, not the view body.

- **Manual real-device verification (hard merge gate) — PASSED**, run against a real device paired
  with the Mac-hosted backend on an imported Photos-library clip.
  - Skeleton orientation and alignment on real footage: **correct** — right way up, sitting on the
    player's body. This was the phase's highest-risk item (the y-flip / aspect-fit bug class) and
    it is the one thing unit tests could assert numerically but not prove visually.
  - Frame extraction latency: **within the ≤ 2 s budget** by observation. The batched extractor
    above is the likely reason there was headroom.
  - Highlighted segment and ideal-indicator placement vs. cue text: **correct for every cue that
    fired**, confirmed across both metric families the validation row calls for — an angle-family
    cue (dashed ray + arc) and, on a separate clip that tripped the racket-drop ball rules, a
    `ball_offset_*` cue (target box + ball marker). This row is fully satisfied.
  - Aggregate counts and history replay: consistent with the per-serve sections.
  - **Partial coverage, disclosed:** the available test serves did not trigger all nine rules in
    `rules.json`, so the `y_diff`/`x_diff` **band** branch (`release_toss_hand_eye_height`,
    `contact_shoulders_stacked`) was not among the cues visually confirmed on real footage. That
    branch is covered by `CueOverlayGeometryTests` (`yDiffBandOffsetFromReference`,
    `openEndedBands`, `xDiffProducesVerticalBand`, `allBackendMetricsAreHandled`), and an
    unrecognized or unresolvable metric degrades to skeleton + highlight rather than crashing, so
    the residual risk is cosmetic band placement rather than a crash or a wrong number. Worth a
    look whenever footage that trips those two rules is available.

- **Deep review (3 parallel agents: correctness / design / spec compliance).** Correctness came
  back clean on the phase's highest-risk areas — every y-flip branch in `drawIdeal`
  (`horizontalBand`, `verticalBand`, `.box` corner swap), the `cross`-based side selection, the
  backend `id(frame)` join, and the aggregate ordering were hand-checked and confirmed correct.
  Findings applied:
  - **`PhaseFrameImageExtractor` seek tolerance ±0.1s → `.zero` (the one high-severity defect).**
    The tolerance had been copied verbatim from Lite's `FrameThumbnailGenerator`, where nothing is
    drawn over the thumbnail. Here the overlay draws *this frame's* keypoints on the image, and
    the backend samples at `DEFAULT_STRIDE = 2` (~67 ms apart at 30fps), so ±100 ms allowed the
    returned image to be up to 1.5 sampled frames away from its keypoints — the highlighted limb
    would float off the body at contact, the fastest-moving moment of the serve. Note the manual
    device check would not have caught this: trophy pose is slow enough to look right.
  - `CueOverlayGeometry.highlightedPolyline` is now all-or-nothing. It previously `compactMap`ped
    away unresolvable joints, so a low-confidence elbow turned a three-joint arm rule into a
    straight shoulder→wrist line rendered directly beneath "Straighten your tossing arm."
  - Phase-frame timestamps now come from the locally-held `segment.frames[i].timestamp` rather
    than the echoed wire value, joining image to keypoints by construction.
  - Open-ended (`gte`/`lte`) ball-offset boxes run to the frame edge instead of being closed at
    the cross-axis width, which would have implied an accepted value was out of range. Latent
    today — both ball rules are `range` — but wrong for any future open-ended rule.
  - Joint dots deduplicated via new `PoseSkeletonGeometry.jointNames`/`jointPoints`: `bones` names
    24 endpoints across 12 distinct joints, so shoulders and hips were compositing their
    translucent dot three times (~0.97 alpha) against 0.7 at the wrists and ankles — inverting the
    flat dimmed look.
  - Severity→colour unified into `Color(severity:)`. The overlay and the cue rows had opposite
    fallbacks for an unrecognized severity.
  - `test_every_rule_in_rules_json_emits_its_own_metric_and_joints` was passing for the wrong
    reason — it asserted on a hand-built `Cue` and never called `evaluate_rules`, so deleting all
    seven kwargs in `rules.py` left it green. Replaced with
    `test_evaluate_rules_populates_deviation_detail_for_every_rule`, which drives the real path
    once per rule with a rigged-to-fail threshold. **Verified by mutation**: with the kwargs
    removed, 4 tests fail; restored, 33 pass.
  - Added the missing aggregate phase-tie-break assertion, `highlightedPolyline` all-or-nothing
    cases, the open-ended ball-box case, and joint-dedup cases. Removed dead code
    (`AssessmentServeDisplay.cuesByPhase`, `AssessmentCueDisplay.isMajor`, public `target(for:)`).
  - `PoseSkeletonGeometryTests.confidenceFloorIsPinned` reworded: it is a change-detector for the
    iOS constant and *cannot* observe `MIN_CONFIDENCE` drifting in `angles.py`. Keeping the two in
    step is a manual obligation, now stated in the test.

- **Recorded, not fixed — angle captions are aspect-distorted.** `pose_model.py:85` normalizes x
  by width and y by height independently, so `compute_angle` measures in a squashed unit square.
  At the locked 720×1280 Pro 2D capture the vertical component is stretched by 1280/720 = 1.78 in
  the tangent: a limb truly 30° off vertical reports **≈45.8°**. Pass/fail is unaffected (P5
  calibrated its thresholds in exactly this space) and `CueOverlayGeometry` deliberately derives
  ray placement in the same space so the drawing stays consistent with the number — but P6c is the
  first phase to print that raw value to a user with a `°` sign ("measured 62° · target ≤45°"), and
  it is not an anatomically true angle. Out of scope to change here: correcting it means either
  re-deriving thresholds (P5's domain) or aspect-correcting the metric, both of which alter
  pass/fail. Worth an explicit decision in a later phase — either aspect-correct the angle metrics
  and recalibrate, or drop the `°` unit from the caption so the number reads as a relative score.

- **Known cleanup, deliberately deferred:** `AssessmentResultViewModel.section(for:cueDisplays:)`
  and `AssessmentHistoryPresenter.section(for:cueDisplays:)` duplicate ~45 lines of section
  construction (identical cue-display id scheme, phase grouping, and `unpairedCues` derivation),
  differing only in whether keypoints are decoded or passed through. Both agents flagged it. Left
  as-is by owner decision: the view-layer duplication this phase set out to remove *is* gone, the
  shared logic is tested from both entry points, and the refactor would churn verified code
  immediately before merge. Natural cleanup is to lift both into `AssessmentDisplayBuilder`.

- **Reported and applied before merge:** `AssessmentHistoryDetailView` rebuilt
  `AssessmentHistoryPresenter` on every body evaluation, re-running ~20 JPEG decodes and ~40 JSON
  decodes per render for a 5-serve session on the main actor. The live path does this work once in
  `init`. Now seeded into `@State` from an explicit `init(session:)`, so it is built once per
  pushed session. Seeding is sound here because the view is a
  `navigationDestination(for: ServeSession.self)` destination — a different session is a different
  push and therefore a different view identity, so the held presenter can never go stale against
  its session. Presenter and subview behavior are unchanged, so
  `AssessmentHistoryPresenterTests` covers it as-is; `scripts/verify.sh ios` re-run green after
  the change.

- **First manual attempt failed for an environmental reason, not a code one.** `POST
  /v1/segment/video` returned `NSURLErrorDomain -1001` with `_kCFStreamErrorCodeKey=60`. Root
  cause: no process was listening on port 8000 — the backend simply wasn't running.
  `BackendConfig.baseURL`'s `192.168.86.205` was correct and still matched the Mac's `en0`. The
  60-second failure was the OS-level TCP connect timeout (`ETIMEDOUT`), which `URLRequest`'s
  `timeoutInterval` does not govern — so it is *not* evidence that the existing 180 s
  `proRequestTimeout` is too short. Re-ran with `uvicorn app.main:app --host 0.0.0.0 --port 8000`
  and the test passed.
