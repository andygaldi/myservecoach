# Phase P4 — Plan

> **Lite-isolation note:** every task group touches only `backend/`. No group modifies
> `PhaseReviewView`, the Lite pipeline/segmentation services, `ContentView`, or any file under `App/`.
> `RTMPoseModel`, `ObjectDetectionModel`, and `calibration_report.py` are consumed unmodified.

## Group 1 — Six-Frame Model & Positional Heuristics (surface: `backend`)

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
   (Order matches the Kovacs stage sequence; existing three members keep their string values, so
   `rules.json` and every existing `ServePhase.trophy_pose`/`racket_drop`/`contact` reference is
   unaffected.)
2. In `backend/app/engine/phases.py`, change the signature to
   `def detect_phases(frames: list[Frame], detections: list[list[Detection]] | None = None) -> dict[ServePhase, Frame | None]:`
   and import `Detection` from `app.models`.
3. Add, before the existing trophy-pose loop:
   ```python
   start_idx: int | None = 0 if frames else None
   ```
4. Add a `release_idx` loop immediately after the `start_idx` line and before the existing trophy-pose
   loop:
   ```python
   release_idx: int | None = None
   for i, frame in enumerate(frames):
       toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
       toss_shoulder_y = keypoint_y(frame, f"{toss}_shoulder")
       if toss_wrist_y is None or toss_shoulder_y is None:
           continue
       if toss_wrist_y > toss_shoulder_y:
           release_idx = i
           break
   ```
5. After the existing contact-detection block, add:
   ```python
   finish_idx: int | None = len(frames) - 1 if frames else None
   ```
6. Update the function's final return dict to include all six keys:
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
7. In `backend/tests/test_phases.py`, add a new `# --- Start / Release / Finish detection ---` section:
   - `test_start_is_first_frame`: `detect_phases([f0, f1])` → `result[ServePhase.start] is f0`.
   - `test_start_is_none_for_empty_frames`: `detect_phases([])` → `result[ServePhase.start] is None`
     (and `finish` is also `None`).
   - `test_finish_is_last_frame`: `detect_phases([f0, f1, f2])` → `result[ServePhase.finish] is f2`.
   - `test_release_is_earliest_toss_rise_frame`: build `f0` with toss wrist below toss shoulder (pre-toss),
     `f1` with toss wrist above toss shoulder (matches `TROPHY_KPS`'s existing relationship), `f2` also
     qualifying — assert `result[ServePhase.release] is f1` (first qualifying frame, not `f2`).
   - `test_release_none_when_toss_never_rises`: all frames have toss wrist below toss shoulder → assert
     `result[ServePhase.release] is None`.
   - `test_release_skips_frames_missing_toss_keypoints`: `f0` missing `left_wrist`, `f1` qualifying →
     assert `result[ServePhase.release] is f1`.
8. Run `pytest backend/tests/test_phases.py -v` — confirm all pre-existing tests still pass unmodified
   and the new Group 1 tests pass.

## Group 2 — Racket-Augmented Racket-Drop Detection (surface: `backend`)

9. In `backend/app/engine/phases.py`, add a module-level helper above `detect_phases`:
   ```python
   def _racket_center_y(dets: list[Detection]) -> float | None:
       racket = next((d for d in dets if d.label == "racket"), None)
       if racket is None:
           return None
       return (racket.bbox.y_min + racket.bbox.y_max) / 2.0
   ```
10. Replace the existing racket-drop block (currently the elbow-y-rise loop) with a version that tries
    the racket signal first, falling back to the existing elbow-based logic:
    ```python
    drop_idx: int | None = None
    if trophy_idx is not None and contact_idx is not None:
        racket_candidates: list[tuple[int, float]] = []
        if detections is not None:
            for i in range(trophy_idx + 1, contact_idx):
                if i >= len(detections):
                    continue
                center_y = _racket_center_y(detections[i])
                if center_y is not None:
                    racket_candidates.append((i, center_y))

        if racket_candidates:
            drop_idx = min(racket_candidates, key=lambda pair: pair[1])[0]
        else:
            max_elbow_rise = float("-inf")
            for i in range(trophy_idx + 1, contact_idx):
                elbow_y_curr = keypoint_y(frames[i], f"{hitting}_elbow")
                elbow_y_prev = keypoint_y(frames[i - 1], f"{hitting}_elbow")
                if elbow_y_curr is None or elbow_y_prev is None:
                    continue
                delta = elbow_y_curr - elbow_y_prev
                if delta > max_elbow_rise:
                    max_elbow_rise = delta
                    drop_idx = i
    ```
    (This is a direct in-place replacement of the current `# 3. Racket drop: ...` block; the elbow-based
    `else` branch is byte-for-byte the pre-existing logic, so every existing racket-drop test continues to
    pass since none of them pass a `detections` argument.)
11. In `backend/tests/test_phases.py`, add a `# --- Racket-augmented racket-drop detection ---` section:
    - `test_racket_drop_uses_racket_signal_when_present`: build a 4-frame sequence (trophy, two
      candidate mid-frames, contact) where the elbow-rise heuristic would pick a *different* frame than
      the racket-lowest-center-y frame; pass a `detections` list (using `Detection`/`BoundingBox` from
      `app.models`) where one mid-frame has a racket detection with a low center-y and the other has none
      or a higher center-y; assert `detect_phases(frames, detections)[ServePhase.racket_drop]` is the
      racket-signal-chosen frame, not the elbow-signal-chosen one.
    - `test_racket_drop_falls_back_to_elbow_when_no_racket_detected`: same frame sequence, but pass
      `detections` as a list of empty lists (`[[], [], [], []]`) — assert the result matches the current
      elbow-based expectation (reuse `test_racket_drop_is_frame_with_largest_elbow_rise`'s fixture data),
      confirming the fallback path is exercised even when `detections` is provided but empty.
    - `test_racket_drop_ignores_ball_detections`: `detections` includes a `Detection(label="ball", ...)`
      entry with a very low center-y and no `"racket"` entry in that frame — assert the result still falls
      back to the elbow heuristic (ball detections must never influence `racket_drop`).
    - `test_racket_drop_detections_shorter_than_frames`: pass a `detections` list shorter than `frames`
      (simulating a partial/mismatched list) — assert no `IndexError` is raised and the function falls back
      to the elbow heuristic for the frames beyond the `detections` list's length.
12. In `backend/app/models.py`, add to `AnalyzeRequest`:
    ```python
    detections: list[list[Detection]] | None = None
    ```
    (placed after `frames`, before `session_id`; `Detection` is already defined earlier in the same file).
13. In `backend/app/routers/analyze.py`, change the `detect_phases` call to
    `phase_frames = detect_phases(request.frames, request.detections)`.
14. In `backend/tests/test_analyze.py`, add one new test confirming the extended contract is accepted and
    passed through: POST to `/analyze` with a request body that includes a `detections` field (list of
    per-frame detection lists, can be empty lists) alongside `frames` — assert `200 OK` and that the
    response shape is unchanged (existing `AnalyzeResponse` fields). Assert a request **without** the
    `detections` field (today's existing contract) still returns `200 OK` unchanged (backward compatibility).
15. Run `pytest backend/tests/test_phases.py backend/tests/test_analyze.py -v` — confirm all pass.

## Group 3 — Segmentation Report Tool (surface: `backend`)

16. Create `backend/tools/segmentation_report.py` with a module docstring following
    `pose_benchmark.py`/`calibration_report.py`'s style (purpose, usage example). Add the same
    `sys.path.insert(0, str(Path(__file__).parent.parent))` line.
17. Import `sample_video_frames` from `tools.pose_benchmark` (frame sampling, reused verbatim) and
    `_img_tag` from `tools.calibration_report` (thumbnail rendering, reused verbatim).
18. `def build_frame_sequence(video_path: Path, stride: int, pose_model, detection_model) -> tuple[list[Frame], list[list[Detection]], list[np.ndarray]]:`
    — calls `sample_video_frames(video_path, stride)`, then for each `(timestamp, image)` pair calls
    `pose_model.infer(image)` and `detection_model.infer(image)`, building a `Frame(timestamp=timestamp,
    keypoints=keypoints)` and collecting the per-frame `detections` list and the raw image (for later JPEG
    extraction). Returns the three parallel lists.
19. `_PHASE_LABELS: dict[str, str]` — six-entry version of `calibration_report.py`'s constant, in Kovacs
    stage order: `{"start": "Start", "release": "Release (Toss)", "trophy_pose": "Loading (Trophy Pose)",
    "racket_drop": "Cocking (Racket Drop)", "contact": "Contact", "finish": "Finish"}`.
20. `def generate_segmentation_html(video_name: str, frames: list[Frame], phase_frames: dict[ServePhase, Frame | None], frame_paths: list[Path], output_dir: Path) -> Path:`
    — writes `<output_dir>/report.html`: an all-frames thumbnail strip (`_img_tag` per extracted JPEG,
    highlighted border on any frame matching a detected phase's timestamp) followed by a six-wide phase
    highlight row (one `_img_tag` per `_PHASE_LABELS` entry, `"(not detected)"` placeholder matching
    `calibration_report.py`'s existing style when a phase is `None`). Reuses the same page wrapper/CSS
    block style (`<title>Segmentation Report</title>`, same `body`/`h1`/`section` CSS as
    `calibration_report.py`).
21. `def run_segmentation_report(video_paths: list[Path], stride: int, pose_model, detection_model, report_root: Path) -> list[Path]:`
    — for each video: calls `build_frame_sequence`, `cv2.imwrite`s each raw frame to
    `<report_root>/<video_stem>_segmentation/frames/frame{idx:03d}.jpg`, calls
    `detect_phases(frames, detections)`, then `generate_segmentation_html` for that video's own
    `<video_stem>_segmentation/` directory. Returns the list of report paths.
22. `def main() -> None:` — argparse CLI mirroring `pose_benchmark.py`'s: `--videos` (default
    `"backend/tools/calibration_data/*.mov"`, same case-insensitive glob handling), `--stride` (default
    `5`), `--report-dir` (default `backend/tools/calibration_data`). Constructs real models via
    `get_pose_model()` / `get_object_detection_model()`. Calls `run_segmentation_report(...)`, prints each
    report path.
23. Write `backend/tests/test_segmentation_report.py` (new file) using the same synthetic-fixture pattern
    as `test_pose_benchmark.py`/`test_calibration_report.py`:
    - `StubPoseModel`/`StubDetectionModel` (reuse the pattern from `test_pose_benchmark.py`, or import if
      module-scope stubs there are reusable without triggering real model construction).
    - `TestBuildFrameSequence`: synthetic video via `_make_video`; assert `build_frame_sequence` returns
      frame/detection/image lists of matching length equal to the sampled-frame count.
    - `TestGenerateSegmentationHtml`: hand-built `phase_frames` dict (some `None`, some present); assert
      `report.html` is created and contains all six `_PHASE_LABELS` values as text.
    - `TestRunSegmentationReport`: end-to-end with one tiny synthetic video and the stub models; assert the
      returned report path exists, `frames/*.jpg` has the expected count, and the HTML contains
      `"(not detected)"` for at least one phase (stub keypoints/detections should be sparse enough that not
      all six phases resolve).
    - Assert no real model class (`RTMPoseModel`, `ObjectDetectionModel`, `YOLO(`, `Body(`) is constructed
      anywhere in the file — same `grep` check as P3.
24. Run `pytest backend/tests/test_segmentation_report.py -v` and then the full `pytest backend/` —
    confirm zero failures and no real model load in the default suite.

## Group 4 — Manual Real-Footage Re-Validation (manual, backend-only, hard merge gate)

25. `cd backend && python tools/segmentation_report.py` (default args) against the four real
    `calibration_data/*.mov` videos — confirm it completes (weights already cached from P1–P3).
26. Open each generated `backend/tools/calibration_data/serve_N_segmentation/report.html` in a browser —
    visually spot-check that all six phase frames land in plausible locations relative to the source
    video, paying particular attention to whether the racket-augmented `racket_drop` frame looks more
    correct than the prior elbow-only heuristic did in the Phase 6 / P3 reports for the same footage.
27. Record, in this phase's `validation.md` run notes: which phases resolved to `None` on which videos (if
    any), and a qualitative comparison of the racket-augmented vs. elbow-only `racket_drop` frame for at
    least one video where a racket was reliably detected in the trophy→contact window.
28. Run `scripts/verify.sh backend` — confirm the full pytest suite (including
    `test_segmentation_report.py` and the extended `test_phases.py`/`test_analyze.py`) passes with zero
    failures.
29. Confirm no iOS files were touched at all this phase: `git diff --name-only develop...HEAD` contains no
    changes under `App/`.
