# Phase 6 — Segmentation Calibration: Requirements

## Scope

Phase 6 has three distinct deliverables:

1. **iOS refactoring** — two prerequisite cleanup items carried forward from the Phase 5 implementation that affect `CameraViewModel` and `VideoSourceSelectionViewModel`.
2. **Python calibration tool** — `backend/tools/calibration_report.py`, a permanent developer utility for visualizing phase detection results.
3. **Calibration execution** — actually running the tool against real serve footage and adjusting `phases.py` until phase detection is correct.

## What is In Scope

### iOS Refactoring

- Extract a shared `PermissionChecking` protocol (or similar abstraction) to unify the permission-checking closure shapes in `CameraViewModel` and `VideoSourceSelectionViewModel`.
- Extract a shared pipeline coordinator so both view models delegate `PoseAnalysisPipeline` Task management through a single component instead of each owning duplicated Task + error-handling code.
- No new user-visible behavior. The refactors are purely internal; both recording flows must work identically afterward.

### Calibration Tool (`backend/tools/calibration_report.py`)

- CLI script: `python calibration_report.py --keypoints <path> --video <path> --output <dir>`
- Inputs: keypoint JSON exported from the Xcode console + the source video file (AirDrop or Files app).
- Frame extraction: OpenCV only — no pose estimation. The tool reads timestamps or frame indices from the keypoint JSON and extracts the corresponding frames from the video using `cv2.VideoCapture`.
- Output: a static HTML report (no JavaScript) with one section per segmented serve. Each section contains:
  - A thumbnail strip of every sampled frame for that serve
  - Three larger labeled images — **Trophy Pose**, **Racket Drop**, **Contact Point** — clearly marked as phase frames
- The tool is checked into `backend/tools/` alongside the future `analyze_angles.py` (Phase 7).

### Calibration Execution

- Source footage: 2–3 clips, covering 5–10 individual serves in total, recorded with the iOS app or imported via the Phase 5 library picker. Both input paths exercise the same Vision pipeline and produce equivalent keypoint JSON.
- Inspect the HTML report serve-by-serve against the source video. Adjust `phases.py` heuristics until all three phase frames are visually correct across the full set.
- The adjusted `phases.py` is committed as the artifact; no automated accuracy metric is required.

## What is Out of Scope

- Pose estimation in the Python tool. Vision always stays in the iOS app; the tool uses only the keypoint JSON it receives as input.
- Automated regression testing of `phases.py` with real footage (deferred — would require a labeled ground-truth dataset).
- Phase 7 angle calibration. That phase uses a separate `analyze_angles.py` script and operates on rule thresholds, not segmentation heuristics.
- Any user-facing UI changes. This phase is entirely backend tooling and internal iOS cleanup.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Refactors in Phase 6 vs. separate chore | Included in Phase 6 | The two view models will otherwise diverge further as Phase 6 adds calibration-related logging hooks. Keeping them together avoids an extra branch cycle for a small change. |
| HTML report complexity | Minimal static HTML, no JS | The report is a developer diagnostic tool, not a user-facing feature. A simple static page is faster to build and sufficient for eyeballing mis-detections. |
| Calibration done criteria | Visual spot-check | A numeric accuracy target requires a labeled ground-truth dataset that doesn't exist yet. Human visual inspection against the source video is both faster and more meaningful at this stage. |
| Tool location | `backend/tools/` | Consistent with the roadmap's intent. Both Phase 6 and Phase 7 tools live here as permanent dev utilities. |

## Context

Phase 6 sits between Phase 5 (video library import, ✅ complete) and Phase 7 (rule calibration). The segmentation heuristics in `phases.py` were written against assumed serve geometry; this phase is where they are first validated against real footage. Phase 7 depends on correct phase frames — if trophy pose or contact point detection is wrong, the joint angles measured in Phase 7 will also be wrong. Getting Phase 6 right is therefore a prerequisite for meaningful rule calibration.

Both input sources — clips recorded live with the iOS app and videos imported via `PhotosPicker` — pass through the same Vision pipeline and produce structurally identical keypoint JSON. There is no distinction in the calibration tool or in `phases.py` between the two sources.
