# Phase P4 — Plan

> **Lite-isolation note:** every task group touches only `backend/`. No group modifies
> `PhaseReviewView`, the Lite pipeline/segmentation services, `ContentView`, or any file under `App/`.
> `RTMPoseModel`, `ObjectDetectionModel`, and `calibration_report.py` are consumed unmodified.

## Group 1 — Six-Frame Model & Multi-Serve Boundary Splitting (surface: `backend`)

1. In `backend/app/models.py`, extend `ServePhase`:
   ```python
   class ServePhase(str, Enum):
       start = "start"
       release = "release"
       trophy_pose = "trophy_pose"
       racket_drop = "racket_drop"
       contact = "contact"
       finish = "finish"
   ```
   (Existing three members keep their string values, so `rules.json` and every existing
   `ServePhase.trophy_pose`/`racket_drop`/`contact` reference is unaffected.)
2. In `backend/app/engine/phases.py`, add `import math` and these module-level tunable constants near the
   top (below `HANDEDNESS`):
   ```python
   MIN_REST_FRAMES = 5
   LOW_MOTION_VELOCITY_THRESHOLD = 0.02
   ```
3. Add `def _frame_velocity(a: Frame, b: Frame) -> float:` — mean Euclidean distance, in normalized
   coordinates, across keypoints present in both frames above `MIN_CONFIDENCE` (import `MIN_CONFIDENCE`
   from `app.engine.angles`, alongside the existing `compute_angle`/`joint_xy`/`keypoint_y` imports):
   ```python
   def _frame_velocity(a: Frame, b: Frame) -> float:
       shared = set(a.keypoints) & set(b.keypoints)
       distances = []
       for name in shared:
           kp_a, kp_b = a.keypoints[name], b.keypoints[name]
           if kp_a.confidence < MIN_CONFIDENCE or kp_b.confidence < MIN_CONFIDENCE:
               continue
           distances.append(math.hypot(kp_a.x - kp_b.x, kp_a.y - kp_b.y))
       return sum(distances) / len(distances) if distances else 0.0
   ```
4. Add `def segment_serves(frames: list[Frame], min_rest_frames: int = MIN_REST_FRAMES, velocity_threshold: float = LOW_MOTION_VELOCITY_THRESHOLD) -> list[list[Frame]]:`:
   ```python
   def segment_serves(
       frames: list[Frame],
       min_rest_frames: int = MIN_REST_FRAMES,
       velocity_threshold: float = LOW_MOTION_VELOCITY_THRESHOLD,
   ) -> list[list[Frame]]:
       if not frames:
           return []

       boundaries: list[int] = []
       rest_run_start: int | None = None
       has_seen_active = False

       for i in range(1, len(frames)):
           velocity = _frame_velocity(frames[i - 1], frames[i])
           if velocity >= velocity_threshold:
               if rest_run_start is not None and has_seen_active and (i - rest_run_start) >= min_rest_frames:
                   boundaries.append((rest_run_start + i - 1) // 2)
               rest_run_start = None
               has_seen_active = True
           elif rest_run_start is None:
               rest_run_start = i

       segments: list[list[Frame]] = []
       start = 0
       for boundary in boundaries:
           segments.append(frames[start : boundary + 1])
           start = boundary + 1
       segments.append(frames[start:])
       return segments
   ```
   (Leading idle before the first active frame is never split off, since `has_seen_active` is `False`
   until the first high-velocity transition; trailing idle after the last active frame never closes a
   rest run into a boundary, since the loop ends before another high-velocity frame appears.)
5. Write `backend/tests/test_segment_serves.py` (new file), following `test_phases.py`'s `make_frame`
   fixture style (`from conftest import make_frame`):
   - `test_empty_frames_returns_empty_list`
   - `test_single_serve_no_rest_gap_returns_one_segment`: a sequence of frames with continuously-changing
     keypoints (velocity always above threshold) → `len(segments) == 1`.
   - `test_two_serves_separated_by_rest_gap_returns_two_segments`: build ~6 "active" frames (changing
     keypoints), then `MIN_REST_FRAMES + 2` "rest" frames (identical keypoints, velocity `0.0`), then ~6
     more "active" frames — assert `len(segments) == 2` and that the split point falls within the rest
     run (assert the last frame of segment 1 and first frame of segment 2 are on either side of the
     rest-run midpoint).
   - `test_short_rest_gap_does_not_split`: a rest run shorter than `MIN_REST_FRAMES` between two active
     bursts → `len(segments) == 1` (brief mid-serve pause, e.g. a stutter in the toss, must not fragment
     one serve into two).
   - `test_leading_idle_not_split_off`: several identical (zero-velocity) frames *before* the first active
     burst, long enough to exceed `MIN_REST_FRAMES` → assert the leading idle frames remain attached to
     the first (only) segment, not split into their own empty-ish segment.
   - `test_trailing_idle_not_split_off`: symmetric case after the only active burst.
   - `test_velocity_ignores_low_confidence_keypoints`: two frames with identical high-confidence keypoints
     but wildly different low-confidence (`< MIN_CONFIDENCE`) keypoint values → `_frame_velocity` returns
     `0.0` (or near it), confirming low-confidence noise doesn't register as motion.
6. Run `pytest backend/tests/test_segment_serves.py -v` — confirm all pass.

## Group 2 — New Phase Heuristics: Start, Release, Finish (surface: `backend`)

7. In `backend/app/engine/phases.py`, change `detect_phases`'s signature to
   `def detect_phases(frames: list[Frame], detections: list[list[Detection]] | None = None) -> dict[ServePhase, Frame | None]:`
   and import `Detection` from `app.models`.
8. Add `def _ball_center_y(dets: list[Detection]) -> float | None:`:
   ```python
   def _ball_center_y(dets: list[Detection]) -> float | None:
       ball = next((d for d in dets if d.label == "ball"), None)
       if ball is None:
           return None
       return (ball.bbox.y_min + ball.bbox.y_max) / 2.0
   ```
9. Replace the existing trophy-pose-preceding section with a `release_idx` computation that runs *before*
   the trophy-pose loop:
   ```python
   ball_ever_detected = detections is not None and any(_ball_center_y(dets) is not None for dets in detections)

   release_idx: int | None = None
   if ball_ever_detected:
       for i, frame in enumerate(frames):
           if detections is None or i >= len(detections):
               continue
           ball_y = _ball_center_y(detections[i])
           toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
           if ball_y is not None and toss_wrist_y is not None and ball_y > toss_wrist_y:
               release_idx = i
               break
   else:
       for i, frame in enumerate(frames):
           toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
           toss_shoulder_y = keypoint_y(frame, f"{toss}_shoulder")
           if toss_wrist_y is None or toss_shoulder_y is None:
               continue
           if toss_wrist_y > toss_shoulder_y:
               release_idx = i
               break
   ```
10. Add the `start_idx` computation right after `release_idx` (and after `trophy_idx` is computed, so it
    can use `trophy_idx` as a secondary bound — keep the existing trophy-pose loop where it is, between
    steps 9 and this one):
    ```python
    start_search_end = release_idx if release_idx is not None else trophy_idx
    start_idx: int | None = None
    if start_search_end is not None and start_search_end > 0:
        min_toss_wrist_y = float("inf")
        for i in range(0, start_search_end):
            toss_wrist_y = keypoint_y(frames[i], f"{toss}_wrist")
            if toss_wrist_y is not None and toss_wrist_y < min_toss_wrist_y:
                min_toss_wrist_y = toss_wrist_y
                start_idx = i
    ```
11. After the existing contact-detection block, add the `finish_idx` computation:
    ```python
    finish_idx: int | None = None
    if contact_idx is not None:
        min_front_foot_y = float("inf")
        for i in range(contact_idx + 1, len(frames)):
            front_foot_y = keypoint_y(frames[i], f"{toss}_ankle")
            if front_foot_y is not None and front_foot_y < min_front_foot_y:
                min_front_foot_y = front_foot_y
                finish_idx = i
    if finish_idx is None:
        finish_idx = len(frames) - 1 if frames else None
    ```
12. Update the function's final return dict to include all six keys, in Kovacs stage order:
    ```python
    return {
        ServePhase.start: frames[start_idx] if start_idx is not None else None,
        ServePhase.release: frames[release_idx] if release_idx is not None else None,
        ServePhase.trophy_pose: frames[trophy_idx] if trophy_idx is not None else None,
        ServePhase.racket_drop: frames[drop_idx] if drop_idx is not None else None,
        ServePhase.contact: frames[contact_idx] if contact_idx is not None else None,
        ServePhase.finish: frames[finish_idx] if finish_idx is not None else None,
    }
    ```
13. In `backend/tests/test_phases.py`, add a `# --- Release detection ---` section:
    - `test_release_ball_primary_when_ball_ever_detected`: build frames where a `Detection(label="ball", ...)`
      is present in `detections` for some frames, with the ball's bbox center-y above the toss wrist in the
      first qualifying frame and below it in an earlier frame — assert `release_idx` matches the ball-based
      frame, not the toss-wrist-rise frame (construct the fixture so the two would disagree, proving the
      ball path takes priority).
    - `test_release_falls_back_to_toss_wrist_when_ball_never_detected`: `detections` provided but with no
      `"ball"` label in any frame (e.g. only `"racket"` entries, or empty lists) → assert the result matches
      the original toss-wrist-above-shoulder heuristic.
    - `test_release_falls_back_when_detections_is_none`: `detect_phases(frames)` with no `detections` arg
      at all → same fallback path.
    - `test_release_none_when_toss_never_rises_and_no_ball`: neither signal ever qualifies → `None`.
    Add a `# --- Start detection ---` section:
    - `test_start_is_lowest_toss_wrist_before_release`: 3+ frames with varying toss-wrist heights before a
      qualifying release frame → assert `start_idx` is the frame with the minimum toss-wrist y strictly
      before `release_idx`.
    - `test_start_falls_back_to_trophy_bound_when_no_release`: no frame ever qualifies for `release`, but
      `trophy_idx` resolves → assert `start_idx` is the argmin over `frames[0:trophy_idx]`.
    - `test_start_none_when_neither_release_nor_trophy_resolve`: assert `None`.
    Add a `# --- Finish detection ---` section:
    - `test_finish_is_lowest_front_foot_after_contact`: contact resolves at some index; multiple frames
      after it have varying `left_ankle` (toss-side/front-foot) heights — assert `finish_idx` is the frame
      with the minimum front-foot y after contact.
    - `test_finish_falls_back_to_last_frame_when_no_ankle_data_after_contact`: contact resolves, but no
      frame after it has `left_ankle` data → assert `finish_idx` is `len(frames) - 1`.
    - `test_finish_falls_back_to_last_frame_when_no_contact`: `contact_idx` is `None` → assert `finish_idx`
      is `len(frames) - 1`.
14. Run `pytest backend/tests/test_phases.py -v` — confirm all pre-existing tests still pass unmodified and
    all new Group 2 tests pass.

## Group 3 — Combined-Signal Racket Drop (surface: `backend`)

15. In `backend/app/engine/phases.py`, add two more tunable constants near `MIN_REST_FRAMES`:
    ```python
    RACKET_DROP_ELBOW_WEIGHT = 0.5
    RACKET_DROP_RACKET_WEIGHT = 0.5
    ```
16. Add `def _racket_center_y(dets: list[Detection]) -> float | None:` (same shape as `_ball_center_y`,
    filtering for `"racket"`).
17. Add `def _min_max_normalize(values: dict[int, float]) -> dict[int, float]:` — a small helper: given
    `{frame_index: raw_value}`, returns `{frame_index: normalized_0_to_1}`; if all values are equal (or
    only one entry), every entry normalizes to `1.0` (avoids a divide-by-zero and still lets that lone
    candidate win on its own signal).
18. Replace the existing racket-drop block (currently the elbow-y-rise loop) with the combined-signal
    version:
    ```python
    drop_idx: int | None = None
    if trophy_idx is not None and contact_idx is not None:
        elbow_rises: dict[int, float] = {}
        for i in range(trophy_idx + 1, contact_idx):
            elbow_y_curr = keypoint_y(frames[i], f"{hitting}_elbow")
            elbow_y_prev = keypoint_y(frames[i - 1], f"{hitting}_elbow")
            if elbow_y_curr is not None and elbow_y_prev is not None:
                elbow_rises[i] = elbow_y_curr - elbow_y_prev

        racket_depths: dict[int, float] = {}
        if detections is not None:
            for i in range(trophy_idx + 1, contact_idx):
                if i >= len(detections):
                    continue
                center_y = _racket_center_y(detections[i])
                if center_y is not None:
                    racket_depths[i] = -center_y  # lower center_y (more dropped) => higher score

        elbow_norm = _min_max_normalize(elbow_rises)
        racket_norm = _min_max_normalize(racket_depths)

        best_score = float("-inf")
        for i in set(elbow_norm) | set(racket_norm):
            parts = []
            if i in elbow_norm:
                parts.append((RACKET_DROP_ELBOW_WEIGHT, elbow_norm[i]))
            if i in racket_norm:
                parts.append((RACKET_DROP_RACKET_WEIGHT, racket_norm[i]))
            total_weight = sum(w for w, _ in parts)
            score = sum(w * v for w, v in parts) / total_weight if total_weight else float("-inf")
            if score > best_score:
                best_score = score
                drop_idx = i
    ```
    (This is a direct in-place replacement of the current `# 3. Racket drop: ...` block. With
    `detections=None`, `racket_norm` is always empty, so every candidate's score reduces to
    `elbow_norm[i]` alone — the ranking is identical to the original elbow-only heuristic, so every
    existing racket-drop test continues to pass unmodified.)
19. In `backend/tests/test_phases.py`, add a `# --- Combined-signal racket-drop detection ---` section:
    - `test_racket_drop_combines_elbow_and_racket_signals`: build a 4-frame window (trophy, two mid-frames,
      contact) where frame A has a strong elbow rise but no racket detection, frame B has a weaker elbow
      rise but the lowest racket center-y — construct weights/values so the combined score favors frame B
      over frame A, proving the racket signal can outweigh a purely-elbow-dominant frame (unlike a
      strict elbow-first-fallback design).
    - `test_racket_drop_all_existing_elbow_only_tests_pass_with_no_detections`: parametrize or re-run the
      pre-existing elbow-only fixtures (`test_racket_drop_is_frame_with_largest_elbow_rise`, etc.) with no
      `detections` argument and confirm identical results to before this phase.
    - `test_racket_drop_ignores_ball_detections`: `detections` includes only `"ball"` entries (no
      `"racket"`) → assert the result matches the elbow-only ranking (ball never contributes to
      `racket_norm`).
    - `test_racket_drop_detections_shorter_than_frames`: a `detections` list shorter than `frames` — assert
      no `IndexError`, and frames beyond the list's length are scored on the elbow signal alone.
    - `test_min_max_normalize_handles_equal_values`: direct unit test of `_min_max_normalize` with all-equal
      input values, and with a single-entry input — both normalize to `{..., 1.0}` without raising.
20. In `backend/app/models.py`, add to `AnalyzeRequest`:
    ```python
    detections: list[list[Detection]] | None = None
    ```
    (placed after `frames`, before `session_id`; `Detection` is already defined earlier in the same file).
21. In `backend/app/routers/analyze.py`, change the `detect_phases` call to
    `phase_frames = detect_phases(request.frames, request.detections)`.
22. In `backend/tests/test_analyze.py`, add tests confirming the extended contract: POST with a
    `detections` field present (list of per-frame detection lists, can be empty lists) → `200 OK`, response
    shape unchanged; POST **without** `detections` (today's existing contract) → still `200 OK` unchanged.
23. Run `pytest backend/tests/test_phases.py backend/tests/test_analyze.py -v` — confirm all pass.

## Group 4 — Segmentation Report Tool (surface: `backend`)

24. Create `backend/tools/segmentation_report.py` with a module docstring following
    `pose_benchmark.py`/`calibration_report.py`'s style. Add the same
    `sys.path.insert(0, str(Path(__file__).parent.parent))` line.
25. Import `sample_video_frames` from `tools.pose_benchmark` and `_img_tag` from `tools.calibration_report`
    (both reused verbatim).
26. `def build_frame_sequence(video_path: Path, stride: int, pose_model, detection_model) -> tuple[list[Frame], list[list[Detection]], list[np.ndarray]]:`
    — calls `sample_video_frames`, then for each `(timestamp, image)` pair calls `pose_model.infer(image)`
    and `detection_model.infer(image)`, building a `Frame` and collecting the per-frame `detections` list
    and the raw image. Returns the three parallel lists.
27. `_PHASE_LABELS: dict[str, str]` — six-entry version of `calibration_report.py`'s constant, in Kovacs
    stage order: `{"start": "Start", "release": "Release (Toss)", "trophy_pose": "Loading (Trophy Pose)",
    "racket_drop": "Cocking (Racket Drop)", "contact": "Contact", "finish": "Finish"}`.
28. `def generate_segmentation_html(video_name: str, serve_segments: list[list[Frame]], serve_detections: list[list[list[Detection]]], phase_results: list[dict[ServePhase, Frame | None]], frame_index_map: dict[float, int], frame_paths: list[Path], output_dir: Path) -> Path:`
    — writes `<output_dir>/report.html`: one `<section>` per detected serve (mirroring
    `calibration_report.py`'s existing per-serve sectioning), each with an all-frames thumbnail strip for
    that serve's frame range and a six-wide phase highlight row (one `_img_tag` per `_PHASE_LABELS` entry,
    `"(not detected)"` placeholder when a phase is `None`, matching `calibration_report.py`'s existing
    style). `frame_index_map` maps each frame's timestamp back to its saved JPEG path so segments (which
    are slices of the full sequence) can look up the right image. Reuses the same page wrapper/CSS block
    style (`<title>Segmentation Report</title>`).
29. `def run_segmentation_report(video_paths: list[Path], stride: int, pose_model, detection_model, report_root: Path) -> list[Path]:`
    — for each video: calls `build_frame_sequence`; `cv2.imwrite`s each raw frame to
    `<report_root>/<video_stem>_segmentation/frames/frame{idx:03d}.jpg`; calls `segment_serves(frames)` to
    get serve boundaries, then slices the parallel `detections` list at the same boundaries; runs
    `detect_phases(segment_frames, segment_detections)` per serve; calls `generate_segmentation_html` for
    that video's own `<video_stem>_segmentation/` directory. Returns the list of report paths.
30. `def main() -> None:` — argparse CLI mirroring `pose_benchmark.py`'s: `--videos` (default
    `"backend/tools/calibration_data/*.mov"`, same case-insensitive glob handling), `--stride` (default
    `5`), `--report-dir` (default `backend/tools/calibration_data`). Constructs real models via
    `get_pose_model()` / `get_object_detection_model()`. Calls `run_segmentation_report(...)`, prints each
    report path and, per video, how many serves were detected.
31. Write `backend/tests/test_segmentation_report.py` (new file), synthetic-fixture pattern matching
    `test_pose_benchmark.py`:
    - `StubPoseModel`/`StubDetectionModel` (reuse or mirror the ones in `test_pose_benchmark.py`).
    - `TestBuildFrameSequence`: synthetic video via `_make_video`; assert matching-length frame/detection/
      image lists.
    - `TestGenerateSegmentationHtml`: hand-built multi-serve `phase_results` (some phases `None` in some
      serves); assert `report.html` contains one section per serve and all six `_PHASE_LABELS` values.
    - `TestRunSegmentationReport`: end-to-end with one synthetic video built to contain two motion bursts
      separated by a rest gap (mirroring `test_segment_serves.py`'s two-serve fixture) and stub models;
      assert two serve sections appear in the generated report, and `frames/*.jpg` has the expected count.
    - Assert no real model class (`RTMPoseModel`, `ObjectDetectionModel`, `YOLO(`, `Body(`) is constructed
      anywhere in the file (same `grep` check as P3).
32. Run `pytest backend/tests/test_segmentation_report.py -v` and then the full `pytest backend/` —
    confirm zero failures and no real model load in the default suite.

## Group 5 — Manual Real-Footage Re-Validation & Heuristic Iteration (manual, backend-only, hard merge gate)

33. `cd backend && python tools/segmentation_report.py` (default args) against the four real
    `calibration_data/*.mov` videos — confirm it completes (weights already cached from P1–P3).
34. Open each generated `backend/tools/calibration_data/serve_N_segmentation/report.html` in a browser.
    For `serve_4.mov` specifically, confirm `segment_serves` produced **two** serve sections matching the
    two `Serve 1/2`/`Serve 2/2` entries in `serve_4_console.txt` — this is the phase's only real multi-serve
    ground truth. If it doesn't split correctly (or over/under-splits on the other three, single-serve
    videos), adjust `MIN_REST_FRAMES` / `LOW_MOTION_VELOCITY_THRESHOLD` in `phases.py` and re-run this tool
    (no test changes needed — these are runtime-tunable module constants) until the split is correct.
35. For each detected serve section, visually spot-check all six phase frames, paying particular attention
    to: whether the combined-signal `racket_drop` looks more correct than the elbow-only Phase 6 result
    for the same footage; whether `start`/`release`/`finish` land at plausible points given they have no
    prior calibration history. If a heuristic is visibly wrong, adjust the relevant constant
    (`RACKET_DROP_ELBOW_WEIGHT`/`RACKET_DROP_RACKET_WEIGHT`) or, if a structural fix is needed, note it —
    structural heuristic changes should still match this phase's already-reviewed function shapes; iterate
    on constants first.
36. Record, in this phase's `validation.md` run notes: the final tuned constant values, which phases (if
    any) still resolve to `None` on which videos, the `serve_4.mov` split-correctness result, and a
    qualitative comparison of the combined-signal vs. elbow-only `racket_drop` frame.
37. Run `scripts/verify.sh backend` — confirm the full pytest suite (including
    `test_segment_serves.py`, `test_segmentation_report.py`, and the extended `test_phases.py`/
    `test_analyze.py`) passes with zero failures.
38. Confirm no iOS files were touched at all this phase: `git diff --name-only develop...HEAD` contains no
    changes under `App/`.
