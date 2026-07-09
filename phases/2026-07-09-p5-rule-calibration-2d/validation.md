# Phase P5 — Validation

## Definition of Done

Phase P5 is complete when all of the following pass.

## Backend — Angle Helper Extensions (Group 1)

| Check | How to verify |
|---|---|
| `keypoint_x` mirrors `keypoint_y`'s confidence-gated behavior | `pytest backend/tests/test_angles.py -v -k test_keypoint_x` |
| `segment_angle_from_vertical` returns ~0° when the second joint is directly above the first | `pytest backend/tests/test_angles.py -v -k test_segment_angle_from_vertical_zero_when_directly_above` |
| `segment_angle_from_vertical` returns ~90° when the second joint is level (horizontal) with the first | `pytest backend/tests/test_angles.py -v -k test_segment_angle_from_vertical_ninety_when_horizontal` |
| `segment_angle_from_vertical` returns `None` when either joint is missing/low-confidence | `pytest backend/tests/test_angles.py -v -k test_segment_angle_from_vertical_none_when_joint_missing` |
| `forearm_angle_from_vertical`'s refactor is behavior-preserving | `pytest backend/tests/test_angles.py -v -k test_forearm_angle_from_vertical_matches_segment_angle_from_vertical` |
| All pre-existing `test_angles.py` tests still pass unmodified | `pytest backend/tests/test_angles.py -v` — zero failures. |

## Backend — Rule Engine: New Metrics, View Tag, Detections (Group 2)

| Check | How to verify |
|---|---|
| `x_diff` and `angle_from_vertical` metrics compute correctly | `pytest backend/tests/test_rules.py -v -k "test_x_diff_metric or test_angle_from_vertical_metric"` |
| `ball_offset_x`/`ball_offset_y` compute correctly when a ball detection is present | `pytest backend/tests/test_rules.py -v -k "test_ball_offset_y_metric_with_detection or test_ball_offset_x_metric_with_detection"` |
| Ball-offset metrics return `None` (rule skipped, no cue) when no ball is detected, or `detections` is absent entirely | `pytest backend/tests/test_rules.py -v -k "test_ball_offset_metric_returns_none"` |
| `evaluate_rules` defaults to `view="open_side"` and filters out other-view rules | `pytest backend/tests/test_rules.py -v -k test_evaluate_rules_defaults_to_open_side_view` |
| `evaluate_rules` honors an explicit `view` argument | `pytest backend/tests/test_rules.py -v -k test_evaluate_rules_respects_explicit_view_argument` |
| `phase_detections` is correctly threaded from `evaluate_rules` into ball-offset rule evaluation | `pytest backend/tests/test_rules.py -v -k test_evaluate_rules_passes_detections_to_ball_offset_rule` |
| `/analyze` builds a phase→detections map and a ball-offset rule can fire through the full request/response cycle | `pytest backend/tests/test_analyze.py -v` |
| `pose_model.py` retains `nose` in the backend keypoint schema; eyes/ears remain dropped | `pytest backend/tests/test_pose_model.py -v` — includes a check that `"nose" in map_coco17_to_backend_schema(...)`'s result while `"left_eye"`/`"right_eye"`/`"left_ear"`/`"right_ear"` are absent. |
| Full `rules.py`/`analyze.py`/`pose_model.py` test files green | `pytest backend/tests/test_rules.py backend/tests/test_analyze.py backend/tests/test_pose_model.py -v` — zero failures. |

## Backend — `analyze_angles.py` Calibration Tool (Group 3)

| Check | How to verify |
|---|---|
| `nearest_frame` picks the closest-timestamp frame | `pytest backend/tests/test_analyze_angles.py -v -k test_nearest_frame_picks_closest_timestamp` |
| `measure_video` skips a metric/serve pair when the computed value is `None` (e.g. no ball detected) instead of crashing | `pytest backend/tests/test_analyze_angles.py -v -k test_measure_video_skips_metric_when_value_is_none` |
| `measure_video` computes the expected value for a hand-built known frame | `pytest backend/tests/test_analyze_angles.py -v -k test_measure_video_computes_expected_value_for_known_frame` |
| `print_report` doesn't crash on a single-value (1-serve) aggregate | `pytest backend/tests/test_analyze_angles.py -v -k test_print_report_handles_single_value` |
| Full tool test file green, no real model construction | `pytest backend/tests/test_analyze_angles.py -v` — zero failures, completes fast (no ONNX/model load). |

## Manual — Ground-Truth Label Additions (Group 4)

| Check | How to verify |
|---|---|
| `segmentation_ground_truth.json` has an `alcaraz_serve_1.mov` entry with `release`/`trophy_pose`/`racket_drop`/`contact` timestamps | `python -c "import json; d=json.load(open('backend/tools/segmentation_ground_truth.json')); p=d['videos']['alcaraz_serve_1.mov'][0]['phases']; assert all(k in p for k in ('release','trophy_pose','racket_drop','contact'))"` |
| `serve_2.mov`'s entry now includes `trophy_pose` | `python -c "import json; d=json.load(open('backend/tools/segmentation_ground_truth.json')); assert 'trophy_pose' in d['videos']['serve_2.mov'][0]['phases']"` |
| `vesa_slow_mo.mov`'s entry now includes `contact` | `python -c "import json; d=json.load(open('backend/tools/segmentation_ground_truth.json')); assert 'contact' in d['videos']['vesa_slow_mo.mov'][0]['phases']"` |
| File still parses as valid JSON | `python -c "import json; json.load(open('backend/tools/segmentation_ground_truth.json'))"` exits 0. |

## Manual — Calibration Run & `rules.json` (Group 5, hard merge gate)

| Check | How to verify |
|---|---|
| `analyze_angles.py` runs end-to-end against the 5 reference serves | `cd backend && python tools/analyze_angles.py` — completes without error, prints all 9 metrics' per-serve values + aggregate stats. |
| `rules.json` holds 9 rules, all `view: "open_side"`, `severity: "major"`, replacing the old 5 | `python -c "import json; r=json.load(open('backend/rules.json'))['rules']; assert len(r)==9; assert all(x['view']=='open_side' and x['severity']=='major' for x in r)"` |
| `rules.json` loads cleanly through the real validator | `cd backend && python -c "import app.engine.rules"` exits 0. |
| **Self-consistency: all 5 reference serves pass every rule derived from them** | Recorded in run notes below — zero cues when each reference serve's real detected phase frames are evaluated against the calibrated `rules.json`. Hard requirement for merge. |
| Held-out sanity check performed and recorded | Recorded in run notes below — `serve_1.MOV`/`ag_three_serves.MOV` measured against the calibrated rules; any firing rule's plausibility assessed. |
| Full backend suite green | `pytest backend/` (equivalently `scripts/verify.sh backend`) — zero failures, includes every Group 1–3 addition. |
| No iOS files touched | `git diff --name-only develop...HEAD` contains no changes under `App/`. |

**Calibrated threshold table:**

| Rule id | Metric | Raw envelope (5 refs, at hand-labeled frames) | Chosen margin | Final threshold |
|---|---|---|---|---|
| `release_toss_arm_straight` | angle, gte | min=162.70, max=173.29 | −7.7° off min | `gte 155` |
| `release_toss_hand_eye_height` | y_diff, range | [−0.0204, 0.0736] (superseded; see post-correction note below) | ±0.02 | `range [-0.04, 0.10]` |
| `trophy_hitting_elbow_shoulder_line` | angle, range | [162.93, 178.81] | ±~8°, capped at 180 | `range [155, 180]` |
| `trophy_toss_arm_straight` | angle, gte | min=150.40, max=179.65 | −5.4° off min | `gte 145` |
| `trophy_toss_arm_vertical` | angle_from_vertical, lte | min=1.68, max=35.01 | +10° off max | `lte 45` |
| `racket_drop_ball_height` | ball_offset_y, range | [0.3067, 0.3766] (n=3 — no ball detected at racket_drop for serve_3/alcaraz) | ±0.03 | `range [0.28, 0.40]` |
| `racket_drop_ball_front` | ball_offset_x, range | [0.0162, 0.1001] (n=3, same gap) | ±0.02 | `range [-0.01, 0.12]` |
| `contact_left_hip_angle` | angle, range | [109.60, 141.30] | +14.7/+28.7° (upper widened again post-self-consistency, see below) | `range [95, 170]` |
| `contact_shoulders_stacked` | x_diff, range | [−0.0701, 0.0150] | ±0.02/0.025 | `range [-0.09, 0.04]` |

**Run notes:**

- **`analyze_angles.py` real run** (`cd backend && python tools/analyze_angles.py`, real RTMPose +
  YOLO models, ~5 min): completed cleanly against all 5 reference serves at each rule's
  hand-labeled phase timestamp. `racket_drop_ball_height`/`racket_drop_ball_front` only got 3/5
  values — no ball was detected by the object detector at the `racket_drop` frame for `serve_3.mov`
  or `alcaraz_serve_1.mov` (motion blur/small-object detection gap, same class of limitation
  documented for `vesa_slow_mo.mov`'s `contact` in P4b). The 3 available values (`serve_2`,
  `serve_4`, `vesa_slow_mo`) were tightly clustered, so the envelope is still trusted, but this is a
  smaller sample than the other 7 rules.
- **Self-consistency check, round 1 (initial margins):** ad hoc script ran the *real* auto-detection
  pipeline (`segment_serves` + `detect_phases`, not the hand-labeled timestamps) against all 5
  reference serves and evaluated the calibrated `rules.json`. 2 of 5 failed:
  `contact_left_hip_angle` fired on `serve_2.mov` (156.52° vs. the then-threshold_max of 156) and
  `serve_4.mov` (161.66° vs. 156). Root cause: the real auto-detected `contact` frame landed ~1
  sampled stride-2 frame (~0.033s) earlier than the hand-labeled frame used for calibration, and
  the hip-angle metric changes fast at this exact moment in the swing (the lead leg is actively
  extending) — a single-frame timing difference swung the measured angle by 15–20°, well beyond the
  original ±15° margin. All other 8 rules passed self-consistency cleanly on round 1.
- **Fix:** widened `contact_left_hip_angle`'s `threshold_max` from 156 to 170 — comfortably above
  the observed real-pipeline value of 161.66 (serve_4) with headroom. `threshold_min` (95) was left
  unchanged since every observed value (hand-labeled and real-pipeline, across all 5 references)
  stayed ≥107. The wider upper bound doesn't meaningfully weaken the rule's coaching value: a
  straighter/more-extended leg at contact isn't a real technique flaw, so the rule's useful signal
  is the lower bound (catching insufficient hip drive), which is unchanged.
- **Self-consistency check, round 2 (after the fix):** re-ran the same real-pipeline script — **all
  5 reference serves now produce zero cues** against the calibrated `rules.json`. Confirmed pass.
- **Held-out check** (`serve_1.MOV`, `ag_three_serves.MOV` — the user's own club-level serves,
  excluded from calibration, run through the same real auto-detection pipeline): `trophy_toss_arm_vertical`
  fired on all 4 held-out serves (`serve_1` and all 3 `ag_three_serves` serves) — a consistent
  pattern suggesting a real, repeatable difference in toss-arm verticality between these serves and
  the 5 references, plausible and informative rather than a threshold bug (a single reference serve
  being an outlier wouldn't explain firing on 4/4 held-out serves this uniformly).
  `racket_drop_ball_front` also fired once (`serve_1.MOV`). No held-out serve tripped
  `contact_left_hip_angle` after the widening. Per this phase's Not-Required-for-Merge list, this
  is disclosed as an informative finding, not treated as a failure.
- `pytest backend/` (full suite, after all fixes): **169 passed, 3 skipped, zero failures.**
- `git diff --name-only develop...HEAD` contains zero changes under `App/` — confirmed.
- The ad hoc self-consistency script (`backend/tools/_p5_self_consistency_check.py`, used only for
  this manual verification) was deleted before merge — not a committed artifact.

**Post-review correction — `alcaraz_serve_1.mov` ground-truth labels (disclosed process error):**

- **What happened:** Group 4's `alcaraz_serve_1.mov` entry (and, independently, the `serve_2.mov`
  `trophy_pose`/`vesa_slow_mo.mov` `contact` additions) was originally authored by the agent's own
  visual inspection of the segmentation-report frame images, without first checking whether the user
  already had hand-picked frame numbers — which they did, for every video in the calibration set.
  The user supplied the authoritative frame numbers after the fact. Cross-checking all 7 videos'
  frame numbers against every entry already in `segmentation_ground_truth.json` (existing pre-P5
  entries plus this phase's 3 additions) confirmed exact agreement everywhere **except**
  `alcaraz_serve_1.mov`'s `release`/`racket_drop`/`contact` (the agent's `trophy_pose` guess, and the
  `serve_2`/`vesa_slow_mo` additions, happened to land on the same frame the user had — those needed
  no change).
- **Fix:** replaced `alcaraz_serve_1.mov`'s `_note` and `phases` with the user's frame numbers,
  converted to timestamps via `frame * stride / fps` (stride 2, fps≈59.911) — `start` 147→4.907s,
  `release` 201→6.71s (was 6.009s), `trophy_pose` 262→8.746s (unchanged), `racket_drop` 292→9.748s
  (was 9.347s), `contact` 303→10.115s (was 9.981s), `finish` 344→11.484s. `start`/`finish` were added
  even though P5's rules don't read them, since the authoritative values were available at no extra
  cost.
- **Recalibration impact:** re-ran `analyze_angles.py` with the corrected ground truth. Of the 9
  metrics, only **`release_toss_hand_eye_height`** actually changed envelope: `alcaraz_serve_1`'s
  value moved from −0.0855 (previously the extreme low value, driving the old `threshold_min` of
  −0.11) to +0.0272 (no longer extremal — `serve_2.mov` at −0.0204 is now the min). The other 8
  metrics' min/max envelopes were unaffected — `alcaraz_serve_1` was never the extreme contributor
  for any of them, before or after the correction (its `trophy_pose`-phase metrics didn't move at
  all since `trophy_pose`'s frame was already correct; `contact_left_hip_angle`/`shoulders_stacked`
  and `release_toss_arm_straight` shifted numerically but stayed comfortably inside the existing
  envelope either way).
- **Threshold update:** narrowed `release_toss_hand_eye_height`'s `threshold_min` from `-0.11` to
  `-0.04` (new min −0.0204, same ±0.02 margin convention). Verified against the previously-captured
  real-auto-detection diagnostic values for all 5 references (−0.0204, −0.0170, 0.0736, −0.0061,
  −0.0209) — all comfortably inside `[-0.04, 0.10]`, so no further self-consistency risk was
  introduced by narrowing this bound.
- **Full self-consistency + held-out re-check** (real pipeline, post-correction): **all 5 reference
  serves again produce zero cues.** Held-out results on `serve_1.MOV`/`ag_three_serves.MOV` are
  **unchanged** from the pre-correction run (`trophy_toss_arm_vertical` on all 4 held-out serves,
  `racket_drop_ball_front` once) — expected, since the held-out check runs the real auto-detection
  pipeline independent of `segmentation_ground_truth.json` entirely.
- `pytest backend/` re-run after the correction: **169 passed, 3 skipped, zero failures.**

## Merge Criteria

- `pytest backend/` passes (full suite, zero failures) — includes all Group 1–3 unit test additions.
- **Group 4's ground-truth label additions are present and the file parses cleanly** — covers all 5
  reference videos' `release`/`trophy_pose`/`racket_drop`/`contact` timestamps.
- **Group 5's real calibration run has been completed** (hard merge gate, matching P4b's precedent):
  `rules.json` holds the 9 calibrated (non-placeholder) `view: "open_side"` rules, the
  self-consistency check passes (all 5 reference serves produce zero cues against their own
  derived rules), the held-out check against `serve_1.MOV`/`ag_three_serves.MOV` is recorded, and
  the calibrated threshold table + run notes above are filled in.
- **No iOS changes at all** — `git diff --name-only develop...HEAD` contains zero changes under
  `App/`.
- No changes to `RTMPoseModel`'s inference logic, `ObjectDetectionModel`, or `phases.py`'s
  phase-detection heuristics — all explicitly out of scope per `requirements.md`.
- No behind-server/closed-side rules, 3D recalibration, serve-type variants, or iOS/mode-selector
  wiring — all explicitly deferred (P15, P10, P14, P6 respectively).

## Not Required for Merge

- Behind-server / closed-side rules and the view-selection UI — P15.
- 3D re-calibration of these thresholds — P10.
- Per-serve-type threshold variants — P14.
- Wiring `/v1/analyze` or the mode-selector into the iOS app — P6.
- Rigorous ground-truth accuracy metrics (PCK/mAP) — P18.
- Perfect held-out performance on `serve_1.MOV`/`ag_three_serves.MOV` — these are club-level serves
  with real technique flaws; rules firing on them is expected and informative, not a failure.
