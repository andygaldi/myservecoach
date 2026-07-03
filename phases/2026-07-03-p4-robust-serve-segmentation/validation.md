# Phase P4 — Validation

## Definition of Done

Phase P4 is complete when all of the following pass.

## Backend — Six-Frame Model & Positional Heuristics (Group 1)

| Check | How to verify |
|---|---|
| `ServePhase` has six members (`start`, `release`, `trophy_pose`, `racket_drop`, `contact`, `finish`) with unchanged existing string values | `python -c "from app.models import ServePhase; print(list(ServePhase))"` from `backend/` — six entries; `ServePhase.trophy_pose.value == 'trophy_pose'` etc. unchanged. |
| `start` resolves to the first frame, `None` for an empty frame list | `pytest backend/tests/test_phases.py -v -k "test_start"` |
| `finish` resolves to the last frame, `None` for an empty frame list | `pytest backend/tests/test_phases.py -v -k "test_finish"` |
| `release` resolves to the earliest toss-rise frame, skips frames with missing toss keypoints, `None` when the toss never rises | `pytest backend/tests/test_phases.py -v -k "test_release"` |
| All pre-existing `test_phases.py` tests (trophy/racket-drop/contact) still pass unmodified | `pytest backend/tests/test_phases.py -v` — zero failures, including every test present before this phase. |

## Backend — Racket-Augmented Racket-Drop Detection (Group 2)

| Check | How to verify |
|---|---|
| `racket_drop` prefers the lowest-racket-center-y frame when a racket detection exists in the trophy→contact window | `pytest backend/tests/test_phases.py -v -k test_racket_drop_uses_racket_signal_when_present` |
| `racket_drop` falls back to the elbow-y-rise heuristic when `detections` is provided but empty for every frame in range | `pytest backend/tests/test_phases.py -v -k test_racket_drop_falls_back_to_elbow_when_no_racket_detected` |
| Ball detections never influence `racket_drop` | `pytest backend/tests/test_phases.py -v -k test_racket_drop_ignores_ball_detections` |
| A `detections` list shorter than `frames` does not raise `IndexError` and falls back correctly for the missing tail | `pytest backend/tests/test_phases.py -v -k test_racket_drop_detections_shorter_than_frames` |
| `detect_phases(frames)` with no `detections` argument at all behaves exactly as before (default `None`, elbow-only path) | `pytest backend/tests/test_phases.py -v` — every pre-existing call site (none pass `detections`) still passes. |
| `AnalyzeRequest` accepts an optional `detections` field; `/analyze` still works with and without it | `pytest backend/tests/test_analyze.py -v` |
| Full backend suite green after Groups 1–2 | `pytest backend/tests/test_phases.py backend/tests/test_analyze.py -v` — zero failures. |

## Backend — Segmentation Report Tool (Group 3)

| Check | How to verify |
|---|---|
| `build_frame_sequence` returns frame/detection/image lists of matching, correct length | `pytest backend/tests/test_segmentation_report.py -v -k TestBuildFrameSequence` |
| `generate_segmentation_html` writes a report containing all six phase labels, with a placeholder for undetected phases | `pytest backend/tests/test_segmentation_report.py -v -k TestGenerateSegmentationHtml` |
| `run_segmentation_report` produces a valid report + frame JPEGs end-to-end against a synthetic video and stub models | `pytest backend/tests/test_segmentation_report.py -v -k TestRunSegmentationReport` |
| No real model class (`RTMPoseModel`, `ObjectDetectionModel`, `YOLO(`, `Body(`) is constructed in the default test suite | `grep -rn "RTMPoseModel(\|ObjectDetectionModel(\|YOLO(\|Body(" backend/tests/test_segmentation_report.py` returns nothing; the file's default run is fast with no network activity. |
| `calibration_report.py` is unmodified by this phase | `git diff --name-only develop...HEAD -- backend/tools/calibration_report.py` is empty. |
| Full backend suite green | `pytest backend/` (equivalently `scripts/verify.sh backend`) — zero failures, including every pre-existing test file. |

## Manual — Real-Footage Re-Validation (Group 4, hard merge gate)

| Check | How to verify |
|---|---|
| `segmentation_report.py` runs end-to-end against all four real serve videos | `cd backend && python tools/segmentation_report.py` — completes without error. |
| Visual spot-check of all six phases across the four videos | Open each `backend/tools/calibration_data/serve_N_segmentation/report.html` — record which phases (if any) resolved to `None`, and note anything visually wrong, in the run notes below. This phase does not need every phase to resolve on every video to merge — Start/Finish/Release are new and unvalidated against real footage until this run. |
| Racket-augmented `racket_drop` qualitatively compared against the prior elbow-only result for at least one video with a reliable racket detection in range | Record the comparison in the run notes below. |
| No regression to existing backend endpoints/tests | `pytest backend/` includes and passes all pre-existing test files (`test_analyze.py`, `test_phases.py`, `test_pose_endpoint.py`, `test_detect_endpoint.py`, `test_reference_frames.py`, `test_rules.py`, `test_angles.py`, `test_calibration_report.py`, `test_object_detection.py`, `test_pose_benchmark.py`). |
| No iOS files touched | `git diff --name-only develop...HEAD` contains no changes under `App/`. |

**Run notes:**

- *(To be filled in during `/phase` Group 4.)*

## Merge Criteria

- `scripts/verify.sh backend` passes (full `pytest backend/` suite, zero failures) — includes the new
  `test_segmentation_report.py` suite and the extended `test_phases.py`/`test_analyze.py` assertions; no
  real model load happens in this run.
- **The Group 4 manual real-footage run has been completed at least once**, its six-phase HTML reports
  reviewed for all four videos, and the run notes above filled in. This is a hard merge gate — the whole
  point of this phase is a segmentation heuristic that holds up against real footage, not just synthetic
  fixtures.
- `calibration_report.py`, `RTMPoseModel`, and `ObjectDetectionModel` are unmodified.
- **No iOS changes at all** — `git diff --name-only develop...HEAD` contains zero changes under `App/`.
- No multi-serve boundary splitting, no `rules.json`/rule-calibration changes for the new phases, no
  ground-truth/PCK accuracy tooling, no mode-selector or `/v1/analyze` iOS wiring — all explicitly out of
  scope per `requirements.md`.

## Not Required for Merge

- Rigorous ground-truth accuracy metrics for the new phases (deferred to P18).
- Rule calibration / `rules.json` thresholds for Start, Release, or Finish (P5).
- Wiring `/v1/analyze` or the mode-selector into the iOS app (P6).
- Multi-serve continuous-clip boundary splitting (deferred until P7 actually needs it).
- Fixing any segmentation quality issues surfaced by the Group 4 visual spot-check beyond what this
  phase's heuristics already address — documented for follow-up, not necessarily fixed in this phase.
