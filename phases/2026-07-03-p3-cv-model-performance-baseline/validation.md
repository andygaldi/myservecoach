# Phase P3 — Validation

## Definition of Done

Phase P3 is complete when all of the following pass.

## Backend — Frame Sampling & Overlay Drawing (Group 1)

| Check | How to verify |
|---|---|
| `sample_video_frames` returns every `stride`-th frame with correct timestamps | `pytest backend/tests/test_pose_benchmark.py -v -k TestSampleVideoFrames` — a 60-frame/30fps synthetic video with `stride=5` yields 12 frames at `0.0, 5/30, 10/30, ...`. |
| `stride=1` returns all frames | Same test file — 60-frame video, `stride=1` yields 60 entries. |
| Nonexistent video path raises `ValueError` | Same test file. |
| `draw_overlay` returns a same-shape copy, never mutates the input | `pytest backend/tests/test_pose_benchmark.py -v -k TestDrawOverlay` — `result is not image`, `result.shape == image.shape`. |
| `draw_overlay` visibly annotates the frame when keypoints/detections are present | Same test file — `not np.array_equal(result, image)`. |
| `draw_overlay` with no keypoints/detections still returns without raising | Same test file — empty dict/list input case. |

## Backend — Per-Frame Benchmarking & Aggregation (Group 2)

| Check | How to verify |
|---|---|
| `benchmark_frame` correctly derives `person_detected`/`racket_detected`/`ball_detected` and confidences from stub model output | `pytest backend/tests/test_pose_benchmark.py -v -k TestBenchmarkFrame` |
| Both latencies are non-negative | Same test file. |
| `aggregate_stats` computes correct per-video detection rates and averages | `pytest backend/tests/test_pose_benchmark.py -v -k TestAggregateStats` — hand-computed expected values (e.g. `2/3` racket detection rate) match. |
| `aggregate_stats`'s `"aggregate"` entry correctly pools frames across multiple videos | Same test file. |
| No division-by-zero on an empty per-video frame list | Same test file — `0.0` rates / `None` averages, no exception. |

## Backend — HTML Report & CLI Orchestration (Group 3)

| Check | How to verify |
|---|---|
| `run_benchmark` produces a valid baseline JSON with the documented top-level keys | `pytest backend/tests/test_pose_benchmark.py -v -k TestRunBenchmark` — `generated_at`, `stride`, `videos`, `aggregate` all present. |
| `run_benchmark` produces `report.html` and per-frame overlay JPEGs under `<report_root>/<video_stem>_benchmark/` | Same test file. |
| No real model class (`RTMPoseModel`, `ObjectDetectionModel`, `YOLO(`, `Body(`) is constructed in the default test suite | `grep -rn "RTMPoseModel(\|ObjectDetectionModel(\|YOLO(\|Body(" backend/tests/test_pose_benchmark.py` returns nothing; `pytest backend/tests/test_pose_benchmark.py` completes quickly with no network activity. |
| `backend/tools/pose_benchmark_baselines/` is git-tracked, not gitignored | `git check-ignore backend/tools/pose_benchmark_baselines/test.json` — exits non-zero (not ignored). |
| Full backend suite green | `pytest backend/` (equivalently `scripts/verify.sh backend`) — zero failures, including all pre-existing tests. |

## Manual — Real-Footage Baseline Run (Group 4, hard merge gate)

| Check | How to verify |
|---|---|
| `pose_benchmark.py` runs end-to-end against all four real serve videos | `cd backend && python tools/pose_benchmark.py` — completes without error (may download RTMPose/YOLO weights on first run). |
| Visual spot-check of overlay quality | Open each `backend/tools/calibration_data/serve_N_benchmark/report.html` in a browser — skeleton dots plausibly track the body and racket/ball boxes plausibly land on the racket/ball across a sample of frames. Record any gross CV failures (e.g. no person ever detected) in the notes below — this phase does not fix such failures, only documents them for P4. |
| First committed baseline JSON exists and reflects the real run | `backend/tools/pose_benchmark_baselines/<timestamp>.json` is created, added with `git add`, and its `aggregate` numbers are transcribed into the run notes below. |
| No regression to existing backend endpoints/tests | `pytest backend/` includes and passes all pre-existing test files (`test_analyze.py`, `test_phases.py`, `test_pose_endpoint.py`, `test_detect_endpoint.py`, `test_reference_frames.py`, `test_rules.py`, `test_angles.py`, `test_calibration_report.py`, `test_object_detection.py`). |
| No iOS files touched | `git diff --name-only develop...HEAD` contains no changes under `App/`. |

**Run notes (fill in after the manual run):**

- Baseline file: `backend/tools/pose_benchmark_baselines/<timestamp>.json`
- Aggregate person/racket/ball detection rates:
- Aggregate avg keypoint / racket / ball confidence:
- Aggregate avg pose FPS / detection FPS:
- Visual spot-check observations (gross failures, if any):

## Merge Criteria

- `scripts/verify.sh backend` passes (full `pytest backend/` suite, zero failures) — includes the new
  synthetic-fixture `test_pose_benchmark.py` suite; no real model load happens in this run.
- **The Group 4 manual real-footage run has been completed at least once**, its baseline JSON committed to
  `backend/tools/pose_benchmark_baselines/`, and the run notes above filled in. Unlike P2's opt-in real-model
  check, this is a hard merge gate — producing the first committed baseline is this phase's core deliverable,
  not an incidental smoke test.
- No changes to `RTMPoseModel`, `ObjectDetectionModel`, `backend/app/engine/phases.py`, or `rules.json`.
- **No iOS changes at all** — `git diff --name-only develop...HEAD` contains zero changes under `App/`.
- No new `/v1` endpoint, no ground-truth/PCK/mAP accuracy tooling, no automated baseline-comparison/CI gating
  — all explicitly out of scope per `requirements.md`.

## Not Required for Merge

- Rigorous ground-truth accuracy metrics (PCK/mAP) — deferred to Phase P18.
- Fixing any CV quality issues surfaced by the visual spot-check — this phase documents, P4 (and beyond)
  addresses.
- Automated regression gating / CI comparison against the baseline (deferred "continuous CV model improvement
  loop," not scheduled).
- Combining pose + object-detection signals into segmentation logic (Phase P4).
