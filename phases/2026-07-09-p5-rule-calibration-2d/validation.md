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

**Calibrated threshold table (filled in during Group 5):**

| Rule id | Metric | Raw envelope (5 refs) | Chosen margin | Final threshold |
|---|---|---|---|---|
| `release_toss_arm_straight` | | | | |
| `release_toss_hand_eye_height` | | | | |
| `trophy_hitting_elbow_shoulder_line` | | | | |
| `trophy_toss_arm_straight` | | | | |
| `trophy_toss_arm_vertical` | | | | |
| `racket_drop_ball_height` | | | | |
| `racket_drop_ball_front` | | | | |
| `contact_left_hip_angle` | | | | |
| `contact_shoulders_stacked` | | | | |

**Run notes:**

*(filled in during Group 5 execution — self-consistency result, held-out check findings, any
threshold direction/sign corrections, and anything disclosed as an out-of-scope exception.)*

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
