# Phase P4b — Validation

## Definition of Done

Phase P4b is complete when all of the following pass.

## Backend — Trophy Pose Precision Fix (Group 1)

| Check | How to verify |
|---|---|
| `trophy_pose` rejects a frame where the hitting elbow is above hitting-shoulder height | `pytest backend/tests/test_phases.py -v -k test_trophy_rejected_when_elbow_above_shoulder` |
| `trophy_pose` still passes when elbow is at or below shoulder height (including the existing `TROPHY_KPS` fixture, elbow == shoulder) | `pytest backend/tests/test_phases.py -v -k test_trophy_passes_when_elbow_at_or_below_shoulder` |
| `trophy_pose` falls forward to a later qualifying frame when an earlier one fails only the new condition | `pytest backend/tests/test_phases.py -v -k test_trophy_falls_back_to_later_frame_when_elbow_above_shoulder_first` |
| All pre-existing `test_phases.py` trophy-pose tests still pass unmodified | `pytest backend/tests/test_phases.py -v` — zero failures, including every test present before this phase. |

## Backend — Contact Combined-Signal Redesign & Deterministic Tie-Breaking (Group 2)

| Check | How to verify |
|---|---|
| `contact` can pick a frame favored by racket-ball proximity over one favored by a higher wrist position | `pytest backend/tests/test_phases.py -v -k test_contact_combines_wrist_height_and_racket_ball_proximity` |
| Every pre-existing wrist-only `contact` fixture produces identical results with no `detections` argument | `pytest backend/tests/test_phases.py -v -k test_contact_all_existing_wrist_only_tests_pass_with_no_detections` |
| `contact` falls back to wrist-height-only when a frame has only a racket or only a ball detection (never both) | `pytest backend/tests/test_phases.py -v -k test_contact_falls_back_when_ball_or_racket_missing_from_frame` |
| A `detections` list shorter than `frames` does not raise `IndexError` for `contact` | `pytest backend/tests/test_phases.py -v -k test_contact_detections_shorter_than_frames` |
| `racket_drop`'s and `contact`'s combined-signal loops iterate in `sorted()` order, not raw `set()` order | `grep -n "for i in sorted(set(" backend/app/engine/phases.py` shows two matches (one for `racket_drop`, one for `contact`); `grep -n "for i in set(" backend/app/engine/phases.py` returns nothing. |
| Full backend suite green after Groups 1–2 | `pytest backend/tests/test_phases.py -v` — zero failures. |

## Backend — Denser Default Sampling (Group 3)

| Check | How to verify |
|---|---|
| `segmentation_report.py`'s default `--stride` is `2` | `pytest backend/tests/test_segmentation_report.py -v -k test_default_stride_is_two` |
| Full segmentation_report test suite green | `pytest backend/tests/test_segmentation_report.py -v` — zero failures, no real model construction (unchanged from P4's guard). |

## Manual — Re-Validation, Full Spot-Check & Ground-Truth Authoring (Group 4, hard merge gate)

| Check | How to verify |
|---|---|
| `segmentation_report.py` runs end-to-end with the new `--stride 2` default against every video in `calibration_data/` | `cd backend && python tools/segmentation_report.py` — completes without error. |
| Every video's `segment_serves` count still matches its expected count (from P4's table) at the new stride | Open each `serve_N_segmentation/report.html` and compare against the table below. If any don't match, retune `MIN_REST_SECONDS`/`LOW_MOTION_VELOCITY_THRESHOLD` and re-run — hard requirement for merge, same as P4's gate. |
| `ag_three_serves.MOV`'s previously-`None` `racket_drop` outcome is re-checked and the resolution documented | Recorded in run notes below — either it now resolves (denser stride + trophy_pose/contact fixes gave it a real candidate frame) or it's confirmed still structurally unresolvable, with the reason noted. |
| Full six-phase visual spot-check across every video (not just 2–3) | Recorded in run notes below — this is best-effort/documented, not a strict pass/fail gate, since there's no ground truth to check against *before* Group 4 produces one. Anything that looks visibly wrong should either be fixed via a tunable constant (step 17 of `plan.md`) or explicitly noted as a known follow-up. |
| Final tuned constant values recorded | `MIN_REST_SECONDS`, `LOW_MOTION_VELOCITY_THRESHOLD`, `RACKET_DROP_ELBOW_WEIGHT`, `RACKET_DROP_RACKET_WEIGHT`, `CONTACT_WRIST_WEIGHT`, `CONTACT_PROXIMITY_WEIGHT`, and the `--stride` default — whatever values the code ends up with after iteration, transcribed into the run notes below. |
| `backend/tools/segmentation_ground_truth.json` exists, is git-tracked, and covers every video/serve/phase | `git check-ignore backend/tools/segmentation_ground_truth.json` exits non-zero (not ignored); `python -c "import json; d=json.load(open('backend/tools/segmentation_ground_truth.json')); print(list(d['videos']))"` lists every calibration video. |
| No regression to existing backend endpoints/tests | `pytest backend/` includes and passes all pre-existing test files. |
| No iOS files touched | `git diff --name-only develop...HEAD` contains no changes under `App/`. |

**Expected vs. actual serve counts (re-confirmed at `--stride 2`):**

| Video | Expected serve count | Actual serve count |
|---|---|---|
| `serve_1.MOV` | 1 | — |
| `serve_2.mov` | 1 | — |
| `serve_3.mov` | 1 | — |
| `serve_4.mov` | 1 | — |
| `ag_three_serves.MOV` | 3 | — |
| `vesa_slow_mo.mov` | 1 | — |

**Run notes:**

- *(To be filled in during `/phase` Group 4.)*

## Backend — Ground-Truth Regression Test (Group 5, hard merge gate)

| Check | How to verify |
|---|---|
| `test_segmentation_ground_truth.py` is skipped by default | `pytest backend/` — the new test does not run without `RUN_MODEL_INTEGRATION_TESTS=1` set, matching `test_pose_model_integration.py`/`test_object_detection_integration.py`'s precedent. |
| The regression test passes against the ground truth authored in Group 4 | `cd backend && RUN_MODEL_INTEGRATION_TESTS=1 .venv/bin/pytest tests/test_segmentation_ground_truth.py -v` — passes with zero failures against the real models and real footage. |
| Full backend suite green (default run) | `pytest backend/` (equivalently `scripts/verify.sh backend`) — zero failures, including every pre-existing test file plus all Group 1–3 additions. |
| No iOS files touched | `git diff --name-only develop...HEAD` contains no changes under `App/`. |

## Merge Criteria

- `scripts/verify.sh backend` passes (full `pytest backend/` suite, zero failures) — includes all
  Group 1–3 test additions; the new Group 5 ground-truth test is present but skipped by default
  (no real model load in this run).
- **The Group 4 manual real-footage run has been completed, every video's serve count matches its
  expected count at `--stride 2`, `backend/tools/segmentation_ground_truth.json` is authored and
  git-tracked, and the run notes above (including final tuned constants) are filled in.** Hard
  merge gate, same pattern as P4's Group 5.
- **The Group 5 ground-truth regression test passes when run with `RUN_MODEL_INTEGRATION_TESTS=1`
  against the real footage and the ground truth authored in Group 4.** Hard merge gate — this is
  this phase's core "don't regress this again" deliverable, not an incidental smoke test.
- `calibration_report.py`, `RTMPoseModel`, and `ObjectDetectionModel` are unmodified.
- **No iOS changes at all** — `git diff --name-only develop...HEAD` contains zero changes under
  `App/`.
- No changes to the six-frame model's shape, the `ServePhase` enum, `segment_serves`'s time-based
  design, `rules.json`/rule-calibration, or the mode-selector/iOS wiring — all explicitly out of
  scope per `requirements.md`.

## Not Required for Merge

- Rigorous ground-truth accuracy metrics (PCK/mAP) — still deferred to P18; this phase's
  ground-truth JSON is six timestamps per serve for regression-catching, not per-keypoint accuracy.
- Rule calibration / `rules.json` changes (P5).
- Wiring `/v1/analyze`, `segment_serves`, or the mode-selector into the iOS app (P6/P7).
- Perfect visual correctness on every conceivable real-world serve — Group 4 targets the videos
  available at merge time; broader robustness can continue to be tuned in future phases via the
  same tunable constants and the ground-truth regression test this phase establishes.
