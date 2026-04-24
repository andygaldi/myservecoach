# Roadmap

Phases are intentionally small and independently testable. Each phase should produce working, committable code before moving to the next.

Legend: ✅ Complete · 🔄 In Progress · ⬜ Pending

---

## Phase 0 — Project Foundation ✅

Basic SwiftUI project scaffold with folder structure matching the CLAUDE.md architecture.

## Phase 1 — Video Capture UI ✅

Camera view (full-screen portrait), record/stop button, post-recording preview playback. AVFoundation `AVCaptureSession` pipeline writing to a temp file. Real-device only; Simulator shows a placeholder.

## Phase 2 — On-Device Pose Estimation & Serve Segmentation ⬜

Sample frames from the recorded video at a fixed interval. Run `VNDetectHumanBodyPoseRequest` on each frame. Detect serve boundaries by analyzing keypoint velocity across the frame sequence. Output is a list of per-serve keypoint arrays, not a flat stream. Log segmented keypoint JSON to the console. No backend call yet.

## Phase 3 — Backend Scaffold ⬜

FastAPI project with a `POST /analyze` endpoint. Accepts a single serve's keypoint JSON, returns a hardcoded list of coaching cues. This single-serve contract is shared by both workflows — Assessment loops one call per segmented serve; Set Goal calls it once per detected serve. Confirms the iOS ↔ backend contract before any real logic is written.

## Phase 4 — Coaching Rule Engine ⬜

Implement `rules.json` threshold config and angle computation utilities. Serve phase detection (trophy pose, racket drop, contact point). Unit-tested with pytest. Backend now returns real cues instead of hardcoded ones.

## Phase 5 — iOS Networking ⬜

URLSession `async/await` layer. For each segmented serve from Phase 2, POST its keypoint JSON to the Phase 3/4 backend (one call per serve). Collect the cue responses and surface them in a basic SwiftUI text view.

## Phase 6 — Results Screen ⬜

Dedicated SwiftUI results screen: session date/time header, one keyframe thumbnail per segmented serve (contact-point frame; no skeleton yet), scrollable list of coaching cues per serve. Displayed immediately after analysis completes.

## Phase 7 — SwiftData Persistence ⬜

SwiftData models: `ServeSession` (full clip metadata — date, duration, total serves) with child `ServeAttempt` records (one per segmented serve, each holding its keypoints and coaching cues). History list screen shows past sessions; tap to re-open results.

## Phase 8 — Assessment MVP Polish ⬜

Loading/progress states during analysis. Error handling (network failure, no pose detected). Empty states for history screen. Basic app icon and launch screen. **Assessment workflow complete.**

## Phase 9 — Goal Library & Selection UI ⬜

Define the goal catalog: each goal maps to one specific rule/metric in `rules.json` (e.g., `pronation_contact`, `trophy_pose_elbow_height`). Backend `POST /analyze` accepts an optional `goal_id`; when present, returns a `goal_result: { passed: bool, spoken_cue: String }` alongside normal cues. SwiftUI goal-selection screen presented before starting a Set Goal session.

## Phase 10 — Set Goal Session Mode ⬜

Continuous recording session: `AVCaptureSession` runs uninterrupted from session start to "End Session". On-device serve detection (same keypoint velocity algorithm from Phase 2, applied to the live feed) automatically identifies each serve as it happens. After each detected serve: analyze keypoints → POST to backend with `goal_id` → speak the `spoken_cue` result via AVSpeechSynthesizer → resume listening for the next serve. Player never needs to touch the screen between serves. When the session ends the video is discarded; only keypoints and pass/fail results are persisted.

## Phase 11 — Goal Session Persistence ⬜

SwiftData models for `GoalSession` and `GoalAttempt` (per-serve pass/fail + spoken cue). Summary screen after ending a session (pass rate, attempt count). Goal sessions appear in history alongside Assessment sessions. **Set Goal workflow complete.**

## Phase 12 — LLM Coaching Cues ⬜

Integrate Claude API in the backend. Pass rule violations + keypoints to Claude to generate natural-language coaching paragraphs. Displayed as an expandable section below the cue list in the Assessment results screen.

## Phase 13 — Pose Skeleton Overlay ⬜

Draw the detected skeleton on keyframe thumbnails in the results screen using SwiftUI `Canvas` or Core Graphics. Gives players visual confirmation that pose detection worked correctly.
