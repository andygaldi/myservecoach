# Phase P4 — Validation

## Definition of Done

Phase P4 is complete when all of the following pass.

## Backend — Six-Frame Model & Multi-Serve Boundary Splitting (Group 1)

| Check | How to verify |
|---|---|
| `ServePhase` has six members with unchanged existing string values | `python -c "from app.models import ServePhase; print(list(ServePhase))"` from `backend/` — six entries; `ServePhase.trophy_pose.value == 'trophy_pose'` etc. unchanged. |
| `segment_serves([])` returns `[]` | `pytest backend/tests/test_segment_serves.py -v -k test_empty_frames_returns_empty_list` |
| A continuously-active frame sequence returns exactly one segment | `pytest backend/tests/test_segment_serves.py -v -k test_single_serve_no_rest_gap_returns_one_segment` |
| Two active bursts separated by a rest run `>= MIN_REST_SECONDS` split into two segments at the rest run's midpoint | `pytest backend/tests/test_segment_serves.py -v -k test_two_serves_separated_by_rest_gap_returns_two_segments` |
| A rest run shorter than `MIN_REST_SECONDS` does not split | `pytest backend/tests/test_segment_serves.py -v -k test_short_rest_gap_does_not_split` |
| Leading idle before the first active burst is not split into its own segment | `pytest backend/tests/test_segment_serves.py -v -k test_leading_idle_not_split_off` |
| Trailing idle after the last active burst is not split into its own segment | `pytest backend/tests/test_segment_serves.py -v -k test_trailing_idle_not_split_off` |
| `_frame_velocity` ignores keypoints below `MIN_CONFIDENCE` | `pytest backend/tests/test_segment_serves.py -v -k test_velocity_ignores_low_confidence_keypoints` |

## Backend — New Phase Heuristics: Start, Release, Finish (Group 2)

| Check | How to verify |
|---|---|
| `release` uses the ball-detection signal when the ball is ever detected, even if it disagrees with the toss-wrist-rise fallback | `pytest backend/tests/test_phases.py -v -k test_release_ball_primary_when_ball_ever_detected` |
| `release` falls back to toss-wrist-rise when no `"ball"` detection exists anywhere, or when `detections` is omitted | `pytest backend/tests/test_phases.py -v -k "test_release_falls_back"` |
| `release` is `None` when neither signal ever qualifies | `pytest backend/tests/test_phases.py -v -k test_release_none_when_toss_never_rises_and_no_ball` |
| `start` resolves to the lowest toss-wrist frame strictly before `release` (or `trophy_pose` if `release` is unresolved) | `pytest backend/tests/test_phases.py -v -k "test_start_is_lowest\|test_start_falls_back"` |
| `start` is `None` when neither `release` nor `trophy_pose` resolve | `pytest backend/tests/test_phases.py -v -k test_start_none_when_neither_release_nor_trophy_resolve` |
| `finish` resolves to the lowest front-foot (toss-side ankle) frame after `contact` | `pytest backend/tests/test_phases.py -v -k test_finish_is_lowest_front_foot_after_contact` |
| `finish` falls back to the last frame when there's no post-contact ankle data, or no `contact` at all | `pytest backend/tests/test_phases.py -v -k "test_finish_falls_back"` |
| All pre-existing `test_phases.py` tests (trophy/racket-drop/contact) still pass unmodified | `pytest backend/tests/test_phases.py -v` — zero failures, including every test present before this phase. |

## Backend — Combined-Signal Racket Drop (Group 3)

| Check | How to verify |
|---|---|
| `racket_drop` can pick a frame favored by the racket signal over one favored by a stronger elbow-rise signal, when weighted combination says so | `pytest backend/tests/test_phases.py -v -k test_racket_drop_combines_elbow_and_racket_signals` |
| Every pre-existing elbow-only `racket_drop` fixture produces identical results with no `detections` argument | `pytest backend/tests/test_phases.py -v -k test_racket_drop_all_existing_elbow_only_tests_pass_with_no_detections` |
| Ball detections never influence `racket_drop` | `pytest backend/tests/test_phases.py -v -k test_racket_drop_ignores_ball_detections` |
| A `detections` list shorter than `frames` does not raise `IndexError` | `pytest backend/tests/test_phases.py -v -k test_racket_drop_detections_shorter_than_frames` |
| `_min_max_normalize` handles all-equal and single-entry inputs without raising | `pytest backend/tests/test_phases.py -v -k test_min_max_normalize_handles_equal_values` |
| `AnalyzeRequest` accepts an optional `detections` field; `/analyze` works with and without it | `pytest backend/tests/test_analyze.py -v` |
| Full backend suite green after Groups 1–3 | `pytest backend/tests/test_segment_serves.py backend/tests/test_phases.py backend/tests/test_analyze.py -v` — zero failures. |

## Backend — Segmentation Report Tool (Group 4)

| Check | How to verify |
|---|---|
| `build_frame_sequence` returns frame/detection/image lists of matching, correct length | `pytest backend/tests/test_segmentation_report.py -v -k TestBuildFrameSequence` |
| `generate_segmentation_html` writes a report with one section per serve and all six phase labels | `pytest backend/tests/test_segmentation_report.py -v -k TestGenerateSegmentationHtml` |
| `run_segmentation_report` produces two serve sections end-to-end against a synthetic two-burst video and stub models | `pytest backend/tests/test_segmentation_report.py -v -k TestRunSegmentationReport` |
| No real model class (`RTMPoseModel`, `ObjectDetectionModel`, `YOLO(`, `Body(`) is constructed in the default test suite | `grep -rn "RTMPoseModel(\|ObjectDetectionModel(\|YOLO(\|Body(" backend/tests/test_segmentation_report.py` returns nothing; the file's default run is fast with no network activity. |
| `calibration_report.py` is unmodified by this phase | `git diff --name-only develop...HEAD -- backend/tools/calibration_report.py` is empty. |
| Full backend suite green | `pytest backend/` (equivalently `scripts/verify.sh backend`) — zero failures, including every pre-existing test file. |

## Manual — Real-Footage Re-Validation & Heuristic Iteration (Group 5, hard merge gate)

| Check | How to verify |
|---|---|
| `segmentation_report.py` runs end-to-end against every video in `calibration_data/`, including any newly-added ones | `cd backend && python tools/segmentation_report.py` — completes without error. |
| **Every** multi-serve video splits into exactly its known expected serve count | Open each `serve_N_segmentation/report.html` and compare against the expected-count table below. `ag_three_serves.MOV` plus any further newly-added multi-serve videos must all match. If any don't, tune `MIN_REST_SECONDS`/`LOW_MOTION_VELOCITY_THRESHOLD` and re-run until all of them do — this is a hard requirement for merge. |
| Every single-serve video still produces exactly one serve section | Open each `serve_N_segmentation/report.html` for the single-serve videos — one section each, no spurious splits. This includes `serve_4.mov`: its console log shows two on-device-Vision-segmented entries, but that's Vision's own over-splitting of one real serve, not ground truth for this phase — `segment_serves` must produce one section for it, not two. |
| Visual spot-check of all six phases across every detected serve section | Record which phases (if any) resolved to `None`, and anything visually wrong, in the run notes below. |
| Qualitative comparison of combined-signal `racket_drop` vs. the prior elbow-only result for at least one video with a reliably-detected racket in the trophy→contact window | Recorded in run notes below. |
| Final tuned constant values recorded | `MIN_REST_SECONDS`, `LOW_MOTION_VELOCITY_THRESHOLD`, `RACKET_DROP_ELBOW_WEIGHT`, `RACKET_DROP_RACKET_WEIGHT` — whatever values `phases.py` ends up with after iteration, transcribed into the run notes below. |
| No regression to existing backend endpoints/tests | `pytest backend/` includes and passes all pre-existing test files. |
| No iOS files touched | `git diff --name-only develop...HEAD` contains no changes under `App/`. |

**Expected vs. actual serve counts** *(filled in before/during the Group 5 run — add one row per video in `calibration_data/`)*:

| Video | Expected serve count | Actual serve count |
|---|---|---|
| `serve_1.MOV` | 1 | 1 |
| `serve_2.mov` | 1 | 1 |
| `serve_3.mov` | 1 | 1 |
| `serve_4.mov` | 1 | 1 |
| `ag_three_serves.MOV` | 3 | 3 |
| `vesa_slow_mo.mov` | 1 | 1 |

**Run notes:**

- **Final tuned constants:** `MIN_REST_SECONDS = 0.4`, `LOW_MOTION_VELOCITY_THRESHOLD = 0.03` (both changed from
  their initial values — `0.2`/`0.15` — chosen before any real footage existed). `RACKET_DROP_ELBOW_WEIGHT`/
  `RACKET_DROP_RACKET_WEIGHT` stayed at the original `0.5`/`0.5`; no evidence from spot-checking required
  reweighting them.
- **Tuning process:** the initial defaults badly over-split every video (`ag_three_serves.MOV`: 10 instead of
  3; `serve_1.MOV`: 5 instead of 1) — real pose-estimation keypoint jitter has a non-zero noise floor
  (~0.02–0.07 units/sec observed on `serve_1.MOV`, comparable to the initial `0.15` threshold), so brief
  natural pauses within a single serve's routine (ball bounces, stance adjustment) were being misclassified
  as inter-serve rest gaps. Cached one real off-device pose run per video (no re-inference needed) and grid-
  searched `velocity_threshold ∈ [0.02, 0.045]` × `min_rest_seconds ∈ [0.3, 3.0]` against the known expected
  counts; `(0.03, 0.4)` is the center of a stable region (`0.03–0.035` × `0.35–0.50`) that exactly matches all
  six videos, not an isolated fluke.
- **All six phases resolved with no `None`s** on `serve_1.MOV`, `serve_2.mov`, `serve_3.mov`, `serve_4.mov`,
  and `vesa_slow_mo.mov`.
- **`ag_three_serves.MOV`: `racket_drop` is `None` on all 3 detected serves** (one serve also missed
  `trophy_pose`). Root-caused, not a bug: in each case `trophy_pose` and `contact` resolved to *adjacent*
  sampled frames (e.g. frame052 → frame053), leaving an empty `range(trophy_idx+1, contact_idx)` for the
  racket-drop search — the same designed behavior as the pre-existing
  `test_no_frames_between_trophy_and_contact_gives_no_racket_drop` case, just triggered here by
  `--stride 5` sampling being too sparse to catch an intermediate frame during a fast real swing. Not fixed
  in this phase (out of scope — `trophy_pose`/`contact` heuristics are unchanged); a finer `--stride` would
  likely resolve it and is a natural follow-up, not a blocker.
- **Qualitative `racket_drop` comparison:** visually inspected the combined-signal frame on `serve_1.MOV`
  (frame047) and `serve_4.mov` (frame062) — both land cleanly on the racket-behind-the-back "back-scratch"
  position, clearly distinct from the adjacent `trophy_pose`/`contact` frames. This is a materially more
  precise picture of Cocking than the prior elbow-only heuristic could guarantee alone, since a racket
  detection was present and contributing in both windows.
- Visual spot-check of the full six-phase sequence on `serve_1.MOV` and `serve_4.mov` (both real outdoor/
  stadium footage) shows a coherent, correct story matching the Kovacs stages: bent-over stance → toss
  release → trophy pose → racket-dropped cocking → arm-extended contact → post-swing finish/walk-off.
  `vesa_slow_mo.mov`'s `trophy_pose`/`racket_drop` frames are less crisply "classic trophy pose" looking
  than the other two (racket appears higher/less dropped-behind-the-back at both frames) — plausibly a
  different serve style or camera angle, and since `trophy_pose`'s heuristic is unchanged by this phase,
  this is a pre-existing limitation to note for future calibration, not a P4 regression.
- No iOS files touched during this run (verified below).

## Merge Criteria

- `scripts/verify.sh backend` passes (full `pytest backend/` suite, zero failures) — includes
  `test_segment_serves.py`, `test_segmentation_report.py`, and the extended `test_phases.py`/
  `test_analyze.py` assertions; no real model load happens in this run.
- **The Group 5 manual real-footage run has been completed, every multi-serve video (`ag_three_serves.MOV`
  plus any further newly-added ones) splits into exactly its expected serve count, every single-serve video
  (including `serve_4.mov`) produces exactly one section, and the run notes above (including the
  expected-vs-actual table and final tuned constants) are filled in.** This is a hard merge gate, consistent
  with this phase's explicit expectation of iterative tuning against real footage.
- `calibration_report.py`, `RTMPoseModel`, and `ObjectDetectionModel` are unmodified.
- **No iOS changes at all** — `git diff --name-only develop...HEAD` contains zero changes under `App/`.
- No `rules.json`/rule-calibration changes for the new phases, no ground-truth/PCK accuracy tooling, no
  mode-selector or `/v1/analyze` iOS wiring, no ball-signal use outside of `release` — all explicitly out
  of scope per `requirements.md`.

## Not Required for Merge

- Rigorous ground-truth accuracy metrics for the new phases or for `segment_serves`'s boundary accuracy
  (deferred to P18).
- Rule calibration / `rules.json` thresholds for Start, Release, or Finish (P5).
- Wiring `/v1/analyze`, `segment_serves`, or the mode-selector into the iOS app (P6/P7).
- Perfect segmentation/phase accuracy on every possible real-world serve — Group 5 targets the four
  available calibration videos; broader real-world robustness can continue to be tuned after merge via the
  same tunable constants.
