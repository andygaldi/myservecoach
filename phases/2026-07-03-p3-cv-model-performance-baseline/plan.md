# Phase P3 — Plan

> **Lite-isolation note:** everything in this phase is backend developer tooling. No task group touches any
> file under `App/`. `pose_benchmark.py` calls the existing, unmodified P1 (`RTMPoseModel`) and P2
> (`ObjectDetectionModel`) services directly — no new endpoint, no iOS caller.

## Group 1 — Frame Sampling & Overlay Drawing Helpers (surface: `backend`)

1. Create `backend/tools/pose_benchmark.py` with module docstring following `calibration_report.py`'s style
   (purpose, usage example). Add:
   ```python
   sys.path.insert(0, str(Path(__file__).parent.parent))  # allow running from repo root or backend/
   ```
2. `def sample_video_frames(video_path: Path, stride: int) -> list[tuple[float, np.ndarray]]:` — opens
   `cv2.VideoCapture(str(video_path))`, reads `fps = cap.get(cv2.CAP_PROP_FPS) or 30.0`, then does a single
   sequential `cap.read()` loop counting a frame index; keeps `(timestamp, frame.copy())` for every frame
   where `idx % stride == 0`; releases the capture before returning. Raises `ValueError(f"could not open video:
   {video_path}")` if `cap.isOpened()` is `False`.
3. `LIMB_PAIRS: list[tuple[str, str]] = [...]` — backend keypoint-name pairs to connect with skeleton lines:
   `("left_shoulder", "right_shoulder")`, `("left_shoulder", "left_elbow")`, `("left_elbow", "left_wrist")`,
   `("right_shoulder", "right_elbow")`, `("right_elbow", "right_wrist")`, `("left_hip", "right_hip")`,
   `("left_shoulder", "left_hip")`, `("right_shoulder", "right_hip")`, `("left_hip", "left_knee")`,
   `("left_knee", "left_ankle")`, `("right_hip", "right_knee")`, `("right_knee", "right_ankle")`.
4. `_DETECTION_COLORS: dict[str, tuple[int, int, int]] = {"racket": (255, 128, 0), "ball": (0, 200, 0)}` (BGR,
   for `cv2.rectangle`/`cv2.putText`).
5. `def draw_overlay(image: np.ndarray, keypoints: dict[str, Keypoint], detections: list[Detection]) ->
   np.ndarray:` — works on `image.copy()`; imports `MIN_CONFIDENCE` from `app.engine.angles`. For each keypoint
   above `MIN_CONFIDENCE`: convert normalized/y-up coords to pixel space (`px = kp.x * w`, `py = (1.0 - kp.y) *
   h`) and `cv2.circle(out, (int(px), int(py)), 4, (0, 255, 255), -1)`. For each `LIMB_PAIRS` pair where both
   joints are present and above `MIN_CONFIDENCE`: `cv2.line(out, pt_a, pt_b, (0, 255, 255), 2)`. For each
   detection: convert its y-up-normalized bbox back to pixel space (`px_min = bbox.x_min * w`, `px_max =
   bbox.x_max * w`, `py_min = (1.0 - bbox.y_max) * h`, `py_max = (1.0 - bbox.y_min) * h`), draw
   `cv2.rectangle(out, (px_min, py_min), (px_max, py_max), _DETECTION_COLORS[det.label], 2)` and a
   `cv2.putText` label `f"{det.label} {det.confidence:.2f}"` above the box. Returns the annotated copy; never
   mutates the input array.
6. Write `backend/tests/test_pose_benchmark.py` (new file) — Group 1 tests only for now:
   - `TestSampleVideoFrames`: build a tiny synthetic video via a `_make_video(path, num_frames, fps)` helper
     (identical pattern to `test_calibration_report.py`'s); assert `sample_video_frames(path, stride=5)` on a
     60-frame video returns 12 entries with timestamps `0.0, 5/30, 10/30, ...`; assert `stride=1` returns all
     60 frames; assert `ValueError` is raised for a nonexistent path.
   - `TestDrawOverlay`: build a solid-color 64×64 synthetic `np.ndarray`; call `draw_overlay` with one
     keypoint dict (all `MIN_CONFIDENCE`-passing) and one detection; assert the returned array has the same
     shape as the input, is a different object (`result is not image`), and differs pixel-wise from the
     unannotated input (`not np.array_equal(result, image)`); assert calling `draw_overlay(image, {}, [])`
     (nothing to draw) still returns a same-shape copy without raising.
7. Run `pytest backend/tests/test_pose_benchmark.py -v` — confirm Group 1 tests pass.

## Group 2 — Per-Frame Benchmarking & Metrics Aggregation (surface: `backend`)

8. In `backend/tools/pose_benchmark.py`, add:
   ```python
   @dataclass
   class FrameResult:
       timestamp: float
       person_detected: bool
       keypoint_confidences: list[float]
       racket_detected: bool
       racket_confidence: float | None
       ball_detected: bool
       ball_confidence: float | None
       pose_latency_s: float
       detection_latency_s: float
       keypoints: dict[str, Keypoint]
       detections: list[Detection]
   ```
9. `def benchmark_frame(image: np.ndarray, pose_model, detection_model) -> FrameResult:` — times each model
   call with `time.perf_counter()`:
   ```python
   t0 = time.perf_counter()
   keypoints = pose_model.infer(image)
   pose_latency_s = time.perf_counter() - t0

   t0 = time.perf_counter()
   detections = detection_model.infer(image)
   detection_latency_s = time.perf_counter() - t0
   ```
   Builds `racket = next((d for d in detections if d.label == "racket"), None)` and same for `ball`;
   `person_detected = bool(keypoints)`; `keypoint_confidences = [kp.confidence for kp in keypoints.values()]`.
   Returns the populated `FrameResult`. Both `pose_model`/`detection_model` params are duck-typed (anything
   with `.infer(image)`) so tests can pass stubs without touching `RTMPoseModel`/`ObjectDetectionModel`.
10. `def benchmark_video(video_path: Path, pose_model, detection_model, stride: int) -> list[tuple[FrameResult,
    np.ndarray]]:` — calls `sample_video_frames`, then `benchmark_frame` per sampled frame, returning a list
    pairing each `FrameResult` with its original (un-annotated) frame array (needed by Group 3 to draw and
    save the overlay).
11. `def aggregate_stats(per_video: dict[str, list[FrameResult]], stride: int) -> dict:` — per video, computes:
    `frame_count`, `person_detection_rate` (mean of `person_detected`), `racket_detection_rate`,
    `ball_detection_rate`, `avg_keypoint_confidence` (mean of all `keypoint_confidences` flattened across
    frames, `None` if none present), `avg_racket_confidence`/`avg_ball_confidence` (mean over frames where
    detected, `None` if never detected), `avg_pose_fps` (`1.0 / mean(pose_latency_s)`), `avg_detection_fps`
    (`1.0 / mean(detection_latency_s)`). Then computes one `"aggregate"` entry pooling every frame across all
    videos with the same fields. Returns
    `{"generated_at": datetime.now(timezone.utc).isoformat(), "stride": stride, "videos": {name: stats, ...},
    "aggregate": stats}`. Raises nothing on an empty `per_video` frame list for a given video — reports `0.0`
    rates and `None` averages instead of dividing by zero.
12. Extend `backend/tests/test_pose_benchmark.py`:
    - Add `StubPoseModel` (`infer(image) -> dict[str, Keypoint]` returns a fixed dict, e.g. one keypoint at
      confidence `0.9`) and `StubDetectionModel` (`infer(image) -> list[Detection]` returns a fixed
      one-`racket`-detection list at confidence `0.8`) at module scope, both accepting no constructor args and
      doing no I/O.
    - `TestBenchmarkFrame`: call `benchmark_frame` with the stubs against a synthetic image; assert
      `person_detected is True`, `racket_detected is True`, `ball_detected is False`,
      `racket_confidence == pytest.approx(0.8)`, both latencies `>= 0.0`.
    - `TestAggregateStats`: hand-build a small `per_video` dict with known `FrameResult` values (e.g. 3 frames,
      2 with `racket_detected=True`) and assert `racket_detection_rate == pytest.approx(2 / 3)`,
      `avg_keypoint_confidence` and `avg_pose_fps` match hand-computed expected values, and the `"aggregate"`
      entry correctly pools frames from multiple videos.
13. Run `pytest backend/tests/test_pose_benchmark.py -v` — confirm Groups 1–2 tests pass.

## Group 3 — HTML Report Generation & CLI Orchestration (surface: `backend`)

14. In `backend/tools/pose_benchmark.py`, import `_img_tag` from `tools.calibration_report` (reused verbatim
    for thumbnail rendering) and add:
    `def generate_benchmark_html(video_name: str, results: list[FrameResult], frame_paths: list[Path],
    output_dir: Path) -> Path:` — writes `<output_dir>/report.html`: one section per video with a thumbnail
    strip (`_img_tag` per frame, using each frame's saved annotated JPEG path relative to `output_dir`) and a
    one-line caption per thumbnail (`person: yes/no | racket: yes (0.81)/no | ball: ... | Nms`). Reuses the
    same page wrapper/CSS block style as `calibration_report.py`'s `generate_html` (`<title>Pose Benchmark
    Report</title>`, same `body`/`h1`/`section` CSS). Returns the report path.
15. `def run_benchmark(video_paths: list[Path], stride: int, pose_model, detection_model, report_root: Path,
    baseline_dir: Path) -> Path:` — orchestrates the full run:
    - For each `video_path`: call `benchmark_video`; for each `(result, frame)` pair, call
      `draw_overlay(frame, result.keypoints, result.detections)` and `cv2.imwrite` it to
      `<report_root>/<video_stem>_benchmark/frames/frame{idx:03d}.jpg`; call `generate_benchmark_html` for that
      video's own `<video_stem>_benchmark/` directory.
    - Collect all videos' `FrameResult` lists into a `per_video: dict[str, list[FrameResult]]` keyed by
      `video_path.stem`, call `aggregate_stats`.
    - `baseline_dir.mkdir(parents=True, exist_ok=True)`; write the aggregate dict as pretty-printed JSON
      (`json.dumps(..., indent=2)`, **excluding** the `keypoints`/`detections` raw fields — only the numeric
      `FrameResult` fields feed `aggregate_stats`, so the dict returned by `aggregate_stats` already has no
      image/keypoint payloads) to
      `<baseline_dir>/<datetime.now().strftime('%Y-%m-%d-%H%M%S')>.json`.
    - Returns the baseline JSON path.
16. `def main() -> None:` — argparse CLI:
    - `--videos` (default `"backend/tools/calibration_data/*.mov"`, a glob string; resolved via
      `Path().parent.glob(...)` — must also match `*.MOV` per the existing mixed-case files, so glob
      case-insensitively by trying both `*.mov` and `*.MOV` patterns and de-duplicating).
    - `--stride` (`type=int`, default `5`).
    - `--report-dir` (default `backend/tools/calibration_data`, the parent under which each
      `<video_stem>_benchmark/` directory is created).
    - `--baseline-dir` (default `backend/tools/pose_benchmark_baselines`).
    - Exits with an error message (`sys.exit(...)`) if the video glob matches nothing.
    - Constructs real models via `get_pose_model()` / `get_object_detection_model()` (imported from
      `app.services.pose_model` / `app.services.object_detection` — reuses the existing `lru_cache`d
      singletons, no separate construction path).
    - Calls `run_benchmark(...)`, prints the resulting baseline path and a short console summary (overall
      detection rates + FPS) via the `"aggregate"` entry.
17. Add `backend/tools/pose_benchmark_baselines/` to version control readiness: no `.gitignore` entry needed
    (it's outside `tools/calibration_data/`, which is the only gitignored tools subpath); confirm via
    `git check-ignore backend/tools/pose_benchmark_baselines/test.json` that it is **not** ignored.
18. Extend `backend/tests/test_pose_benchmark.py` with an end-to-end synthetic test:
    - `TestRunBenchmark.test_report_and_baseline_created(tmp_path)`: generate one tiny synthetic video via
      `_make_video`, call `run_benchmark([video_path], stride=5, pose_model=StubPoseModel(),
      detection_model=StubDetectionModel(), report_root=tmp_path / "reports", baseline_dir=tmp_path /
      "baselines")`; assert the returned path exists and is valid JSON with top-level keys `generated_at`,
      `stride`, `videos`, `aggregate`; assert `<tmp_path>/reports/<stem>_benchmark/report.html` exists; assert
      `<tmp_path>/reports/<stem>_benchmark/frames/*.jpg` has the expected sampled-frame count.
    - Assert no real model class (`RTMPoseModel`, `ObjectDetectionModel`, `YOLO(`, `Body(`) is constructed
      anywhere in `test_pose_benchmark.py` — manual `grep` check, mirroring P2's isolation check.
19. Run `pytest backend/` — confirm the full suite (including the new file) passes with zero failures and no
    real model load anywhere in the default run.

## Group 4 — Manual Real-Footage Baseline Run (manual, backend-only)

20. `cd backend && python tools/pose_benchmark.py` (default args) against the real
    `backend/tools/calibration_data/serve_1.MOV` … `serve_4.mov` footage — confirm it completes, downloading
    RTMPose/YOLO weights on first run if not already cached (mirrors P1/P2's first-run download).
21. Open the generated `backend/tools/calibration_data/serve_1_benchmark/report.html` (and the other three) in
    a browser — visually spot-check that skeleton dots track the body and racket/ball boxes land in
    plausible locations across a sample of frames.
22. Record the resulting `backend/tools/pose_benchmark_baselines/<timestamp>.json` outcome (aggregate
    detection rates, avg confidences, avg FPS for both models) in this phase's `validation.md` notes, and
    `git add` the new baseline file (git-tracked, unlike the gitignored `*_benchmark/` report directories).
23. Run `scripts/verify.sh backend` — confirm the full pytest suite (including
    `test_pose_benchmark.py`) passes with zero failures.
24. Confirm no iOS files were touched at all this phase: `git diff --name-only develop...HEAD` contains no
    changes under `App/`.
