# Phase P3 — CV Model Performance Baseline (2D) — Requirements

## Scope

Establish a reusable, quantitative performance baseline for Phase P1's pose model (`RTMPoseModel`) and
Phase P2's object detector (`ObjectDetectionModel`) against real tennis serve footage, before Phase P4
combines their signals into six-frame segmentation logic. The goal is to make it possible to tell "the CV
is inaccurate" apart from "the segmentation heuristic is wrong" once P4 lands, and to give any future model
swap (e.g. a fine-tuned YOLO, or a different pose backbone) a fixed reference point to beat. This is a
developer-tooling phase — no new API endpoint, no iOS surface, no changes to existing services.

## In Scope

- **New tool `backend/tools/pose_benchmark.py`** — samples frames from every `backend/tools/calibration_data/*.mov`
  video at a configurable stride, runs each sampled frame through the *existing, unmodified* `RTMPoseModel`
  (P1) and `ObjectDetectionModel` (P2) instances, and records per-frame results.
- **`--stride` CLI flag** (default `5`) controlling how many raw video frames are skipped between benchmark
  samples. Decoupled from any iOS-side constant (none currently exists to mirror).
- **Per-frame metrics captured:**
  - `person_detected` — `RTMPoseModel.infer()` returned a non-empty keypoints dict.
  - Per-keypoint confidence values for all detected keypoints (feeds an average-confidence aggregate).
  - `racket_detected` / `ball_detected` — `ObjectDetectionModel.infer()` returned at least one `Detection`
    with that label (already filtered by the model's own `confidence_threshold`, default `0.25`).
  - Confidence of the racket/ball detection when present.
  - Pose inference latency and object-detection inference latency (wall-clock, seconds per frame) — feeds
    an average-FPS aggregate for each model independently.
- **Visual HTML overlay report** (gitignored, written under `backend/tools/calibration_data/<video>_benchmark/`
  alongside the source footage — same "developer-tool output next to its source" convention as
  `calibration_report.py`'s `<video>_report/` dirs): each extracted JPEG thumbnail gets the detected pose
  skeleton drawn on top (keypoints above `MIN_CONFIDENCE` as dots, connected by straight lines along a fixed
  limb-pair list where both endpoints are present) and racket/ball bounding boxes drawn as colored rectangles,
  for human spot-check of CV quality. Reuses `calibration_report.py`'s frame-extraction (`extract_video_frame`)
  and HTML-scaffolding helpers (`_img_tag`, the page wrapper/CSS) via import rather than duplicating them.
- **Small, git-tracked numeric summary** written per run to
  `backend/tools/pose_benchmark_baselines/<YYYY-MM-DD-HHMMSS>.json` — aggregate stats only (no images, no
  video, no per-frame raw dumps): per-video and overall detection rates (person/racket/ball), average
  keypoint confidence, average racket/ball confidence, average pose FPS, average detection FPS. Each run adds
  a new timestamped file; history accumulates rather than being overwritten, so past baselines remain
  available for trend comparison.
- **Default `pytest` suite** (`backend/tests/test_pose_benchmark.py`) using synthetic fixtures exactly like
  `test_calibration_report.py`: a tiny generated video plus stub pose/detection model objects (no real
  RTMPose/YOLO model load) — fast and deterministic, runs as part of `scripts/verify.sh backend`.
- **Manual, opt-in real-footage run** against the four real serve videos in `backend/tools/calibration_data/`
  (from Phase 6, gitignored, local-only, no new recording needed) — its output becomes the first committed
  baseline entry, recorded in this phase's `validation.md` notes.

## Out of Scope

- **Rigorous ground-truth accuracy metrics** (PCK for pose, mAP/IoU for object detection) — explicitly
  deferred to Phase P18, which adds hand-labeled annotations. P3 is detection-rate/confidence/FPS only, no
  ground truth required — matching Phase 6's precedent of visual comparison over labeled accuracy.
- **Any change to `RTMPoseModel`, `ObjectDetectionModel`, `backend/app/engine/phases.py`, or `rules.json`.**
  This phase only measures the existing P1/P2 services; it does not tune, retrain, or modify them.
- **Combining pose + object-detection signals into segmentation logic** — that is Phase P4's job. P3 only
  produces the diagnostic baseline P4 will be validated against.
- **Automated regression gating / CI comparison against the baseline.** The "continuous CV model improvement
  loop" described in `specs/mission.md` is explicitly deferred and not scheduled; this phase only produces the
  raw baseline artifact such a loop would eventually consume.
- **Multi-person handling** beyond what `RTMPoseModel.infer()` already does (first detected body only, per
  `rtmlib.Body`'s own behavior) — not this phase's concern to change.
- **Any iOS work or new `/v1` endpoint.** This is a developer CLI tool, not a network-facing API; nothing in
  the app calls it.
- **Fine-tuning YOLO or swapping either model** — P2 explicitly deferred fine-tuning until real-footage
  detection quality is assessed; this phase produces that assessment but does not act on it.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Overlay style | Draw skeleton (dots + limb lines) and detection bounding boxes directly onto each extracted JPEG thumbnail | More useful for visually judging whether a bounding box is actually on the racket / whether keypoints track the body correctly than text-only captions; user confirmed this is worth the extra drawing code over `calibration_report.py`'s simpler text-caption precedent. |
| Baseline file location & history behavior | `backend/tools/pose_benchmark_baselines/<YYYY-MM-DD-HHMMSS>.json`, one new file per run, git-tracked, history accumulates (never overwritten) | Lets future model/approach swaps compare against any prior run, not just the most recent; user chose history-preservation over a single overwritten "current" file. Lives outside the gitignored `backend/tools/calibration_data/` directory so it's actually committed. |
| Frame sampling stride | `--stride` CLI flag, default `5` | No existing iOS-side sampling constant to mirror (checked — none found in `App/`); a CLI flag lets the benchmark be re-run at a finer or coarser stride without code changes. |
| Detection-rate criteria | `person_detected` = pose model returned any keypoint at all; `racket_detected`/`ball_detected` = detection model returned an entry with that label (both already gated by each model's own confidence handling — `MIN_CONFIDENCE` for keypoint-level angle math is a separate, downstream threshold reused only for the overlay's skeleton-drawing cutoff) | Keeps "detected" simple and consistent with what each model already reports; avoids introducing a third, benchmark-specific confidence threshold that would need its own justification. |
| Reuse vs. duplicate `calibration_report.py` helpers | Import `extract_video_frame`, `_img_tag`, and the HTML page wrapper/CSS from `calibration_report.py` rather than copy-pasting them | Roadmap explicitly calls for reusing "calibration_report.py's frame-extraction and HTML-report-generation helpers"; importing keeps one source of truth for the shared report-scaffolding look. |
| Test isolation | Default `pytest` suite passes stub pose/detection model objects (matching `test_object_detection.py`'s and P1's dependency-override pattern) — no real `RTMPoseModel`/`ObjectDetectionModel` construction in the default suite | `scripts/verify.sh backend` must stay fast and network/weight-download-independent; mirrors P1/P2's exact precedent for keeping heavy model loads out of the default test run. |
| Real-footage run cadence | Manual, opt-in, run by hand whenever a baseline refresh is wanted — not wired into `scripts/verify.sh` or CI | Matches the roadmap's explicit framing ("a manual, opt-in step whose output becomes the committed baseline") and Phase P2's precedent for its `RUN_MODEL_INTEGRATION_TESTS`-gated real-model check. |

## Context

- Phase P1 built `RTMPoseModel` (2D pose, `POST /v1/pose`) and Phase P2 built `ObjectDetectionModel`
  (racket/ball, `POST /v1/detect`) — both are lazily-loaded, dormant Pro-mode services with no in-app caller
  yet. This phase is the first time both are exercised together against real footage.
- `backend/tools/calibration_data/` holds four real serve videos (`serve_1.MOV` … `serve_4.mov`, gitignored,
  local-only) and their Phase 6 calibration reports — the same footage this phase's manual run reuses, no new
  recording needed.
- `backend/tools/calibration_report.py` established the "developer tool takes local footage → produces a
  gitignored HTML report for visual spot-check" pattern this phase follows, plus its own precedent of a
  synthetic-fixture-only default test suite (`test_calibration_report.py`) with real-data checks kept manual.
- `specs/roadmap.md`'s P3 entry explicitly requires: no ground truth, a gitignored visual report, a small
  git-tracked numeric summary as "the reference point for evaluating candidate model or approach swaps
  later," and a synthetic-fixture default test suite mirroring `test_calibration_report.py`.
- **Three-mode product architecture:** this phase is purely Pro 2D/3D-pipeline diagnostic tooling — it has no
  Lite-mode or iOS surface at all, consistent with `specs/mission.md`'s isolation rule that off-device
  pose/detection work must never touch the Lite path.
