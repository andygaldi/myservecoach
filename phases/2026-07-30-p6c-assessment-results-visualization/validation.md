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
| Persisted `CueRecord`s aggregate with the same semantics as the live path | `-only-testing:MyServeCoachTests/AssessmentHistoryDetailTests` — "aggregates persisted CueRecords across serves". |
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

_(filled in during `/phase`)_
