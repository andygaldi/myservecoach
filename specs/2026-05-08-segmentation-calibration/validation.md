# Phase 6 — Segmentation Calibration: Validation

## How to Know Phase 6 is Complete

### 1. iOS Refactoring Prerequisites

- The app builds without errors or warnings on Xcode (Swift 6 strict concurrency).
- All existing XCTest unit tests pass unchanged.
- Manual smoke test on a real device: Assessment recording flow (record live) and Assessment library import flow (PhotosPicker) both complete end-to-end with no behavioral difference from before the refactor.
- `grep` for the old permission-closure patterns confirms they no longer appear in both view models — only in the shared abstraction.

### 2. Python Calibration Tool

- Running `python backend/tools/calibration_report.py --keypoints <path> --video <path> --output <dir>` exits with code 0 and writes an `index.html` to the output directory.
- Opening `index.html` in a browser shows one section per segmented serve.
- Each section contains:
  - A visible strip of sampled frame thumbnails (at least 3 frames per serve for a typical 1-second serve window at the chosen sampling rate)
  - Three images clearly labeled **Trophy Pose**, **Racket Drop**, and **Contact Point**
- The tool runs against a synthetic keypoint JSON (from `backend/tools/tests/` or equivalent) and produces a valid report without a real video — confirms the logic is unit-testable in CI without device footage.
- No pose estimation code appears in the tool (`VNDetectHumanBodyPoseRequest` or equivalent Python vision calls are absent).

### 3. Calibration Execution

**Inputs used:**
- At least 2 distinct video clips
- At least 5 individual serves total across those clips
- At least one clip sourced from live recording and at least one from library import (to confirm both input paths produce equivalent keypoint JSON)

**Pass criteria (visual spot-check per serve):**

| Phase | Correct frame lands on… |
|---|---|
| Trophy Pose | Frame where ball is near or at its peak and the hitting-arm elbow is at approximately shoulder height or above |
| Racket Drop | Frame with the lowest visible racket-head position (maximum external shoulder rotation / "back-scratch" position) |
| Contact Point | Frame closest to ball–racket impact (racket arm near full extension, ball leaving the strings or at the snap point) |

All three phases pass the visual check for every serve in the test set before the PR is merged.

**Artifacts committed:**
- Updated `phases.py` with adjusted heuristics
- A brief commit message noting the number of clips and serves used for validation (e.g., "validated against 2 clips, 7 serves")

### Merge Gate Summary

| Gate | Check |
|---|---|
| iOS build | Clean build, Swift 6 strict concurrency, no new warnings |
| iOS tests | All XCTest unit tests pass |
| iOS manual | Both recording and library import Assessment flows work on device |
| Tool smoke test | `calibration_report.py` produces valid HTML from synthetic inputs |
| Calibration | All three phase frames visually correct across ≥5 serves from ≥2 clips |
| Code | No pose estimation in the Python tool; no old permission-closure pattern in both view models |
