# Roadmap

Phases are intentionally small and independently testable. Each phase should produce working, committable code before moving to the next.

Legend: ✅ Complete · 🔄 In Progress · ⬜ Pending

---

## Lite Version MVP

### Phase 0 — Project Foundation ✅

Basic SwiftUI project scaffold with folder structure matching the CLAUDE.md architecture.

### Phase 1 — Video Capture UI ✅

Camera view (full-screen portrait), record/stop button, post-recording preview playback. AVFoundation `AVCaptureSession` pipeline writing to a temp file. Real-device only; Simulator shows a placeholder.

### Phase 2 — On-Device Pose Estimation & Serve Segmentation ✅

Sample frames from the recorded video at a fixed interval. Run `VNDetectHumanBodyPoseRequest` on each frame. Detect serve boundaries by analyzing keypoint velocity across the frame sequence. Output is a list of per-serve keypoint arrays, not a flat stream. Log segmented keypoint JSON to the console. No backend call yet.

### Phase 3 — Backend Scaffold ✅

FastAPI project at `backend/` in the same repo as the iOS app. Implements a `POST /analyze` endpoint that accepts a single serve's keypoint JSON and returns a hardcoded list of coaching cues. This single-serve contract is shared by both workflows — Assessment loops one call per segmented serve; Set Goal calls it once per detected serve. Confirms the iOS ↔ backend contract before any real logic is written.

### Phase 4 — Coaching Rule Engine ✅

Implement `rules.json` threshold config and angle computation utilities. Serve phase detection (trophy pose, racket drop, contact point — corresponding to Stages 3, 4, and 6 of the Kovacs 8-stage serve model; see Pro Version Phase P3 for the complete six-frame model). Unit-tested with pytest. Backend now returns real cues instead of hardcoded ones.

### Phase 5 — Video Library Import ✅

Video input selection screen presented at the start of a session. The user chooses between recording a new clip live or picking an existing video from their Photos library. Selecting a library video feeds it through the same Phase 2 pipeline (frame sampling → pose estimation → serve segmentation) and into the normal flow — results and persistence are identical regardless of input source. Uses SwiftUI's `PhotosPicker` (iOS 16+) to request only the video asset, avoiding a full Photos library permission prompt.

### Phase 6 — Segmentation Calibration ✅

Validate and tune the heuristic phase detection logic against real serve footage. Input videos come from two sources: clips recorded directly with the iOS app and external serve videos imported via the Phase 5 Photos library picker — both go through the same on-device Vision pose estimation pipeline. Export the keypoint JSON from the Xcode console and the video file from the device (AirDrop or Files app). A Python script in `backend/tools/` takes those two files, extracts frame images using OpenCV at the timestamps in the keypoint JSON, and produces an HTML report showing thumbnails of every sampled frame alongside highlighted images of the frame identified for each phase (trophy pose, racket drop, contact). No pose estimation happens in the Python tool — it only handles frame extraction and layout. Compare the report against the source video and adjust `phases.py` heuristics until all three phases land on the visually correct frames across a representative set of serves.

> **Outcome / pivot note**: Phase 6 established that on-device Vision pose estimation is not reliable enough for fully automated segmentation across real-world conditions (varied backgrounds, lighting, court lines). Automatic serve detection also cannot reliably identify racket position, which is critical for accurate phase classification. As a result, Phases 7+ pivot to a **Lite Version** model: the app still uses Vision for an initial phase-frame guess, but the user manually reviews and corrects the detected frames before comparison. Automated coaching cues (Assessment, Set Goal workflows) are deferred to a future Pro Version that requires better pose estimation.

### Phase 7 — Manual Frame Selection UI ✅

After pose estimation runs and produces guessed phase frames (trophy pose, racket drop, contact point), present a "phase review" screen where the user can inspect each guessed frame and scrub through the video to select the correct frame if the guess is wrong. The three phases are shown in sequence; the user confirms each one. The confirmed frames are the canonical phase frames for the session — all downstream comparison and persistence use these frames, not the raw Vision output.

### Phase 8 — Reference Frame Backend & iOS Networking ✅

Pivot the FastAPI backend from a coaching rule engine to a reference frame API. The backend hosts a curated library of phase frames from high-quality serves (trophy pose, racket drop, contact point), organized by phase key. Implement a `GET /reference-frames` endpoint that returns the reference frame library (URLs or base64-encoded images). iOS fetches reference frames via URLSession `async/await` at the end of the phase review step. Network required; show a clear error if the fetch fails.

### Phase 9 — Side-by-Side Comparison Screen ✅

Dedicated SwiftUI results screen showing the user's confirmed phase frames alongside the fetched reference frames. One row per phase (trophy pose, racket drop, contact point): user's frame on the left, reference frame on the right, phase label above. The layout should make it immediately obvious which part of the motion each pair represents. Displayed immediately after the reference frames are fetched.

### Phase 10 — SwiftData Persistence ✅

SwiftData models: `ServeSession` (clip metadata — date, source, input type) with child `ServePhase` records (one per confirmed phase frame, each holding the frame timestamp, the phase key, and the URL/identifier of the reference frame shown). History list screen shows past sessions; tap to re-open the comparison view.

### Phase 11 — Lite MVP Polish ✅

Loading/progress states during pose estimation and reference frame fetch. Error handling (network failure, no pose detected, all phases unconfirmed). Empty states for history screen. Basic app icon and launch screen. **Lite Version MVP complete.**

---

## Pro Version (Deferred)

These phases are organized around two user-selectable capture tiers: a **single-camera tier** (iPhone only, 2D pose) and a **two-camera tier** (stereo rig, 3D pose), chosen at session setup. The single-camera 2D path ships first — end-to-end from foundation through coaching — before any stereo hardware is introduced. The two-camera 3D path then adds a parallel precision track. Both tiers remain available in the final product; 3D does not replace 2D. All phases are developed Mac-hosted (the Mac is already the Lite MVP backend; no new hardware needed to start). The final phase (P16) ports the proven pipeline to a Jetson Orin Nano for untethered on-court portability. P16 is explicitly deferrable; all preceding phases run identically on the Mac. No phases are scheduled yet. See `specs/offdevice-pipeline.md` for the full architecture.

**Off-Device 2D Foundation (P1–P3)** — replaces on-device Vision with a robust pose and object-detection pipeline. No new hardware needed.

### Pre-Pro Cleanup ✅

Before starting Pro phases, fix the following items surfaced during loop-based tooling adoption:

- **Stale iOS tests in `MyServeCoachTests.swift`** — three tests reference `Serve` and `RecordServeViewModel` types that no longer exist. These cause `scripts/verify.sh ios` to report build failures unrelated to actual code changes. Delete or rewrite them against the current model.

### Phase P1 — Off-Device 2D Pose Service (Mac dev host)

iPhone POSTs sampled frames to the Mac backend — the Mac is already the dev server (`BackendConfig.swift` hardcodes its LAN IP); no host migration needed. Mac runs a strong 2D pose model (RTMPose or YOLO-Pose via PyTorch-MPS / CoreML / ONNX Runtime) and returns per-frame keypoints, replacing on-device Vision as the keypoint source. Build the Vision-joint-name → backend-joint-name translation layer: iOS `PoseFrame.joints` uses Vision raw key names (`right_wrist_joint`, etc.); the backend `Frame.keypoints` schema expects `right_wrist`, `left_shoulder`, etc. Wire up the currently-stubbed iOS POST path — `App/Services/Coaching/CoachingService.swift` `LiveCoachingService.analyze()` is a `// TODO` pointing at a non-existent endpoint with a mismatched result type — and reconcile `CoachingResult` with the backend `AnalyzeResponse` in `models.py`.

### Phase P2 — Racket & Ball Object Detection

YOLO-class object detector on the Mac for the racket (and ball). Vision never supported racket detection; this is net-new capability. Returns bounding-box positions per frame alongside keypoints, giving the segmentation and phase-detection engines the racket-position signal they need.

### Phase P3 — Robust Automatic Multi-Stage Serve Segmentation

Combine off-device pose + racket-position signals + background handling (lighting and court-line robustness) to achieve reliable automatic segmentation detecting the six Kovacs key frames directly — the core capability Phase 6 concluded on-device Vision could not provide. Removes the Lite MVP's mandatory manual-frame-correction step (Phase 7 UI becomes optional QA rather than required). Re-validate using the `backend/tools/calibration_report.py` HTML-report workflow against the same serve footage used in Phase 6. Extends `backend/app/engine/phases.py` from 3 to 6 detected frames.

The six detected frames map to the following stages of the Kovacs & Ellenbecker (2011) biomechanical model — *A Biomechanical Review of the Tennis Serve* ([PMC3445225](https://pmc.ncbi.nlm.nih.gov/articles/PMC3445225/)):

| Stage | Name | Description | Kovacs angles / criteria | Legacy key |
|---|---|---|---|---|
| 1 | Start | Stance and initial alignment | Minimal muscle activation; ground force generation begins | *(new)* |
| 2 | Release | Ball toss | Toss slightly lateral to overhead; ~100° arm abduction target | *(new)* |
| 3 | Loading | Weight transfer and coil | Front knee flexion >15°; shoulder/pelvis lateral rear tilt; vertical GRF 1.68–2.12× body weight | `trophy_pose` |
| 4 | Cocking | Trophy pose → max external rotation | Shoulder abduction 101° ± 13°; ext. rotation 172° ± 12°; elbow flexion 104° ± 12° | `racket_drop` |
| 5 | Acceleration | External rotation → contact | Peak leg EMG; lead knee extension velocity 800° ± 400°/s; trunk rotation reversal | *(dynamic phase — not a discrete frame)* |
| 6 | Contact | Ball strike | Trunk tilt 48° ± 7°; shoulder abduction ~100–110°; elbow flexion 20° ± 4° | `contact` |
| 7 | Deceleration | Arm and trunk deceleration | Eccentric shoulder distraction 0.5–0.75× body weight; up to 300 N·m trunk-arm deceleration torque | *(dynamic phase — not a discrete frame)* |
| 8 | Finish | Front-foot landing | Horizontal braking forces; eccentric lower-body loading | *(new)* |

Stages 5 (Acceleration) and 7 (Deceleration) are continuous motion phases between key frames, not single poses — they are not detected as discrete frames. The Lite MVP captured stages 3, 4, and 6 only (trophy pose, racket drop, contact point). This phase adds Start, Release, and Finish, completing the six-frame model. Frame detection runs on 2D pose + racket signals and works for both the single-camera and two-camera tiers.

**Single-Camera Coaching — 2D tier (P4–P6)** — the first fully usable Pro experience; iPhone-only, no stereo hardware needed. The coaching engine built in Lite Phases 3–4 is dormant in the Lite MVP; these phases activate it on 2D angles.

### Phase P4 — Rule Calibration (2D)

Ground the `rules.json` thresholds in real 2D-measured joint angles now that reliable phase frames are available from P3. Run `backend/tools/analyze_angles.py` against the validated P3 phase frames and compare measured 2D joint angles against the current thresholds; update, add, remove, or re-weight rules accordingly. Note the 2D-projection caveat — foreshortening from a single camera systematically underestimates angles like shoulder external rotation; these thresholds serve the single-camera tier and are re-derived on 3D angles in Phase P9.

### Phase P5 — Automated Coaching Cues / Assessment (2D)

For each auto-detected phase frame, POST keypoints to `POST /v1/analyze`; receive and display the `AnalyzeResponse` cue list on a coaching-results screen. Add SwiftData fields to persist cues alongside the phase frames already stored. Requires P3 (automatic segmentation) and P4 (calibrated 2D rules).

### Phase P6 — Goal Library & Set Goal Session Mode (2D)

Continuous recording session with automatic per-serve detection (P3) and per-serve analysis. Define a goal catalog; backend returns `goal_result: { passed: bool, spoken_cue: String }` alongside normal cues. Deliver audible pass/fail feedback via `AVSpeechSynthesizer` so the player can stay focused on the court between serves. Mac-hosted; becomes field-portable after the P16 Jetson migration.

**Two-Camera 3D Foundation (P7–P8)** — adds a stereo rig and true 3D angles. Mac + two USB webcams; no Jetson hardware needed.

### Phase P7 — Stereo Camera Rig & Calibration

Two USB webcams on the Mac; OpenCV stereo intrinsics/extrinsics calibration (`cv2.calibrateCamera` per camera, then `cv2.stereoCalibrate`); synchronized dual capture; calibration matrices saved to `stereoCalibration.json` and loaded at backend startup. Introduces `backend/tools/stereo_calibrate.py`. Proves the stereo geometry without any Jetson hardware — the iPhone shifts from primary camera to controller and display on this path. Adds a camera-mode selection step at session setup (single-camera 2D vs. two-camera 3D) that gates which capture pipeline and coaching tier runs downstream.

### Phase P8 — 3D Pose Triangulation & Angles

Triangulate 2D keypoints from both stereo views into 3D joint coordinates using `cv2.triangulatePoints`. Compute true 3D biomechanical angles — for example, the Kovacs 172° shoulder external rotation target is measured in 3D; 2D projection from a single angle systematically underestimates it. Add `compute_angle_3d` to `backend/app/engine/angles.py` *alongside* the existing 2D `compute_angle` — both functions are retained; rules consume whichever angle source matches the active tier.

**Two-Camera Coaching — 3D precision tier (P9–P11)** — each phase extends its 2D counterpart; the shared cue UI and goal engine carry over, with the 3D angle source and re-calibrated thresholds as the key differences.

### Phase P9 — Rule Calibration (3D)

Re-run `backend/tools/analyze_angles.py` against 3D angles from P8 to derive 3D-calibrated thresholds. Add a 3D-tier threshold variant to `rules.json` alongside the existing 2D-tier thresholds (similar structure to the per-serve-type variants introduced in P13). The precision tier now has rules that exploit the full biomechanical fidelity of triangulated joint positions.

### Phase P10 — Coaching Cues (3D)

Route the two-camera 3D tier through the same coaching-cue UI introduced in P5, backed by the 3D-calibrated rules from P9. Surface the active capture tier (2D or 3D) on the results screen so the user understands which fidelity produced the cues.

### Phase P11 — Goal Library & Set Goal Session Mode (3D)

Extend the Set-Goal session mode from P6 to the 3D tier. Enables goals that only 3D can reliably measure — for example, true shoulder external rotation approaching the 172° Kovacs target — without the projection ambiguity of a single-camera view.

**Enhancements (P12–P15)** — additional capabilities layered on the foundation; each is independently testable and can be tackled in any order.

### Phase P12 — Pose Skeleton Overlay & Live Confidence Check

Pre-recording skeleton overlay on the live iPhone feed with a joint-confidence warning. Skeleton drawn on keyframe thumbnails in the results screen.

### Phase P13 — Serve-Type Awareness

Serve-type selection (flat, slice, kick) before recording. Backend applies serve-type-specific rule thresholds. `rules.json` restructured for per-type variants alongside the per-tier variants introduced in P9.

### Phase P14 — Multi-Angle Support

Pipeline extended to support behind-server and closed-side recording angles. Angle-selection step added to session setup; angle-specific segmentation heuristics and rule sets. Note: the stereo rig added in P7 already provides a second view for 3D triangulation — this phase adds the open-side / behind-server / closed-side *analysis angle* variants for single-camera sessions.

### Phase P15 — LLM Coaching Cues

Integrate the Claude API in the backend. Pass rule violations and keypoints to Claude to generate natural-language coaching paragraphs. Displayed as an expandable section below the structured cue list on the results screen. Tier-agnostic — enriches whichever capture tier is active. Explicitly the lowest-priority feature phase; can be skipped if the structured cue list is sufficient.

**On-Court Deployment (P16)** — the full pipeline is developed and validated Mac-hosted. This phase is a pure portability migration with no algorithm changes.

### Phase P16 — Jetson Orin Nano Migration & On-Court Portability

Port the proven Mac pipeline to a Jetson Orin Nano for untethered, battery-powered court use. Export RTMPose and YOLO models to TensorRT; move stereo capture from USB webcams to the Jetson's CSI camera ports; run the FastAPI backend on the Jetson over a local court Wi-Fi network or Jetson-broadcast hotspot — no cloud round-trip, all data stays on court. Update `App/Services/BackendConfig.swift` from the Mac LAN IP to the Jetson's address. No backend logic, model, or iOS app changes — only the serving runtime (TensorRT vs. ONNX Runtime) and camera I/O differ. Deferrable: can be pulled forward whenever on-court portability is wanted; everything before it runs identically on the Mac.
