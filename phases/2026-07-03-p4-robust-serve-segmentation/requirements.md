# Phase P4 — Robust Automatic Multi-Stage Serve Segmentation — Requirements

> **Auto-selected decisions note:** the four Key Decisions below were surfaced via `AskUserQuestion`
> with a recommended option each; no response was received in time, so the recommended option was
> taken for all four (noted per-row). Review before `/phase` and say so if any should change.

## Scope

Extend `backend/app/engine/phases.py`'s `detect_phases` from the current 3-frame model
(trophy pose, racket drop, contact) to the full 6-frame Kovacs model (Start, Release, Loading/trophy
pose, Cocking/racket drop, Contact, Finish), combining the off-device 2D pose signal (P1) with the
racket-detection signal (P2) — the two signals Phase 6 concluded were both necessary and which
on-device Vision could not reliably provide together. This is backend-only, developer-tooling-adjacent
work: no new iOS surface, no `/v1/analyze` caller yet (that's P6), and no change to any Lite-mode file.

## In Scope

- **`ServePhase` enum** (`backend/app/models.py`) gains three new members: `start`, `release`, `finish`,
  alongside the existing `trophy_pose`, `racket_drop`, `contact`.
- **`detect_phases` signature extended** to
  `detect_phases(frames: list[Frame], detections: list[list[Detection]] | None = None) -> dict[ServePhase, Frame | None]`.
  `detections[i]` (if provided) is the list of `Detection` objects for `frames[i]`, aligned by index —
  mirrors how `frames` and `detections` are already produced in lockstep by `/v1/pose` and `/v1/detect`
  sampling the same frame stream. `None`/omitted stays fully backward compatible with existing 3-phase
  callers and tests.
- **Six-frame heuristics:**
  - `start`: `frames[0]` — the input array is already a single boundary-trimmed serve (this phase does
    not add multi-serve splitting; see Out of Scope), so the first frame *is* the ready-stance frame by
    construction.
  - `release`: the earliest frame where the toss wrist rises above the toss shoulder
    (`toss_wrist_y > toss_shoulder_y`) — reuses the existing trophy-pose sub-condition but takes the
    first match in time rather than requiring the full trophy-pose gate.
  - `trophy_pose` (Loading): unchanged existing heuristic.
  - `racket_drop` (Cocking): existing elbow-y-rise heuristic, **augmented** with the racket bounding-box
    signal when `detections` is provided — see Key Decisions for the exact combination rule.
  - `contact`: unchanged existing heuristic.
  - `finish`: `frames[-1]` — the last frame of the trimmed serve array.
- **`AnalyzeRequest` (`backend/app/models.py`) gains an optional `detections: list[list[Detection]] | None = None`
  field**, and `analyze.py`'s handler passes it through to `detect_phases`. No iOS caller sets this field
  yet (P6 is the first caller); this only prepares the contract.
- **New tool `backend/tools/segmentation_report.py`** — runs the real, unmodified `RTMPoseModel` (P1) and
  `ObjectDetectionModel` (P2) against each `backend/tools/calibration_data/*.mov` video (reusing
  `pose_benchmark.py`'s `sample_video_frames`), runs the new 6-frame `detect_phases` over the resulting
  per-video frame/detection sequence, and produces a gitignored HTML report highlighting all six detected
  phase frames per video (extending `calibration_report.py`'s highlight-row pattern from 3 labels to 6,
  reusing `_img_tag` and the page CSS by import). `calibration_report.py` itself is left untouched — it
  remains the separate, still-valid Lite-mode (on-device-Vision-console-log, 3-phase) tool.
- **Unit tests** (`backend/tests/test_phases.py`) for the three new phases and the racket-augmented
  `racket_drop` heuristic, following the existing `make_frame`/`TROPHY_KPS` fixture style.
- **Manual, opt-in re-validation** against the four real serve videos in `calibration_data/` — visual
  spot-check via the new tool's HTML report, following Phase 6's and P3's precedent of no formal ground
  truth (deferred to P18).

## Out of Scope

- **Multi-serve boundary splitting** (segmenting one continuous recording into multiple individual
  serves). *(Key Decision — recommended option auto-selected: no response received.)* Nothing off-device
  does this today; it's deferred to whenever P7's continuous Set-Goal session actually needs it. All four
  real calibration videos are already one-serve-per-file, so this phase's re-validation doesn't require it
  either.
- **Ball-detection signal.** P3's baseline showed a 10.8% ball-detection rate vs. 74.1% for racket — too
  unreliable to use as a phase-detection signal yet. Only racket detections feed the new heuristics.
- **Rule calibration / `rules.json` changes** for the three new phases — that's P5's job, once real
  2D-measured angles exist for Start/Release/Finish.
- **Wiring `/v1/analyze` into the iOS app, or the mode-selector UI** — both are P6.
- **Any change to `RTMPoseModel`, `ObjectDetectionModel`, or `calibration_report.py`.** This phase only
  consumes those services and adds a new, separate tool.
- **Rigorous ground-truth accuracy metrics for the new phases** (deferred to P18, consistent with P3's
  precedent).
- **Any iOS work.** `git diff --name-only develop...HEAD` must show zero changes under `App/`.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| P4 scope: single-serve vs. multi-serve splitting | Single-serve, 6-frame phase detection only | *(Auto-selected, recommended option — no user response.)* Matches the roadmap's literal text ("extends phases.py from 3 to 6 detected frames"); all real calibration videos are already one-serve-per-file; multi-serve splitting has no current caller or need. |
| Racket signal integration | `detect_phases` gains an optional `detections` param; `racket_drop` heuristic is racket-bbox-augmented; `AnalyzeRequest`/`/v1/analyze` gain a forward-compatible optional `detections` field | *(Auto-selected, recommended option — no user response.)* Phase 6's pivot note called racket position "critical for accurate phase classification"; P3's baseline confirms racket detection is reliable (74.1% detection rate, tight boxes) unlike ball (10.8%). |
| Racket-augmented `racket_drop` combination rule | When `detections` is provided and at least one frame in the trophy→contact window has a racket detection, prefer the frame where the racket bounding-box *center y* is lowest (racket at its most-dropped point) among frames with a racket detection; fall back to the existing elbow-y-rise heuristic when no racket detection exists in that window (`detections` omitted, or none present) | Keeps the existing, already-calibrated (Phase 6) elbow-y-rise heuristic as the guaranteed fallback so pose-only callers and existing tests are unaffected, while giving the racket signal priority when available, per the Key Decision above. Exact frame-selection logic is detailed in `spec.md`. |
| New-stage (Start/Release/Finish) heuristic style | Positional: `start = frames[0]`, `finish = frames[-1]`, `release` = earliest toss-wrist-above-shoulder frame | *(Auto-selected, recommended option — no user response.)* Matches the complexity level of the existing 3-frame heuristic; deterministic and unit-testable; consistent with the "single-serve, already-trimmed input" scope decision above. Velocity-based motion analysis was considered but rejected as a bigger lift and closer to the approach Phase 6 already concluded was unreliable alone. |
| Re-validation tooling | New `backend/tools/segmentation_report.py`, reusing `pose_benchmark.py`'s frame sampling and `calibration_report.py`'s `_img_tag`/CSS via import; `calibration_report.py` itself unchanged | *(Auto-selected, recommended option — no user response.)* Avoids conflating the Lite-mode (on-device-Vision-console-log input, 3-phase) tool with the new Pro-mode (off-device-model, video-only input, 6-phase) workflow — mirrors P3's precedent of a new tool importing shared helpers rather than mutating an existing one. |

## Context

- Phase P1 built `RTMPoseModel` (`POST /v1/pose`) and Phase P2 built `ObjectDetectionModel`
  (`POST /v1/detect`, racket + ball) — both dormant, unit-tested services with no in-app caller yet.
  Phase P3 established a quantitative baseline confirming both are reliable enough for this phase to
  build on: 100% person detection, 74.1% racket detection, 10.8% ball detection, across real footage.
- `backend/app/engine/phases.py`'s existing `detect_phases` (3-frame: trophy pose, racket drop, contact)
  was built in Phase 4 and calibrated against real footage in Phase 6 — that calibration outcome is what
  triggered the Lite/Pro pivot: on-device Vision couldn't reliably provide racket position, which Phase 6
  concluded was critical for accurate phase classification. This phase is the first to combine pose +
  racket signals for that reason.
- `backend/app/engine/rules.py`'s `evaluate_rules` already looks up `phase_frames.get(rule.phase)` per
  rule and skips missing phases — adding new `ServePhase` members with no corresponding `rules.json`
  entries yet is safe and requires no `rules.py` change.
- `backend/tools/calibration_data/` holds four real serve videos, each already one serve per file (three
  have exactly one `Serve 1/1` console-log entry; `serve_4.mov` has two) — the same footage P3's benchmark
  ran against, gitignored and local-only.
- **Three-mode product architecture:** per `specs/mission.md`'s isolation rule, this phase's code is
  Pro-2D/3D-only and additive. It must not modify `PhaseReviewView`, the Lite pipeline/segmentation
  services, or `ContentView`. Lite mode's on-device 3-phase flow and its own serve-boundary detection
  (Phase 2, Swift) are untouched — this phase only extends the backend's dormant `phases.py`, which Lite
  never calls.
