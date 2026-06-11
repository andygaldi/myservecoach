# Phase 6 — Segmentation Calibration: Plan

## Task Group 1 — iOS Refactoring Prerequisites

These clean up code duplication introduced across Phases 1–5 before new calibration-specific iOS code is added.

1.1 Extract a shared `PermissionChecking` protocol (or equivalent abstraction) and consolidate the permission-checking pattern between `CameraViewModel` and `VideoSourceSelectionViewModel`. The two currently use slightly different injectable closure shapes for the same conceptual operation.

1.2 Extract a shared pipeline coordinator for the `PoseAnalysisPipeline` Task + error-handling pattern that `CameraViewModel` and `VideoSourceSelectionViewModel` both duplicate. The coordinator owns the Task lifecycle; both view models delegate to it.

1.3 Verify no behavioral change: existing unit tests pass, the Assessment recording flow and library import flow both complete end-to-end on device.

## Task Group 2 — Python Calibration Tool

Builds `backend/tools/calibration_report.py`, a developer script checked into the repo as a permanent utility.

2.1 Scaffold the CLI: accept `--keypoints <path>` (exported JSON from Xcode console), `--video <path>` (AirDropped or Files app export), and `--output <dir>` (where to write the HTML report and extracted frame images).

2.2 Parse the keypoint JSON. Collect the timestamp (or frame index) for every sampled frame and the three phase frames (trophy pose, racket drop, contact point) per segmented serve.

2.3 Extract frames from the video using OpenCV (`cv2.VideoCapture`) at the timestamps/indices identified in 2.2. Write each frame as a JPEG into `<output>/frames/`.

2.4 Generate a static HTML report (no JavaScript). Structure: one `<section>` per segmented serve containing —
  - A horizontal strip of all sampled frame thumbnails for that serve
  - Three larger highlighted images labeled **Trophy Pose**, **Racket Drop**, **Contact Point**, each bordered or captioned to distinguish them from the general strip

2.5 Smoke-test the tool against a synthetic keypoint JSON (hand-crafted, pointing at a short test video) to confirm the report renders before using real footage.

## Task Group 3 — Calibration Execution

Runs the tool against real footage and adjusts `phases.py` until phase detection is visually correct.

3.1 Record or import 2–3 serve clips (5–10 individual serves total) using the iOS app. Export the keypoint JSON from the Xcode console and the video file via AirDrop or the Files app.

3.2 Run `calibration_report.py` against each clip and open the HTML output in a browser.

3.3 For each serve in the report, compare the highlighted phase frames against the source video:
  - Does **Trophy Pose** land on the frame where the ball is near its peak and the elbow is at shoulder height or above?
  - Does **Racket Drop** land on the frame with the lowest racket head position (maximum external rotation)?
  - Does **Contact Point** land on the frame closest to ball–racket impact?

3.4 Identify which heuristics in `phases.py` cause mis-detections. Adjust thresholds, window sizes, or velocity/angle conditions until all three phases land correctly across the full serve set.

3.5 Commit the updated `phases.py` with a brief commit-message note on which clips were used for validation.
