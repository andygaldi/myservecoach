# Roadmap

Phases are intentionally small and independently testable. Each phase should produce working, committable code before moving to the next.

Legend: ✅ Complete · 🔄 In Progress · ⬜ Pending

---

## Phase 0 — Project Foundation ✅

Basic SwiftUI project scaffold with folder structure matching the CLAUDE.md architecture.

## Phase 1 — Video Capture UI ✅

Camera view (full-screen portrait), record/stop button, post-recording preview playback. AVFoundation `AVCaptureSession` pipeline writing to a temp file. Real-device only; Simulator shows a placeholder.

## Phase 2 — On-Device Pose Estimation & Serve Segmentation ✅

Sample frames from the recorded video at a fixed interval. Run `VNDetectHumanBodyPoseRequest` on each frame. Detect serve boundaries by analyzing keypoint velocity across the frame sequence. Output is a list of per-serve keypoint arrays, not a flat stream. Log segmented keypoint JSON to the console. No backend call yet.

## Phase 3 — Backend Scaffold ✅

FastAPI project at `backend/` in the same repo as the iOS app. Implements a `POST /analyze` endpoint that accepts a single serve's keypoint JSON and returns a hardcoded list of coaching cues. This single-serve contract is shared by both workflows — Assessment loops one call per segmented serve; Set Goal calls it once per detected serve. Confirms the iOS ↔ backend contract before any real logic is written.

## Phase 4 — Coaching Rule Engine ✅

Implement `rules.json` threshold config and angle computation utilities. Serve phase detection (trophy pose, racket drop, contact point). Unit-tested with pytest. Backend now returns real cues instead of hardcoded ones.

## Phase 5 — Video Library Import ⬜

Video input selection screen presented at the start of an Assessment session. The user chooses between recording a new clip live or picking an existing video from their Photos library. Selecting a library video feeds it through the same Phase 2 pipeline (frame sampling → pose estimation → serve segmentation) and into the normal assessment flow — results and persistence are identical regardless of input source. Uses SwiftUI's `PhotosPicker` (iOS 16+) to request only the video asset, avoiding a full Photos library permission prompt.

## Phase 6 — Segmentation Calibration ⬜

Validate and tune the heuristic phase detection logic against real serve footage. Input videos come from two sources: clips recorded directly with the iOS app and external serve videos imported via the Phase 5 Photos library picker — both go through the same on-device Vision pose estimation pipeline. Export the keypoint JSON from the Xcode console and the video file from the device (AirDrop or Files app). A Python script in `backend/tools/` takes those two files, extracts frame images using OpenCV at the timestamps in the keypoint JSON, and produces an HTML report showing thumbnails of every sampled frame alongside highlighted images of the frame identified for each phase (trophy pose, racket drop, contact). No pose estimation happens in the Python tool — it only handles frame extraction and layout. Compare the report against the source video and adjust `phases.py` heuristics until all three phases land on the visually correct frames across a representative set of serves.

## Phase 7 — Rule Calibration ⬜

Ground the rule thresholds in real biomechanics. Using the same serve videos from Phase 6, run a developer script (`backend/tools/analyze_angles.py`) that prints all joint angles and relative positions at each validated phase frame for each serve. Compare measured values from technically sound serves against the current `rules.json` thresholds. Update thresholds — and add, remove, or re-weight rules — to reflect what a good serve actually looks like. Both tools are checked into `backend/tools/` as permanent dev utilities.

## Phase 8 — iOS Networking ⬜

URLSession `async/await` layer. For each segmented serve from Phase 2, POST its keypoint JSON to the Phase 3/4 backend (one call per serve). Collect the cue responses and surface them in a basic SwiftUI text view.

## Phase 9 — Results Screen ⬜

Dedicated SwiftUI results screen: session date/time header, one keyframe thumbnail per segmented serve (contact-point frame; no skeleton yet), scrollable list of coaching cues per serve. Displayed immediately after analysis completes.

## Phase 10 — SwiftData Persistence ⬜

SwiftData models: `ServeSession` (full clip metadata — date, duration, total serves) with child `ServeAttempt` records (one per segmented serve, each holding its keypoints and coaching cues). History list screen shows past sessions; tap to re-open results.

## Phase 11 — Assessment MVP Polish ⬜

Loading/progress states during analysis. Error handling (network failure, no pose detected). Empty states for history screen. Basic app icon and launch screen. **Assessment workflow complete.**

## Phase 12 — Goal Library & Selection UI ⬜

Define the goal catalog: each goal maps to one specific rule/metric in `rules.json` (e.g., `pronation_contact`, `trophy_pose_elbow_height`). Backend `POST /analyze` accepts an optional `goal_id`; when present, returns a `goal_result: { passed: bool, spoken_cue: String }` alongside normal cues. SwiftUI goal-selection screen presented before starting a Set Goal session.

## Phase 13 — Set Goal Session Mode ⬜

Continuous recording session: `AVCaptureSession` runs uninterrupted from session start to "End Session". On-device serve detection (same keypoint velocity algorithm from Phase 2, applied to the live feed) automatically identifies each serve as it happens. After each detected serve: analyze keypoints → POST to backend with `goal_id` → speak the `spoken_cue` result via AVSpeechSynthesizer → resume listening for the next serve. Player never needs to touch the screen between serves. When the session ends the video is discarded; only keypoints and pass/fail results are persisted.

## Phase 14 — Goal Session Persistence ⬜

SwiftData models for `GoalSession` and `GoalAttempt` (per-serve pass/fail + spoken cue). Summary screen after ending a session (pass rate, attempt count). Goal sessions appear in history alongside Assessment sessions. **Set Goal workflow complete.**

## Phase 15 — LLM Coaching Cues ⬜

Integrate Claude API in the backend. Pass rule violations + keypoints to Claude to generate natural-language coaching paragraphs. Displayed as an expandable section below the cue list in the Assessment results screen.

## Phase 16 — Pose Skeleton Overlay & Live Confidence Check ⬜

Two related features sharing the same skeleton-rendering layer:

**Pre-recording confidence check**: Before an Assessment or Set Goal session begins, the camera view runs `VNDetectHumanBodyPoseRequest` on the live feed and draws a real-time skeleton overlay on screen. Joint confidence is evaluated against the same thresholds used during analysis; if key joints (shoulders, elbows, wrists, hips) fall below the minimum, a prominent warning prompts the user to adjust their position, lighting, or camera angle before proceeding. The user taps "Looks good" to dismiss the check and start recording.

**Results-screen overlay**: Draw the detected skeleton on keyframe thumbnails in the results screen using SwiftUI `Canvas` or Core Graphics, giving players visual confirmation that pose detection worked correctly on the recorded footage.

Both surfaces share the same joint-drawing component; the confidence check adds the live-feed sampling loop and the threshold-based warning UI on top.
