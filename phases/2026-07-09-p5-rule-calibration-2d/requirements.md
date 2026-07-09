# Phase P5 — Rule Calibration (2D) — Requirements

## Scope

Ground `backend/rules.json` in real 2D-measured joint angles from five reference serves
(`serve_2.mov`, `serve_3.mov`, `serve_4.mov`, `vesa_slow_mo.mov`, `alcaraz_serve_1.mov`), now that
P4/P4b give us reliable six-frame phase detection to measure at. All current footage is single-camera
2D from the **open side** of the server (phone perpendicular to the serve direction) — every rule
this phase adds is scoped to what's reliably visible and measurable from that one angle. Rules for
other camera angles (behind-server, closed-side) are explicitly deferred to P15; this phase adds a
`view` tag to `rules.json` now so P15 can add those rules alongside without restructuring.

This phase **replaces** the 5 hand-authored placeholder rules from Lite Phase 4 with a new
9-rule open-side set (below), whose target values and pass-band margins are derived empirically
from the 5 reference serves via a new calibration tool, `backend/tools/analyze_angles.py`.

Scope is **backend-only** — no iOS changes. The mode selector and in-app cue display are P6.

## In Scope

- **Engine metric extensions** (`backend/app/engine/angles.py`): add `keypoint_x` (mirrors the
  existing `keypoint_y`) and `segment_angle_from_vertical` (generalizes the existing single-joint
  `forearm_angle_from_vertical` to any two joints, needed for the toss-arm-verticality rule).
- **Rule engine extensions** (`backend/app/engine/rules.py`): add 4 new metric types
  (`angle_from_vertical`, `x_diff`, `ball_offset_x`, `ball_offset_y`), a `view` field on `_Rule`
  (default `"open_side"`), and thread per-phase object detections into `evaluate_rules` so the two
  ball-position rules can read racket/ball bounding boxes.
- **Pose schema change** (`backend/app/services/pose_model.py`): retain `nose` in
  `map_coco17_to_backend_schema` (currently dropped via `_FACE_KEYPOINTS`) as a head-height proxy
  for the toss-hand eye-height rule. Eyes/ears stay dropped.
- **`/analyze` wiring** (`backend/app/routers/analyze.py`): pass the per-phase detections map into
  `evaluate_rules`.
- **New calibration tool** (`backend/tools/analyze_angles.py`): samples each reference video, runs
  pose + object detection, locates the sampled frame nearest each hand-labeled ground-truth
  timestamp, computes every candidate rule metric at that frame, and prints a per-serve table plus
  aggregate min/max/mean/std — the basis for setting `rules.json` thresholds by hand.
- **Ground-truth labeling additions** (`backend/tools/segmentation_ground_truth.json`): add the
  phase timestamps the calibration needs but that don't exist yet — `alcaraz_serve_1.mov` (no entry
  at all today), `serve_2.mov`'s `trophy_pose` (currently omitted as a segmentation near-miss; the
  *label* itself is still valid since calibration reads hand-labeled timestamps, not auto-detected
  ones), and `vesa_slow_mo.mov`'s `contact` (currently omitted; contact's two open-side rules here
  are pose-geometry-based, not ball-position-based, so a hand label works even though the object
  detector loses the ball at contact on this video).
- **Manual calibration run** (hard merge gate, mirrors P4b's Group 4 pattern): run
  `analyze_angles.py` against the 5 reference serves, choose each rule's margin by inspecting the
  printed spread, write the final calibrated `rules.json`, and record the chosen values + rationale
  in `validation.md` run notes.
- **Held-out sanity check** (informal, non-tuning): after thresholds are set, run
  `analyze_angles.py` against `serve_1.MOV` and `ag_three_serves.MOV` (the user's own club-level
  serves, not reference-quality) and note whether any rule plausibly fires — mirrors P4b's
  `alcaraz_serve_1.mov` held-out check.
- **Tests**: unit coverage for the two new `angles.py` functions, the four new `rules.py` metrics
  (including the `view` filter and ball-detection-missing skip behavior), `analyze_angles.py`'s
  frame-selection/aggregation logic (synthetic fixtures), and confirmation that `rules.json` still
  loads (the `_Rule` validator runs on every rule at import).

## Out of Scope

- **Behind-server / closed-side rules and the view-selection UI/API.** Still P15. This phase only
  adds the `view` field and populates `"open_side"`.
- **3D re-calibration of these same thresholds.** Still P10.
- **Per-serve-type (flat/slice/kick) threshold variants.** Still P14.
- **Any iOS work, the mode selector, or in-app cue display.** Still P6. `git diff --name-only
  develop...HEAD` must show zero changes under `App/`.
- **Handedness-agnostic rules.** The engine stays hardcoded right-handed-hitting/left-handed-toss,
  matching `phases.py`'s existing `HANDEDNESS` constant — all 5 reference serves are right-handed.
- **Rigorous ground-truth accuracy metrics (PCK/mAP).** Still deferred to P18; unrelated to rule
  calibration.
- **Changing `RTMPoseModel`'s inference logic, `ObjectDetectionModel`, or `phases.py`'s phase-
  detection heuristics.** This phase measures at already-detected/labeled frames; it does not touch
  how those frames are found.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Camera-angle scoping | Add a `view: str = "open_side"` field to every rule now; `evaluate_rules` filters by active view | User's framing: all rules must be justified by open-side visibility; behind-server rules are a different phase (P15) with different visible landmarks. Tagging now avoids a `rules.json` restructure later. |
| Rule set | Replace all 5 existing placeholder rules with the user's 9-rule open-side set (release toss-arm straightness + toss-hand eye-height; trophy hitting-elbow-shoulder-line + toss-arm straightness + toss-arm verticality; racket-drop ball height + ball front-position; contact left-hip-angle + shoulder-stacking) | User-specified list, grounded in what's visible from the open side. Includes a ball-position rule (racket_drop) using the P2 object detector for the first time in the rule engine. |
| Calibration input frames | Hand-labeled ground-truth timestamps (`segmentation_ground_truth.json`), not P4/P4b's auto-detected frames | User's explicit choice — decouples rule-threshold calibration from segmentation accuracy, so a future segmentation regression doesn't silently corrupt rule thresholds too. |
| Threshold derivation | min–max envelope across the 5 reference serves, widened by a margin | User's explicit choice: references define the acceptable technique envelope; the margin accounts for measurement noise and a 5-serve sample being narrow. |
| Margin values | **Not pre-specified.** Chosen by inspection during the manual calibration run (Group with the hard merge gate) once `analyze_angles.py`'s real output is available, and recorded with rationale in `validation.md` run notes | User confirmed — mirrors P4b's precedent of tuning phase-detection constants against real footage rather than guessing numbers in advance. Different metrics have very different natural scales (degrees vs. normalized 0–1 coordinate diffs), so a single formula picked blind risks being wrong for at least some rules. |
| Rule severity | All 9 new rules default to `"major"` | User confirmed — every rule in this set represents a fundamental, clearly-visible open-side technique marker per the user's own framing, not a fine-grained style nitpick; a uniform severity avoids an arbitrary split without more coaching-domain input. |
| Held-out validation | Run the calibrated rules against `serve_1.MOV`/`ag_three_serves.MOV` (excluded from the named 5, not reference-quality) as an informal, non-tuning sanity check; record observations in run notes | User confirmed — mirrors P4b's `alcaraz_serve_1.mov` held-out check; costs little since the same tool already exists, and gives an early signal on whether the calibrated thresholds are absurdly tight/loose against real (imperfect) serves. |
| `nose` keypoint retention | Un-drop `nose` from `pose_model.py`'s `_FACE_KEYPOINTS`; eyes/ears stay dropped | The toss-hand eye-height rule needs a head-height reference. `nose` is COCO-17-native (no extra model work) and approximates eye/head height well enough — matches the user's own fallback framing ("or something similar like midheight of head"). Adding both eyes would require a derived midpoint keypoint for one rule; not worth the schema churn. |
| Ball-position metric semantics | `ball_offset_y`/`ball_offset_x` = ball bbox center minus the referenced joint (`left_shoulder`, the non-hitting shoulder), signed | Matches the existing `y_diff`/`x_diff` convention (`joints[0] - joints[1]`) already used elsewhere in `rules.py`; keeps sign semantics consistent across metric types so `analyze_angles.py`'s printed values are directly comparable. |
| Missing-detection behavior | Ball-position rules silently skip (no cue emitted) when no ball is detected in the phase frame, exactly like existing rules skip on a missing/low-confidence keypoint | Consistent with `evaluate_rules`'s existing `value is None -> skip` behavior; a missing detection is a data-availability gap, not a rule failure. |

## Context

- **P4/P4b** established reliable automatic six-frame (`start`/`release`/`trophy_pose`/
  `racket_drop`/`contact`/`finish`) segmentation and hand-labeled ground truth
  (`segmentation_ground_truth.json`) for `serve_1.MOV`, `serve_2.mov`, `serve_3.mov`, `serve_4.mov`,
  `ag_three_serves.MOV`, and `vesa_slow_mo.mov`. `alcaraz_serve_1.mov` exists as calibration footage
  but has no ground-truth entry yet (P4b used it only as an out-of-sample segmentation check, which
  didn't require labeled timestamps for every phase). This phase is the first to need labeled
  timestamps *for rule calibration*, and the first to use `alcaraz_serve_1.mov` as a full input
  rather than a spot-check.
- **The rule engine** (`backend/app/engine/rules.py`, `backend/rules.json`) has existed since Lite
  Phase 4 but is dormant — Lite mode never calls it; only Pro 2D/3D modes will (starting P6). Its
  current 5 rules were hand-authored placeholders, never grounded in measured angles.
- **`backend/app/engine/angles.py`** already provides `compute_angle`, `joint_xy`, `keypoint_y`,
  and several phase-detection-specific helpers (`knee_flexion_angle`, `arm_straightness_angle`,
  `forearm_angle_from_vertical`). This phase adds two more general-purpose helpers
  (`keypoint_x`, `segment_angle_from_vertical`) rather than duplicating logic inline in `rules.py`.
- **The object detector** (P2, `backend/app/services/object_detection.py`) returns racket/ball
  bounding boxes per frame. `phases.py` already has bbox-center helpers (`_bbox_center`,
  `_detection_center_y`) that this phase's `rules.py` changes can reuse for the ball-position
  metrics rather than re-deriving bbox math.
- **Reference-serve data is gitignored, local-only footage** under `backend/tools/calibration_data/`
  (`*.mov` files) — same as every prior CV-tooling phase (P3, P4, P4b). No new recording is needed;
  `alcaraz_serve_1.mov` and `vesa_slow_mo.mov` are already present alongside `serve_2/3/4.mov`.
- **Three-mode product architecture:** per `specs/mission.md`'s isolation rule, this phase's code is
  Pro-2D/3D-only and additive, same as every Pro-phase before it. It must not modify
  `PhaseReviewView`, the Lite pipeline/segmentation services, or `ContentView` — trivially true here
  since this phase touches no iOS files at all.
