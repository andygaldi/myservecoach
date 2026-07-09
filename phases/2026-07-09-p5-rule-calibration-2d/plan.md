# Phase P5 — Plan

> **Lite-isolation note:** every task group touches only `backend/`. No group modifies
> `PhaseReviewView`, the Lite pipeline/segmentation services, `ContentView`, or any file under
> `App/`. `RTMPoseModel`'s inference logic, `ObjectDetectionModel`, and `phases.py`'s phase-detection
> heuristics are consumed unmodified.

> **Shared design note (applies to Groups 1–2):** `rules.py`'s private `_compute_metric(frame,
> rule)` is renamed to a public `compute_metric_value(frame, metric, joints, detections=None)` that
> takes raw parameters instead of a `_Rule` object. `evaluate_rules` calls it with `rule.metric`/
> `rule.joints`; `analyze_angles.py` (Group 3) calls it directly with its candidate metric specs.
> This keeps calibration math and runtime rule-evaluation math identical by construction — no
> duplicated switch statement — rather than analyze_angles.py reimplementing the metric logic
> separately.

## Group 1 — Angle Helper Extensions (surface: `backend`)

1. In `backend/app/engine/angles.py`, add `keypoint_x`, mirroring the existing `keypoint_y`:
   ```python
   def keypoint_x(frame: Frame, joint_name: str, min_confidence: float = MIN_CONFIDENCE) -> float | None:
       """Normalized x-coordinate of a joint, or None if below confidence threshold."""
       kp = frame.keypoints.get(joint_name)
       if kp is None or kp.confidence < min_confidence:
           return None
       return kp.x
   ```
2. Add `segment_angle_from_vertical`, placed above `forearm_angle_from_vertical`:
   ```python
   def segment_angle_from_vertical(frame: Frame, joint_a: str, joint_b: str) -> float | None:
       """Angle in degrees between straight-up vertical (from `joint_a`) and the `joint_a`->`joint_b`
       segment. 0° when `joint_b` is directly above `joint_a`; grows as the segment tilts away from
       vertical. General form of the single-joint vertical-deviation angle used by
       `forearm_angle_from_vertical`.
       """
       a_xy = joint_xy(frame, joint_a)
       b_xy = joint_xy(frame, joint_b)
       if a_xy is None or b_xy is None:
           return None
       straight_up = (a_xy[0], a_xy[1] + 1.0)
       return compute_angle(straight_up, a_xy, b_xy)
   ```
3. Refactor `forearm_angle_from_vertical` to delegate to it (behavior-preserving — same docstring,
   same result for every existing caller in `phases.py`):
   ```python
   def forearm_angle_from_vertical(frame: Frame, side: str) -> float | None:
       """Angle in degrees between the `side` forearm (elbow->wrist) and straight-up vertical.
       ... (existing docstring body unchanged) ...
       """
       return segment_angle_from_vertical(frame, f"{side}_elbow", f"{side}_wrist")
   ```
4. In `backend/tests/test_angles.py`, add:
   - `test_keypoint_x_returns_x_when_confident` / `test_keypoint_x_returns_none_when_low_confidence`
     — mirror the existing `keypoint_y` test pair exactly.
   - `test_segment_angle_from_vertical_zero_when_directly_above`: `joint_a` at `(0.5, 0.5)`,
     `joint_b` at `(0.5, 0.7)` (straight up) — assert result `≈ 0.0`.
   - `test_segment_angle_from_vertical_ninety_when_horizontal`: `joint_b` at `(0.7, 0.5)` (level
     with `joint_a`) — assert result `≈ 90.0`.
   - `test_segment_angle_from_vertical_none_when_joint_missing`: one joint absent from the frame.
   - `test_forearm_angle_from_vertical_matches_segment_angle_from_vertical`: build a frame, assert
     `forearm_angle_from_vertical(frame, "right") == segment_angle_from_vertical(frame,
     "right_elbow", "right_wrist")` — locks in the refactor's equivalence.
5. Run `pytest backend/tests/test_angles.py -v` — confirm all pre-existing tests pass unmodified
   plus the new ones.

## Group 2 — Rule Engine: New Metrics, View Tag, Detections Plumbing (surface: `backend`)

6. In `backend/app/engine/rules.py`:
   - Extend imports: add `keypoint_x`, `segment_angle_from_vertical` from `app.engine.angles`; add
     `Detection` from `app.models`; add `from app.engine.phases import _bbox_center` (reused
     verbatim — same cross-module private-helper-reuse pattern `segmentation_report.py` already
     uses for `pose_benchmark.py`'s helpers).
   - Extend `_Rule.metric`'s `Literal` to `Literal["y_diff", "x_diff", "angle", "angle_from_vertical",
     "ball_offset_x", "ball_offset_y"]`.
   - Add `view: str = "open_side"` field to `_Rule`.
   - Rename `_compute_metric(frame: Frame, rule: _Rule) -> float | None` to a public
     `compute_metric_value(frame: Frame, metric: str, joints: list[str], detections: list[Detection]
     | None = None) -> float | None`, keeping the existing `y_diff`/`angle` branches (now reading
     `metric`/`joints` params instead of `rule.metric`/`rule.joints`) and adding:
     ```python
     if metric == "x_diff":
         x0 = keypoint_x(frame, joints[0])
         x1 = keypoint_x(frame, joints[1])
         if x0 is None or x1 is None:
             return None
         return x0 - x1
     if metric == "angle_from_vertical":
         return segment_angle_from_vertical(frame, joints[0], joints[1])
     if metric in ("ball_offset_x", "ball_offset_y"):
         if not detections:
             return None
         ball = next((d for d in detections if d.label == "ball"), None)
         if ball is None:
             return None
         ball_x, ball_y = _bbox_center(ball.bbox)
         joint = joint_xy(frame, joints[0])
         if joint is None:
             return None
         return (ball_x - joint[0]) if metric == "ball_offset_x" else (ball_y - joint[1])
     ```
   - Update `evaluate_rules`'s signature and body:
     ```python
     def evaluate_rules(
         phase_frames: dict[ServePhase, Frame | None],
         phase_detections: dict[ServePhase, list[Detection] | None] | None = None,
         view: str = "open_side",
     ) -> list[Cue]:
         cues = []
         for rule in _RULES:
             if rule.view != view:
                 continue
             frame = phase_frames.get(rule.phase)
             if frame is None:
                 continue
             detections = (phase_detections or {}).get(rule.phase)
             value = compute_metric_value(frame, rule.metric, rule.joints, detections)
             if value is None:
                 continue
             if not _passes(value, rule):
                 cues.append(Cue(rule_id=rule.id, phase=rule.phase, message=rule.message, severity=rule.severity))
         return cues
     ```
     (`phase_detections`/`view` both default so existing single-argument callers keep working.)
7. In `backend/app/services/pose_model.py`, remove `"nose"` from `_FACE_KEYPOINTS`:
   ```python
   _FACE_KEYPOINTS = {"left_eye", "right_eye", "left_ear", "right_ear"}
   ```
   Update the set's context (no docstring change needed — `map_coco17_to_backend_schema`'s existing
   docstring doesn't enumerate dropped joints by name).
8. In `backend/app/routers/analyze.py`, build and pass the phase→detections map:
   ```python
   @router.post("/analyze", response_model=AnalyzeResponse)
   async def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
       phase_frames = detect_phases(request.frames, request.detections)
       ts_to_detections = {
           frame.timestamp: dets for frame, dets in zip(request.frames, request.detections or [])
       }
       phase_detections = {
           phase: ts_to_detections.get(frame.timestamp)
           for phase, frame in phase_frames.items()
           if frame is not None
       }
       cues = evaluate_rules(phase_frames, phase_detections)
       trophy_detected = phase_frames.get(ServePhase.trophy_pose) is not None
       summary = _CLEAN_SERVE_SUMMARY if (not cues and trophy_detected) else None
       return AnalyzeResponse(cues=cues, summary=summary)
   ```
9. In `backend/tests/test_rules.py`:
   - Rename any existing direct calls to `_compute_metric` to `compute_metric_value` with the new
     parameter order (update, don't duplicate, existing test bodies).
   - Add a `# --- New metric types ---` section:
     - `test_x_diff_metric`, `test_angle_from_vertical_metric` (assert it matches
       `segment_angle_from_vertical`'s own result for the same frame/joints).
     - `test_ball_offset_y_metric_with_detection`, `test_ball_offset_x_metric_with_detection`.
     - `test_ball_offset_metric_returns_none_when_no_ball_detected`: `detections=[]` (racket-only
       or empty) — assert `None`.
     - `test_ball_offset_metric_returns_none_when_detections_is_none`: `detections=None`.
   - Add a `# --- View filtering ---` section:
     - `test_evaluate_rules_defaults_to_open_side_view`: two synthetic rules loaded via a
       monkeypatched `_RULES` (or a rule fixture list, matching however `test_rules.py` currently
       constructs rule fixtures) — one `view="open_side"`, one `view="behind_server"`, both failing
       — assert only the `open_side` rule's cue is returned by default.
     - `test_evaluate_rules_respects_explicit_view_argument`: same fixture, call with
       `view="behind_server"` — assert the other rule's cue is returned instead.
   - Add `test_evaluate_rules_passes_detections_to_ball_offset_rule`: a rule with a `ball_offset_y`
     metric, `phase_detections` supplying a ball detection for that phase that fails the rule's
     threshold — assert a cue is produced; omit `phase_detections` — assert no cue (metric returns
     `None`, skipped).
10. In `backend/tests/test_analyze.py`, add/update a case confirming `/analyze` builds and forwards
    `phase_detections` correctly: a request with `detections` populated for the frame that resolves
    to `contact`, using a rule (via a temporary rules.json fixture or monkeypatched `_RULES`, matching
    the file's existing test pattern) that only fires via a `ball_offset_*` metric — assert the cue
    appears in the response. Confirm all pre-existing `test_analyze.py` cases still pass with the
    now-two-argument `evaluate_rules` call.
11. Run `pytest backend/tests/test_rules.py backend/tests/test_analyze.py backend/tests/test_pose_model.py -v`
    — confirm all pass. Note: `rules.json` still holds the **old 5 rules** at this point (Group 5
    rewrites it) — `_RULES` loads fine since the old rules' `metric`/`comparison` values remain valid
    members of the extended `Literal`s, and `view` defaults to `"open_side"` for all of them via the
    new field's default, so no rule silently stops firing mid-phase.

## Group 3 — `analyze_angles.py` Calibration Tool (surface: `backend`)

12. Create `backend/tools/analyze_angles.py`, structured like `segmentation_report.py`: reuse
    `sample_video_frames`, `_resolve_videos`, `_TOOLS_DIR` from `tools.pose_benchmark`;
    `get_pose_model`, `get_object_detection_model` from the app services; `compute_metric_value` from
    `app.engine.rules`.
13. Define the 9 candidate metric specs matching this phase's rule table exactly (module-level
    constant, one entry per planned rule):
    ```python
    _CANDIDATE_METRICS: list[dict] = [
        {"id": "release_toss_arm_straight", "phase": "release", "metric": "angle",
         "joints": ["left_shoulder", "left_elbow", "left_wrist"], "shape": "gte"},
        {"id": "release_toss_hand_eye_height", "phase": "release", "metric": "y_diff",
         "joints": ["left_wrist", "nose"], "shape": "range"},
        {"id": "trophy_hitting_elbow_shoulder_line", "phase": "trophy_pose", "metric": "angle",
         "joints": ["left_shoulder", "right_shoulder", "right_elbow"], "shape": "range"},
        {"id": "trophy_toss_arm_straight", "phase": "trophy_pose", "metric": "angle",
         "joints": ["left_shoulder", "left_elbow", "left_wrist"], "shape": "gte"},
        {"id": "trophy_toss_arm_vertical", "phase": "trophy_pose", "metric": "angle_from_vertical",
         "joints": ["left_shoulder", "left_wrist"], "shape": "lte"},
        {"id": "racket_drop_ball_height", "phase": "racket_drop", "metric": "ball_offset_y",
         "joints": ["left_shoulder"], "shape": "range"},
        {"id": "racket_drop_ball_front", "phase": "racket_drop", "metric": "ball_offset_x",
         "joints": ["left_shoulder"], "shape": "range"},
        {"id": "contact_left_hip_angle", "phase": "contact", "metric": "angle",
         "joints": ["left_shoulder", "left_hip", "left_knee"], "shape": "range"},
        {"id": "contact_shoulders_stacked", "phase": "contact", "metric": "x_diff",
         "joints": ["right_shoulder", "left_shoulder"], "shape": "range"},
    ]
    ```
14. `def nearest_frame(frames: list[Frame], target_ts: float) -> Frame:` — returns
    `min(frames, key=lambda f: abs(f.timestamp - target_ts))`.
15. `def measure_video(video_path: Path, ground_truth: dict, pose_model, detection_model, stride: int
    = 2) -> dict[str, dict[int, float]]:` — samples the video (reusing `sample_video_frames`), runs
    pose+detection per frame (mirroring `segmentation_report.py`'s `build_frame_sequence`), looks up
    `ground_truth["videos"][video_path.name]` (list of `{serve_index, phases}`), and for every serve
    entry and every candidate metric whose `phase` key is present in that serve's `phases`: finds the
    nearest sampled frame to the labeled timestamp, finds that frame's parallel detections list, and
    calls `compute_metric_value(frame, metric["metric"], metric["joints"], detections)`. Returns
    `{metric_id: {serve_label: value}}` (skip a metric/serve pair when the value is `None`, e.g. no
    ball detected — don't crash).
16. `def print_report(results: dict[str, dict[str, float]]) -> None:` — for each metric id, print
    every serve's raw signed value, then `min`/`max`/`mean`/`stdev` (via `statistics.mean`/`pstdev`),
    then a one-line suggested-threshold hint keyed by that metric's `shape` from `_CANDIDATE_METRICS`
    (e.g. `shape="gte"` → `f"suggested: gte, threshold <= {min_val:.1f} (subtract your chosen margin)"`;
    `shape="range"` → `f"suggested: range, [{min_val:.3f}, {max_val:.3f}] (widen by your chosen margin)"`).
    Margin values are **not** computed here — printed as raw stats only, per this phase's Key
    Decision to choose margins by inspection.
17. CLI (`_build_arg_parser`/`main`, matching `segmentation_report.py`'s shape): `--videos` (default
    a fixed list of the 5 reference-serve filenames, not a glob — this tool is scoped to exactly the
    named calibration set, unlike `segmentation_report.py`'s "everything in the directory" default),
    `--ground-truth` (default `backend/tools/segmentation_ground_truth.json`), `--stride` (default
    `2`, matching `segmentation_report.py`'s post-P4b default).
18. Create `backend/tests/test_analyze_angles.py` with synthetic fixtures (no real models/videos,
    matching `test_segmentation_report.py`'s style): `test_nearest_frame_picks_closest_timestamp`,
    `test_measure_video_skips_metric_when_value_is_none` (e.g. no ball detection for a
    `ball_offset_*` metric), `test_measure_video_computes_expected_value_for_known_frame` (hand-built
    frame/detections where the expected angle/diff is known), `test_print_report_handles_single_value`
    (no crash on a 1-serve stdev — use `statistics.pstdev`, which is defined for n=1, not
    `statistics.stdev`, which raises).
19. Run `pytest backend/tests/test_analyze_angles.py -v` — confirm it passes with no real model
    construction.

## Group 4 — Ground-Truth Label Additions (manual, visual inspection)

20. Using each video's existing `backend/tools/calibration_data/<name>_segmentation/report.html` /
    `frames/` (already generated by P4b's `segmentation_report.py` run) or a fresh
    `segmentation_report.py` run if needed, visually determine and add to
    `backend/tools/segmentation_ground_truth.json`:
    - **`alcaraz_serve_1.mov`** — a new top-level entry with `serve_index: 1` and timestamps for
      `release`, `trophy_pose`, `racket_drop`, `contact` (the four phases this phase's rules need;
      `start`/`finish` are optional since no rule in this phase reads them).
    - **`serve_2.mov`** — add a `trophy_pose` timestamp to the existing entry (currently omitted per
      its `_note`; the note can stay, since the *segmentation heuristic's* near-miss is unrelated to
      whether a human-labeled timestamp exists).
    - **`vesa_slow_mo.mov`** — add a `contact` timestamp to the existing entry (currently omitted per
      its `_note`, which documents the object-detector limitation, not a labeling impossibility —
      contact is still a visually identifiable pose frame).
21. Confirm `python -c "import json; d=json.load(open('backend/tools/segmentation_ground_truth.json'))"`
    parses without error and every one of the 5 reference videos has entries for all 4 phases this
    phase's rules need (`release`, `trophy_pose`, `racket_drop`, `contact`).

## Group 5 — Manual Calibration Run & `rules.json` (manual, hard merge gate)

22. Run `cd backend && python tools/analyze_angles.py` — prints the 9-metric report across the 5
    reference serves.
23. For each metric, inspect the printed spread and choose a margin by eye (tight for
    low-variance/small-scale metrics like normalized position diffs, looser for angle metrics with
    more natural serve-to-serve variation); compute the final threshold(s).
24. Write the final `backend/rules.json`, replacing all 5 existing placeholder rules with the 9 new
    `view: "open_side"` rules from this phase's `requirements.md` table, using the calibrated
    thresholds from step 23. Draft `message` copy for each (short, actionable, matching the existing
    rules' tone — e.g. `"Straighten your toss arm at release — avoid bending at the elbow."`).
    `severity: "major"` for all 9 (per this phase's Key Decision). Confirm `rules.json` loads (the
    `_Rule` validator runs at import) via `python -c "import app.engine.rules"` from `backend/`.
25. **Self-consistency check:** re-run `analyze_angles.py` (or a small ad hoc script calling
    `evaluate_rules` directly against each reference serve's real detected phase frames) confirming
    all 5 reference serves produce zero cues against the rules derived from them. Investigate and
    fix any self-failure (usually a sign error or an off-by-one margin direction) before proceeding.
26. **Held-out sanity check:** run `analyze_angles.py`-style measurement (or `/analyze` directly)
    against `serve_1.MOV` and `ag_three_serves.MOV` — record in `validation.md` run notes which
    rules fire, if any, and whether that's plausible given these are the user's own club-level
    serves (not reference-quality).
27. Run `pytest backend/` (full suite) — confirm zero failures.
28. Confirm no iOS files touched: `git diff --name-only develop...HEAD` contains no changes under
    `App/`.
29. Record in `validation.md` run notes: the final calibrated threshold table (metric → chosen
    margin → final threshold), the self-consistency result, and the held-out check's findings.
