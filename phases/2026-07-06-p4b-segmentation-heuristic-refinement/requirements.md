# Phase P4b — Segmentation Heuristic Refinement — Requirements

> **Note:** one clarifying question about the `contact` fix went unanswered; the recommended
> synthesis of the evidence gathered (see Context) was taken — flagged in the Key Decisions
> table below. Review before `/phase` and say so if it should change.

## Scope

Iterate on P4's six-frame segmentation and phase-detection heuristics against real footage,
before P5 calibrates rule thresholds against them. This phase does **not** change the six-frame
model's shape, the `ServePhase` enum, `segment_serves`'s time-based design, or anything outside
the Pro 2D/3D pipeline — it revisits the *accuracy* of existing heuristics and tunable constants,
not the architecture P4 established.

## In Scope

- **Constant re-tuning** — re-run the `MIN_REST_SECONDS`/`LOW_MOTION_VELOCITY_THRESHOLD`/
  `RACKET_DROP_ELBOW_WEIGHT`/`RACKET_DROP_RACKET_WEIGHT` grid-search-style tuning process against
  the existing 6 calibration videos plus any additional videos added during this phase (following
  P4's precedent — no video count is fixed in advance).
- **`segmentation_report.py`'s default `--stride`** — lower it (exact value determined during
  Group 1's investigation, informed by real footage) so fast real swings get more intermediate
  sampled frames between Cocking and Contact. Confirmed root cause on `ag_three_serves.MOV`: the
  entire Cocking→Contact motion for two of its three serves fell within a single `stride=5` sample
  step (~0.17s of real time), leaving zero frames for `racket_drop` to select from and likely
  costing `contact` some precision too.
- **`contact`'s heuristic** — investigate a more robust signal than pure peak-wrist-height search.
  Visual evidence (see Context) shows the current heuristic's pick is *close* but not exact, and
  it never uses the racket/ball detection signal despite it being available since P2. A
  racket/ball-bbox-proximity signal (contact ≈ when the racket and ball bounding boxes are
  closest, or overlapping) is the leading candidate; the exact design is Group 1's job, not
  pre-specified here.
- **`trophy_pose`'s heuristic** — investigate whether the existing elbow-angle-range condition
  (unchanged since Phase 4/6) is firing on the right frame across different serve styles/camera
  angles. Visual evidence (see Context) shows it selecting a frame further into the motion (closer
  to Cocking) than the classic "trophy pose" position on at least two videos.
- **`racket_drop`'s search window** — once `trophy_pose`/`contact` are re-validated, confirm
  whether the combined-signal heuristic from P4 still needs a structural change (e.g. handling an
  empty `trophy_idx+1..contact_idx` range) or whether the `--stride`/heuristic fixes above resolve
  it incidentally.
- **`start`/`release`/`finish`** — full visual spot-check across all 6 (or more) videos, since P4
  only spot-checked 2–3. Heuristic changes only if the spot-check surfaces a real problem — these
  are not assumed broken going in.
- **Manual, iterative re-validation** — same hard-merge-gate pattern as P4's Group 5: run
  `segmentation_report.py`, inspect real output, tune, repeat.
- **Ground-truth phase timestamps + a regression test.** As part of the manual re-validation, hand
  -author `backend/tools/segmentation_ground_truth.json` — the expected serve count per video and,
  per serve, a real-world timestamp (in seconds) for each of the six phases, determined by visually
  inspecting the calibration footage. A new opt-in test (gated the same way as P1/P2's
  `RUN_MODEL_INTEGRATION_TESTS`-flagged integration tests, since it needs real models and the
  gitignored local video files) runs the real pipeline against every video and asserts each
  detected phase frame's timestamp falls within a tolerance of the recorded ground truth. This is
  **not** P18's rigorous per-keypoint PCK/mAP accuracy work — it's six timestamps per serve, meant
  to catch future regressions to the phase-detection heuristics this phase is tuning, not to
  produce a general CV accuracy benchmark.

## Out of Scope

- **The six-frame model's shape, `ServePhase` enum, or `segment_serves`'s time-based design.**
  This phase tunes accuracy, not architecture.
- **Rule calibration / `rules.json` changes** — still P5's job, and depends on this phase landing
  first so P5 calibrates against accurate phase frames.
- **Wiring `/v1/analyze`, `segment_serves`, or the mode-selector into the iOS app** — still P6/P7.
- **Rigorous ground-truth accuracy metrics** (PCK/mAP) — still deferred to P18.
- **Any iOS work.** `git diff --name-only develop...HEAD` must show zero changes under `App/`.
- **Changing `RTMPoseModel`, `ObjectDetectionModel`, or `calibration_report.py`.**

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Video set | Existing 6 calibration videos, with room to add more mid-phase (matches P4's precedent) | User confirmed no new footage is ready yet; the phase should still absorb videos added during iteration rather than assuming a fixed set. |
| `racket_drop`'s adjacent-frames gap on `ag_three_serves.MOV` | Both a denser default `--stride` *and* a more robust `contact` signal (racket/ball proximity, not just peak wrist height) | *(Auto-selected — a follow-up clarifying question went unanswered.)* User's initial diagnosis was "contact landing on the wrong frame." Direct visual inspection of frames052–054 shows `contact` (frame053) is actually close — racket approaching the ball, not yet struck, with frame054 one sample later already in full follow-through — so the primary driver is sampling density (the whole Cocking→Contact motion fit in one `stride=5` step), not a badly wrong `contact` pick. Synthesizing both: fix the immediate sampling gap *and* make `contact` less dependent on a single proxy metric (peak wrist height can be fooled by other elevated-arm moments in a longer sequence), since the racket/ball detection signal already exists and currently goes unused for `contact`. |
| `trophy_pose` in scope | Yes — investigate and revise if warranted | User confirmed. Visual evidence from both `ag_three_serves.MOV` (frame052) and `vesa_slow_mo.mov` (frame028) shows the current heuristic selecting a frame that looks more like early Cocking (racket already up near the head, reaching toward the ball) than the classic Loading/trophy position — a pattern across two different videos, not an isolated camera-angle quirk. |
| `start`/`release`/`finish` validation depth | Full visual spot-check across all videos this phase | User selected the recommended option — these heuristics are brand new in P4 and were only spot-checked on 2–3 of 6 videos; this phase is specifically about heuristic quality, so extending the check is low-cost and high-signal before P5 builds on top. |
| `trophy_pose` concrete fix | Add a new required condition: hitting elbow at or below hitting-shoulder height (`hitting_elbow_y <= hitting_shoulder_y`) | Derived from cross-video investigation during this spec: computing the current heuristic's picked frame's elbow/shoulder relationship across all 6 videos showed this condition is `False` only for the 2 broken `ag_three_serves.MOV` picks and `True`/borderline-equal for every other video — a clean, cheap discriminator using the same simple-geometric-comparison style already used throughout `detect_phases`. User confirmed. |
| `contact` concrete fix | Add a racket-ball bounding-box proximity signal, combined with the existing wrist-height signal via the same weighted-normalization pattern P4 established for `racket_drop` (new `CONTACT_WRIST_WEIGHT`/`CONTACT_PROXIMITY_WEIGHT`, default 0.5/0.5) | User confirmed. Directly uses the racket/ball detection signal for `contact` for the first time; backward compatible (reduces to today's wrist-height-only ranking when `detections=None`). |
| Deterministic tie-breaking | Iterate `racket_drop`'s and the new `contact`'s combined-signal candidate loops in `sorted()` order, not raw `set()` order | User confirmed including this alongside the stride fix. Closes a low-severity non-determinism finding flagged in P4's correctness review (Python `set` iteration order over ints is not a language guarantee) while this exact code shape is already being touched twice more. |
| Ground-truth regression test | Hand-author `backend/tools/segmentation_ground_truth.json` (per-serve, per-phase expected timestamps) plus a new opt-in test gated like P1/P2's `RUN_MODEL_INTEGRATION_TESTS` integration tests | User's explicit request — this phase's heuristic changes should leave behind a concrete, automatable check so future phases don't regress phase-detection accuracy without noticing, without conflating this with P18's full PCK/mAP rigor. |

## Context

- Phase P4 built the six-frame model (`start`, `release`, `trophy_pose`, `racket_drop`, `contact`,
  `finish`) and `segment_serves`, tuning `MIN_REST_SECONDS=0.4`/`LOW_MOTION_VELOCITY_THRESHOLD=0.03`
  against the same 6 real calibration videos this phase uses. `trophy_pose` and `contact` were
  carried over **unchanged** from Phase 4/6 — this phase is the first to reconsider them since
  Phase 6's original on-device-Vision calibration.
- P4's `validation.md` run notes documented two open issues this phase directly follows up on:
  1. `racket_drop` resolved to `None` on all 3 `ag_three_serves.MOV` serves because `trophy_pose`
     and `contact` landed on adjacent sampled frames, leaving an empty search range.
  2. `trophy_pose`/`racket_drop` looked "less crisp" on `vesa_slow_mo.mov` than on `serve_1.MOV`/
     `serve_4.mov` — racket appeared higher/less dropped-behind-the-back at both frames.
- Direct visual inspection this session (frames 052–054 of `ag_three_serves.MOV`, serve 1) found:
  frame052 (`trophy_pose`) shows the player airborne, tossing arm reaching for the ball, racket
  already up near the head — not the classic "back-scratch" trophy position. frame053 (`contact`)
  shows the racket approaching the ball, not yet touching it — close, but plausibly a fraction
  early. frame054 (one `stride=5` sample later, ~0.17s) already shows full follow-through with the
  ball gone. Wrist-y confidence stayed high (0.75–0.99) throughout this window — the issue is not
  a confidence dropout, it's that the entire Cocking→Contact motion happened faster than one
  sample interval, and (independently) that `trophy_pose`'s frame looks like it's already
  transitioning toward Cocking.
- `backend/app/engine/rules.py`'s `evaluate_rules` and `rules.json` are keyed by `ServePhase` and
  unaffected by which specific frame a phase resolves to — no `rules.py` change is needed
  regardless of what this phase changes in `phases.py`.
- **Three-mode product architecture:** per `specs/mission.md`'s isolation rule, this phase's code
  is Pro-2D/3D-only and additive, same as P4. It must not modify `PhaseReviewView`, the Lite
  pipeline/segmentation services, or `ContentView`.
