# Phase P4 — Robust Automatic Multi-Stage Serve Segmentation — Requirements

## Scope

Extend `backend/app/engine/phases.py` with two capabilities, both combining the off-device 2D pose
signal (P1) with the racket/ball-detection signal (P2) — the pairing Phase 6 concluded on-device Vision
could not reliably provide:

1. **Multi-serve boundary splitting** — a new `segment_serves` function that splits one continuous
   recording's frame sequence into per-serve sub-sequences, needed for the Assessment (P6) and Set Goal
   (P7) continuous-recording workflows.
2. **Six-frame phase detection** — `detect_phases` extended from the current 3-frame model (trophy pose,
   racket drop, contact) to the full 6-frame Kovacs model (Start, Release, Loading/trophy pose,
   Cocking/racket drop, Contact, Finish), run per serve segment.

This is backend-only, developer-tooling-adjacent work: no new iOS surface, no `/v1/analyze` caller yet
(that's P6), and no change to any Lite-mode file. **This phase's heuristics are expected to need real-footage
iteration** (per Phase 6's precedent) — several thresholds are exposed as named, tunable module constants
specifically so Group 5 (manual re-validation) can adjust them against real serves without touching test
logic.

## In Scope

- **`ServePhase` enum** (`backend/app/models.py`) gains three new members: `start`, `release`, `finish`,
  alongside the existing `trophy_pose`, `racket_drop`, `contact`.
- **New `segment_serves(frames: list[Frame]) -> list[list[Frame]]`** in `phases.py` — splits a continuous
  frame sequence into per-serve sub-lists using frame-to-frame pose-keypoint velocity, normalized by each
  frame's real `timestamp` delta (units/second, not units/frame-step) so the heuristic is invariant to the
  source video's frame rate. A serve boundary is declared after a sustained low-velocity ("rest") window
  spanning at least `MIN_REST_SECONDS` of real time that is preceded by genuine motion (so leading/trailing
  idle padding at the very start/end of the clip is never split off as its own empty "serve").
  `MIN_REST_SECONDS` and `LOW_MOTION_VELOCITY_THRESHOLD` are named, tunable module constants. This is a
  dormant, unit-tested service-layer function — no in-app caller yet, matching P1's precedent for
  introducing capabilities ahead of their eventual (P6/P7) wiring.
- **`detect_phases` signature extended** to
  `detect_phases(frames: list[Frame], detections: list[list[Detection]] | None = None) -> dict[ServePhase, Frame | None]`,
  operating on one serve's frames (i.e., one element of `segment_serves`'s output, or any pre-segmented
  single-serve list as today). `detections[i]` (if provided) is the list of `Detection` objects for
  `frames[i]`, aligned by index. `None`/omitted stays fully backward compatible with existing 3-phase
  callers and tests.
- **Six-frame heuristics:**
  - `release`: the first frame where a detected **ball** is above the toss hand, *if the ball is ever
    detected anywhere in the sequence*; otherwise falls back to the original heuristic (earliest frame
    where `toss_wrist_y > toss_shoulder_y`). Degrades gracefully given P3's baseline 10.8% ball-detection
    rate.
  - `start`: the frame with the lowest toss-wrist height (`argmin(toss_wrist_y)`) searched over
    `frames[0:release_idx]` (or `frames[0:trophy_idx]` if `release` didn't resolve) — mirrors the existing
    `argmax` pattern already used for `contact`, marking the bottom of the toss backswing right before the
    arm begins its ascent.
  - `trophy_pose` (Loading): unchanged existing heuristic.
  - `racket_drop` (Cocking): existing elbow-y-rise signal **combined** with the racket bounding-box signal
    (not a fallback-only relationship) — see Key Decisions for the exact scoring rule.
  - `contact`: unchanged existing heuristic.
  - `finish`: the frame with the lowest **front (leading) foot** height (`argmin` of the toss-side ankle —
    opposite the hitting arm — searched over `frames[contact_idx+1:]`), falling back to the last frame if
    no post-contact ankle data exists.
- **`AnalyzeRequest` (`backend/app/models.py`) gains an optional `detections: list[list[Detection]] | None = None`
  field**, and `analyze.py`'s handler passes it through to `detect_phases`. No iOS caller sets this field
  yet (P6 is the first caller); this only prepares the contract.
- **New tool `backend/tools/segmentation_report.py`** — runs the real, unmodified `RTMPoseModel` (P1) and
  `ObjectDetectionModel` (P2) against each `backend/tools/calibration_data/*.mov` video (reusing
  `pose_benchmark.py`'s `sample_video_frames`), calls `segment_serves` on the resulting frame/detection
  sequence, runs the new 6-frame `detect_phases` over each resulting serve segment, and produces a
  gitignored HTML report with one section per detected serve, each showing all six phase frames
  (extending `calibration_report.py`'s per-serve, per-phase highlight-row pattern — which already handles
  multiple serves per video — from 3 labels to 6, reusing `_img_tag` and the page CSS by import).
  `calibration_report.py` itself is left untouched.
- **Unit tests** for `segment_serves`, the three new phase heuristics (including their fallback paths),
  and the combined-signal `racket_drop`, following the existing `make_frame`/`TROPHY_KPS` fixture style.
- **Manual, opt-in, iterative re-validation** against the real serve videos in `calibration_data/` —
  none of the original four calibration videos actually contain more than one serve (`serve_4.mov`'s
  console log logs two segments, `Serve 1/2`/`Serve 2/2`, but that's on-device Vision's own segmentation
  over-splitting a single real serve — confirmed against the actual footage, not reliable ground truth).
  The user is adding dedicated multi-serve videos specifically to stress-test `segment_serves`, each with a
  known expected serve count supplied when the video is added. Following Phase 6's precedent, this group
  expects to *tune* the new module constants against what the
  reports show, not just observe them once. New videos need no companion `_console.txt` (that format is
  Lite-mode-only, for `calibration_report.py`) — `segmentation_report.py` runs the off-device pose/detection
  models directly on the video, so any `*.mov`/`*.MOV` dropped into `calibration_data/` is picked up
  automatically by the tool's existing default glob, no code change required.

## Out of Scope

- **Ball-detection signal for anything except `release`.** `racket_drop` never considers ball detections;
  `segment_serves` uses pose velocity only, not object detections.
- **Rule calibration / `rules.json` changes** for the three new phases — that's P5's job, once real
  2D-measured angles exist for Start/Release/Finish.
- **Wiring `/v1/analyze`, `segment_serves`, or the mode-selector UI into the iOS app** — all P6/P7.
- **Any change to `RTMPoseModel`, `ObjectDetectionModel`, or `calibration_report.py`.** This phase only
  consumes those services and adds a new, separate tool.
- **Rigorous ground-truth accuracy metrics for the new phases or for `segment_serves`'s boundary accuracy**
  (deferred to P18, consistent with P3's precedent).
- **Any iOS work.** `git diff --name-only develop...HEAD` must show zero changes under `App/`.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Multi-serve splitting: in scope | `segment_serves(frames) -> list[list[Frame]]`, new dormant function in `phases.py` | User correction: needed for the Assessment (P6) workflow, which the roadmap explicitly ties to "automatic per-serve detection (P4)." None of the original four calibration videos are actually multi-serve, so the user is adding dedicated multi-serve footage for this phase's real-footage validation. |
| Serve-boundary detection approach | Frame-to-frame pose-keypoint velocity; split after a sustained low-velocity window (`MIN_REST_SECONDS`) that follows genuine motion | User-selected over "return-to-ready-stance detection" — velocity-based splitting doesn't couple to the `start` heuristic's own definition, and is more general-purpose (works even if a player's ready stance varies serve to serve). |
| Velocity/rest-window units: time-based, not frame-count-based | `_frame_velocity` normalizes displacement by each pair of frames' real `timestamp` delta (units/second); `MIN_REST_SECONDS` measures cumulative real time of a rest run, not a raw frame count | User correction, prompted by adding `vesa_slow_mo.mov` (confirmed ~58.4 fps vs. ~30 fps for the other calibration videos — genuinely slow-motion, not just a name). A frame-count-based threshold would need separate tuning per frame rate; time-based normalization uses `Frame.timestamp` (already populated by `sample_video_frames`) to make the same constants valid across both. |
| `racket_drop` combination rule | Weighted combination, not fallback-only: normalize the elbow-y-rise signal and the racket-bbox-center-y signal (inverted, since lower = more dropped) across the trophy→contact window, then pick the frame maximizing a weighted average of whichever signals are available for it. `RACKET_DROP_ELBOW_WEIGHT` / `RACKET_DROP_RACKET_WEIGHT` (default 0.5/0.5) are named, tunable constants. With `detections=None`, the racket term is never available for any frame, so the result reduces to the original elbow-only ranking — fully backward compatible. | User correction: combine both signals rather than racket-first-fallback-to-elbow, since neither signal alone is fully reliable (P3: 74.1% racket detection, and the pre-existing elbow heuristic was only ever calibrated against on-device Vision, without racket data at all). |
| `finish` foot selection | Front (leading) foot — the toss-side ankle (opposite the hitting arm; `left_ankle` for the current `HANDEDNESS["hitting"] == "right"`) | User-selected. Matches the Kovacs model's "front-foot landing" description and standard serve biomechanics, rather than the literal (hitting-side) right foot. |
| `release` ball-detection handling | Ball-detection primary (first frame where a detected ball's bbox is above the toss hand), toss-wrist-rise fallback when the ball is never detected anywhere in the sequence | User-selected. Degrades gracefully given P3's confirmed 10.8% ball-detection rate — most serves will likely use the fallback path today, but the primary path activates automatically as ball-detection quality improves later. |
| `start` heuristic | `argmin(toss_wrist_y)` searched over `frames[0:release_idx]` (or `frames[0:trophy_idx]` if `release` is unresolved) | User-selected over velocity-sign-change detection. Mirrors the existing `argmax` pattern already used for `contact`; deterministic and unit-testable; avoids the velocity-only approach Phase 6 already concluded was unreliable alone. |
| Re-validation tooling | New `backend/tools/segmentation_report.py`, reusing `pose_benchmark.py`'s frame sampling and `calibration_report.py`'s `_img_tag`/CSS/per-serve-sectioning pattern via import; `calibration_report.py` itself unchanged | Avoids conflating the Lite-mode (on-device-Vision-console-log input, 3-phase) tool with the new Pro-mode (off-device-model, video-only input, 6-phase, multi-serve) workflow — mirrors P3's precedent of a new tool importing shared helpers rather than mutating an existing one. |
| Iterative tuning is an explicit part of Group 5 | `MIN_REST_SECONDS`, `LOW_MOTION_VELOCITY_THRESHOLD`, `RACKET_DROP_ELBOW_WEIGHT`, `RACKET_DROP_RACKET_WEIGHT` are named module constants in `phases.py`, tuned during the manual real-footage run rather than fixed a priori | User noted iteration will likely be needed to "nail down rules" — mirrors Phase 6's own precedent of adjusting heuristics against real footage until they visually hold up. |

## Context

- Phase P1 built `RTMPoseModel` (`POST /v1/pose`) and Phase P2 built `ObjectDetectionModel`
  (`POST /v1/detect`, racket + ball) — both dormant, unit-tested services with no in-app caller yet.
  Phase P3 established a quantitative baseline confirming both are reliable enough for this phase to
  build on: 100% person detection, 74.1% racket detection, 10.8% ball detection, across real footage.
- `backend/app/engine/phases.py`'s existing `detect_phases` (3-frame: trophy pose, racket drop, contact)
  was built in Phase 4 and calibrated against real footage in Phase 6 — that calibration outcome is what
  triggered the Lite/Pro pivot: on-device Vision couldn't reliably provide racket position, which Phase 6
  concluded was critical for accurate phase classification. This phase is the first to combine pose +
  racket signals for that reason, and the first to attempt automatic serve-boundary splitting off-device.
- `backend/app/engine/rules.py`'s `evaluate_rules` already looks up `phase_frames.get(rule.phase)` per
  rule and skips missing phases — adding new `ServePhase` members with no corresponding `rules.json`
  entries yet is safe and requires no `rules.py` change.
- `backend/tools/calibration_data/` holds four original real serve videos, gitignored and local-only — the
  same footage P3's benchmark ran against. All four are actually single-serve: three contain a single
  `Serve 1/1` console-log entry; `serve_4.mov`'s console log shows two (`Serve 1/2`, `Serve 2/2`), but that
  reflects on-device Vision's own segmentation over-splitting one real serve into two logged segments, not
  an actual second serve (confirmed against the footage) — a small, concrete illustration of exactly the
  on-device segmentation unreliability Phase 6 already concluded, and a reminder that these console logs
  are Vision's own guess, not ground truth. `calibration_report.py`'s existing `generate_html` already
  sections its report per-serve (built for multi-serve-per-video cases in general, using on-device Vision's
  own boundary detection) — `segmentation_report.py` follows the same per-serve sectioning convention, but
  with boundaries produced by the new off-device `segment_serves` instead.
- The user added two further videos to `calibration_data/` specifically because none of the original four
  are actually multi-serve, and `segment_serves` needs real multi-serve footage to prove out against:
  `ag_three_serves.MOV` (expected 3 serves, ~30 fps) and `vesa_slow_mo.mov` (expected 1 serve, confirmed
  ~58.4 fps — genuinely slow-motion, not just a name, vs. ~30 fps for every other calibration video).
  Discovering the real fps difference is what prompted the time-based (not frame-count-based) redesign of
  `segment_serves` above. All videos' expected counts are recorded in `validation.md`'s expected-vs-actual
  table.
- **Three-mode product architecture:** per `specs/mission.md`'s isolation rule, this phase's code is
  Pro-2D/3D-only and additive. It must not modify `PhaseReviewView`, the Lite pipeline/segmentation
  services, or `ContentView`. Lite mode's on-device 3-phase flow and its own serve-boundary detection
  (Phase 2, Swift) are untouched — this phase only extends the backend's dormant `phases.py`, which Lite
  never calls.
