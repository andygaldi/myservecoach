# Phase P2 — Validation

## Definition of Done

Phase P2 is complete when all of the following pass.

## Backend — Object Detection Model Mapping (Group 1)

| Check | How to verify |
|---|---|
| `tennis racket` (COCO class 38) maps to `label="racket"` | `pytest backend/tests/test_object_detection.py -v` — detection present with correct `label`/`confidence`/`bbox`. |
| `sports ball` (COCO class 32) maps to `label="ball"` | Same test file — analogous assertion. |
| Bounding box normalized 0–1 and y-flipped to Vision's convention | Same test file — a box near the top of the source image has `bbox.y_min`/`bbox.y_max` near `1.0`; a box near the bottom has values near `0.0`. |
| `y_min < y_max` invariant holds after the y-flip | Same test file — explicit assertion, since flipping inverts which raw coordinate is smaller. |
| Non-racket/ball classes (e.g. `person`, class 0) are dropped | Same test file — result list has no detection for a non-mapped class id. |
| Below-`confidence_threshold` detections are dropped | Same test file — a detection with `conf` under the threshold is absent from the result. |
| Empty `boxes` input produces `[]` without raising | Same test file. |
| No real model load in default suite | Manual check: `grep -rn "YOLO(" backend/tests/test_object_detection.py` returns nothing; `pytest backend/tests/test_object_detection.py` completes in well under a second with no network activity. |

## Backend — `POST /v1/detect` Endpoint (Group 2)

| Check | How to verify |
|---|---|
| Valid request returns HTTP 200 with correct frame count/timestamps/detections | `pytest backend/tests/test_detect_endpoint.py -v` |
| Mismatched `frames`/`timestamps` lengths returns HTTP 400 | Same test file |
| Corrupt image bytes returns HTTP 400 | Same test file |
| Endpoint registered under `/v1` prefix | `grep "detect.router" backend/app/main.py` shows `prefix="/v1"` |
| Full backend suite green | `pytest backend/` (equivalently `scripts/verify.sh backend`) — zero failures, including all pre-existing tests |

## Backend — Opt-In Real-Model Check (Group 3, informational — see Merge Criteria)

| Check | How to verify |
|---|---|
| Real `ultralytics.YOLO` loads and runs inference without error | `cd backend && RUN_MODEL_INTEGRATION_TESTS=1 pytest tests/test_object_detection_integration.py -v` — record pass/fail and first-run weight-download time/size in this file's notes once run. |

**Run notes:** _(fill in after Group 3, task 11 is executed during `/phase`)_

## Integration (Group 4, manual — local backend)

| Check | How to verify |
|---|---|
| `/v1/detect` responds to a real multipart request | `curl -F "frames=@sample.jpg" -F "timestamps=0.5" http://localhost:8000/v1/detect` → HTTP 200, well-formed `frames` array |
| Full backend suite green | `scripts/verify.sh backend` — zero failures |
| No iOS files touched | `git diff --name-only develop...HEAD` contains no changes under `App/` |
| No regression to existing backend endpoints | `pytest backend/` includes and passes all pre-existing test files (`test_analyze.py`, `test_phases.py`, `test_pose_endpoint.py`, `test_reference_frames.py`, `test_rules.py`, `test_angles.py`, `test_calibration_report.py`) |

## Merge Criteria

- `scripts/verify.sh backend` passes (full `pytest backend/` suite, zero failures) — the opt-in `RUN_MODEL_INTEGRATION_TESTS=1` real-model test is **not** part of this run and is **not** a merge gate; it's a one-time manual check whose outcome is recorded above for documentation purposes.
- The Group 4 manual integration smoke test has been run at least once (`/v1/detect` curl check confirmed).
- **No iOS changes at all** — `git diff --name-only develop...HEAD` contains zero changes under `App/`. This phase has no iOS surface; stricter than P1's narrower Lite-file gate because there is no iOS work to distinguish from Lite work.
- No changes to `rules.json` or `backend/app/engine/phases.py` — P4 is where detection signals get consumed by segmentation logic, not this phase.
- No new UI, no fine-tuning artifacts/training scripts, no `/v1/detect` iOS caller — all explicitly out of scope per `requirements.md`.

## Not Required for Merge

- Fine-tuning YOLO on tennis-specific footage (deferred; needs a labeled dataset not yet collected).
- Combining pose + racket/ball signals into segmentation logic (Phase P4).
- Detection accuracy/confidence benchmarking against real footage (Phase P3).
- iOS capture/POST of raw frames to `/v1/detect` (deferred; backend-only this phase).
- Multi-object tracking across frames.
