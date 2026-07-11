# Roadmap

Phases are intentionally small and independently testable. Each phase should produce working, committable code before moving to the next.

Legend: ✅ Complete · 🔄 In Progress · ⬜ Pending

---

## Lite Mode (Mode 1 — Permanent)

### Phase 0 — Project Foundation ✅

Basic SwiftUI project scaffold with folder structure matching the CLAUDE.md architecture.

### Phase 1 — Video Capture UI ✅

Camera view (full-screen portrait), record/stop button, post-recording preview playback. AVFoundation `AVCaptureSession` pipeline writing to a temp file. Real-device only; Simulator shows a placeholder.

### Phase 2 — On-Device Pose Estimation & Serve Segmentation ✅

Sample frames from the recorded video at a fixed interval. Run `VNDetectHumanBodyPoseRequest` on each frame. Detect serve boundaries by analyzing keypoint velocity across the frame sequence. Output is a list of per-serve keypoint arrays, not a flat stream. Log segmented keypoint JSON to the console. No backend call yet.

### Phase 3 — Backend Scaffold ✅

FastAPI project at `backend/` in the same repo as the iOS app. Implements a `POST /analyze` endpoint that accepts a single serve's keypoint JSON and returns a hardcoded list of coaching cues. This single-serve contract is shared by both workflows — Assessment loops one call per segmented serve; Set Goal calls it once per detected serve. Confirms the iOS ↔ backend contract before any real logic is written.

### Phase 4 — Coaching Rule Engine ✅

Implement `rules.json` threshold config and angle computation utilities. Serve phase detection (trophy pose, racket drop, contact point — corresponding to Stages 3, 4, and 6 of the Kovacs 8-stage serve model; see Pro Version Phase P4 for the complete six-frame model). Unit-tested with pytest. Backend now returns real cues instead of hardcoded ones.

### Phase 5 — Video Library Import ✅

Video input selection screen presented at the start of a session. The user chooses between recording a new clip live or picking an existing video from their Photos library. Selecting a library video feeds it through the same Phase 2 pipeline (frame sampling → pose estimation → serve segmentation) and into the normal flow — results and persistence are identical regardless of input source. Uses SwiftUI's `PhotosPicker` (iOS 16+) to request only the video asset, avoiding a full Photos library permission prompt.

### Phase 6 — Segmentation Calibration ✅

Validate and tune the heuristic phase detection logic against real serve footage. Input videos come from two sources: clips recorded directly with the iOS app and external serve videos imported via the Phase 5 Photos library picker — both go through the same on-device Vision pose estimation pipeline. Export the keypoint JSON from the Xcode console and the video file from the device (AirDrop or Files app). A Python script in `backend/tools/` takes those two files, extracts frame images using OpenCV at the timestamps in the keypoint JSON, and produces an HTML report showing thumbnails of every sampled frame alongside highlighted images of the frame identified for each phase (trophy pose, racket drop, contact). No pose estimation happens in the Python tool — it only handles frame extraction and layout. Compare the report against the source video and adjust `phases.py` heuristics until all three phases land on the visually correct frames across a representative set of serves.

> **Outcome / pivot note**: Phase 6 established that on-device Vision pose estimation is not reliable enough for fully automated segmentation across real-world conditions (varied backgrounds, lighting, court lines). Automatic serve detection also cannot reliably identify racket position, which is critical for accurate phase classification. As a result, Phases 7+ pivot to a **Lite mode**: the app still uses Vision for an initial phase-frame guess, but the user manually reviews and corrects the detected frames before comparison. This is not a stopgap — Lite mode is **Mode 1 of three permanent, user-selectable modes** (see `specs/mission.md` "Capture Modes"). Automated coaching cues (Assessment, Set Goal workflows) are added by Pro 2D and Pro 3D mode (Modes 2 and 3) alongside Lite, not in place of it.

### Phase 7 — Manual Frame Selection UI ✅

After pose estimation runs and produces guessed phase frames (trophy pose, racket drop, contact point), present a "phase review" screen where the user can inspect each guessed frame and scrub through the video to select the correct frame if the guess is wrong. The three phases are shown in sequence; the user confirms each one. The confirmed frames are the canonical phase frames for the session — all downstream comparison and persistence use these frames, not the raw Vision output.

### Phase 8 — Reference Frame Backend & iOS Networking ✅

Pivot the FastAPI backend from a coaching rule engine to a reference frame API. The backend hosts a curated library of phase frames from high-quality serves (trophy pose, racket drop, contact point), organized by phase key. Implement a `GET /reference-frames` endpoint that returns the reference frame library (URLs or base64-encoded images). iOS fetches reference frames via URLSession `async/await` at the end of the phase review step. Network required; show a clear error if the fetch fails.

### Phase 9 — Side-by-Side Comparison Screen ✅

Dedicated SwiftUI results screen showing the user's confirmed phase frames alongside the fetched reference frames. One row per phase (trophy pose, racket drop, contact point): user's frame on the left, reference frame on the right, phase label above. The layout should make it immediately obvious which part of the motion each pair represents. Displayed immediately after the reference frames are fetched.

### Phase 10 — SwiftData Persistence ✅

SwiftData models: `ServeSession` (clip metadata — date, source, input type) with child `ServePhase` records (one per confirmed phase frame, each holding the frame timestamp, the phase key, and the URL/identifier of the reference frame shown). History list screen shows past sessions; tap to re-open the comparison view.

### Phase 11 — Lite MVP Polish ✅

Loading/progress states during pose estimation and reference frame fetch. Error handling (network failure, no pose detected, all phases unconfirmed). Empty states for history screen. Basic app icon and launch screen. **Lite mode (Mode 1) complete — permanent, not superseded by Pro modes.**

---

## Pro Modes (Deferred) — Mode 2 (Pro 2D) and Mode 3 (Pro 3D)

These phases build **two additional, permanent, user-selectable modes** alongside Lite (Mode 1): **Pro 2D mode** (iPhone only, 2D pose) and **Pro 3D mode** (stereo rig, 3D pose), chosen at session setup alongside Lite. Pro 2D ships first — end-to-end from foundation through coaching — before any stereo hardware is introduced. Pro 3D then adds a parallel precision mode. All three modes remain available in the final product; neither Pro mode replaces Lite, and Pro 3D does not replace Pro 2D. All Pro phases are developed Mac-hosted (the Mac is already the Lite backend; no new hardware needed to start) and are **additive** — they introduce new, mode-gated code paths and must not modify Lite-mode files (`PhaseReviewView`, the Lite pipeline/segmentation services, `ContentView`). The final phase (P17) ports the proven Pro pipeline to a Jetson Orin Nano for untethered on-court portability. P17 is explicitly deferrable; all preceding phases run identically on the Mac. No phases are scheduled yet. See `specs/offdevice-pipeline.md` for the full architecture.

**Off-Device 2D Foundation (P1–P4)** — replaces on-device Vision with a robust pose and object-detection pipeline, validated against real footage before segmentation logic is built on top of it. No new hardware needed.

### Pre-Pro Cleanup ✅

Before starting Pro phases, fix the following items surfaced during loop-based tooling adoption:

- **Stale iOS tests in `MyServeCoachTests.swift`** — three tests reference `Serve` and `RecordServeViewModel` types that no longer exist. These cause `scripts/verify.sh ios` to report build failures unrelated to actual code changes. Delete or rewrite them against the current model.

### Phase P1 — Off-Device 2D Pose Service (Mac dev host) ✅

Mac backend gets a real 2D pose model (RTMPose via ONNX Runtime) behind a new `POST /v1/pose` endpoint, returning per-frame keypoints — the future keypoint source for Pro 2D/3D mode. Build the Vision-joint-name → backend-joint-name translation layer: iOS `PoseFrame.joints` uses Vision raw key names (`right_wrist_joint`, etc.); the backend `Frame.keypoints` schema expects `right_wrist`, `left_shoulder`, etc. Implement the currently-stubbed `App/Services/Coaching/CoachingService.swift` `LiveCoachingService.analyze()` — a `// TODO` pointing at a non-existent endpoint with a mismatched result type — and reconcile `CoachingResult` with the backend `AnalyzeResponse` in `models.py`. **Service-layer only this phase**: `LiveCoachingService` has no in-app caller yet, and `/v1/pose` has no iOS capture-path caller yet — both stay dormant, unit-tested services. In-app wiring lands on a Pro-mode screen in P6, never on the Lite `PhaseReviewView`.

### Phase P2 — Racket & Ball Object Detection ✅

YOLO-class object detector on the Mac for the racket (and ball). Vision never supported racket detection; this is net-new capability. Returns bounding-box positions per frame alongside keypoints, giving the segmentation and phase-detection engines the racket-position signal they need.

### Phase P3 — CV Model Performance Baseline (2D) ✅

Establish a reusable, quantitative performance baseline for P1's pose model and P2's object detector against real tennis serve footage, before P4 combines their signals into segmentation logic — so a bad segmentation result can be diagnosed as "the CV is inaccurate" vs. "the segmentation heuristic is wrong" instead of conflating the two. New tool `backend/tools/pose_benchmark.py`, reusing `calibration_report.py`'s frame-extraction and HTML-report-generation helpers, run directly against the existing `backend/tools/calibration_data/*.mov` videos (real footage from Phase 6; gitignored, local-only — no new recording needed). Computes per-video/per-frame detection rate (person/racket/ball detected?), average keypoint/detection confidence, and inference FPS; produces a visual HTML overlay report for human spot-check (gitignored output alongside the source footage) plus a small, git-tracked numeric summary (aggregate stats only, no images or video) that becomes the reference point for evaluating candidate model or approach swaps later. No ground truth required — matches Phase 6's precedent of visual comparison rather than labeled accuracy metrics; rigorous hand-labeled PCK/mAP accuracy is deferred to Phase P18. Default `pytest` suite uses synthetic fixtures (mirroring `test_calibration_report.py`); the real run against real footage is a manual, opt-in step whose output becomes the committed baseline.

### Phase P4 — Robust Automatic Multi-Stage Serve Segmentation ✅

Combine off-device pose + racket-position signals + background handling (lighting and court-line robustness) to achieve reliable automatic segmentation detecting the six Kovacs key frames directly — the core capability Phase 6 concluded on-device Vision could not provide. In Pro 2D/3D mode, this automatic segmentation replaces the manual-correction step (Phase 7 UI becomes optional QA in Pro modes rather than required). **Lite mode keeps mandatory manual frame correction permanently — this phase does not touch the Lite `PhaseReviewView` or its flow; it only affects the Pro 2D/3D pipeline.** Re-validate using the `backend/tools/calibration_report.py` HTML-report workflow against the same serve footage used in Phase 6. Extends `backend/app/engine/phases.py` from 3 to 6 detected frames.

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

Stages 5 (Acceleration) and 7 (Deceleration) are continuous motion phases between key frames, not single poses — they are not detected as discrete frames. Lite mode captures stages 3, 4, and 6 only (trophy pose, racket drop, contact point) and continues to do so permanently. This phase adds Start, Release, and Finish for Pro 2D/3D mode, completing the six-frame model there. Frame detection runs on 2D pose + racket signals and works for both Pro 2D and Pro 3D mode.

**Pro 2D mode coaching (P5–P7)** — the first fully usable Pro experience; iPhone-only, no stereo hardware needed. The coaching engine built in Lite Phases 3–4 is dormant in Lite mode; these phases activate it for Pro 2D mode. **A mode-selection step (Lite / Pro 2D / Pro 3D) at session setup gates which pipeline runs; Pro coaching screens introduced by P6+ are separate from the Lite `PhaseReviewView`/comparison flow and do not modify it.**

### Phase P4b — Segmentation Heuristic Refinement ✅

Iterate on P4's six-frame segmentation and phase-detection heuristics against more real
footage, before P5 calibrates rule thresholds against them. Re-tunes the tunable constants
(`MIN_REST_SECONDS`, `LOW_MOTION_VELOCITY_THRESHOLD`, `RACKET_DROP_ELBOW_WEIGHT`,
`RACKET_DROP_RACKET_WEIGHT`) against additional calibration videos, and revisits any of the
`start`/`trophy_pose`/`contact`/`racket_drop`/`finish` heuristics found to be unreliable — for
example, `trophy_pose`/`racket_drop` landing less cleanly on some real footage, or `racket_drop`
failing when `trophy_pose`/`contact` resolve to adjacent sampled frames because the whole
Cocking→Contact motion fell within a single sample step (a denser default `--stride` and a more
robust `contact` signal — e.g. racket/ball proximity, not just peak wrist height — are both
candidates). Extends `backend/app/engine/phases.py` and `backend/tools/segmentation_report.py`;
does not change the
six-frame model's shape, the `ServePhase` enum, or anything outside the Pro 2D/3D pipeline.

### Phase P5 — Rule Calibration (2D) ✅

Ground the `rules.json` thresholds in real 2D-measured joint angles now that reliable phase frames are available from P4. Run `backend/tools/analyze_angles.py` against the validated P4 phase frames and compare measured 2D joint angles against the current thresholds; update, add, remove, or re-weight rules accordingly. Note the 2D-projection caveat — foreshortening from a single camera systematically underestimates angles like shoulder external rotation; these thresholds serve Pro 2D mode and are re-derived on 3D angles for Pro 3D mode in Phase P10.

### Phase P6 — Automated Coaching Cues / Assessment (2D) ✅

**Builds the mode-selector, first appearance (2-way).** This is the first phase with any Pro-facing screen, so it also owns building the session-setup mode-selection step that gates entry to it: a **Lite / Pro 2D** choice shown at session start (natural insertion point: at or just before `VideoSourceSelectionView`, today's session entry). Selecting **Lite** routes into the existing, byte-for-byte-unchanged Lite flow (`VideoSourceSelectionView` → pipeline → `PhaseReviewView` → comparison) — the selector must not modify `PhaseReviewView`, the Lite pipeline/segmentation services, or the internals of `VideoSourceSelectionView`'s Lite path; if a wrapper/parent view is introduced at session entry, Lite's downstream views are navigated to unchanged. Selecting **Pro 2D** routes into the new Pro pipeline described below. (Pro 3D is not an option yet — added in P8.) The exact UI form and default/persistence behavior (segmented control vs. first-run screen, remembered-per-user vs. per-session) are decided during this phase's `/spec`.

For each auto-detected phase frame, POST keypoints to `POST /v1/analyze`; receive and display the `AnalyzeResponse` cue list on a **new, Pro-mode-gated coaching-results screen** — distinct from the Lite comparison screen, reachable only when Pro 2D mode is selected via the selector built above. Wires `LiveCoachingService.analyze()` (built service-layer-only in P1) into the app for the first time. Add SwiftData fields to persist cues alongside the phase frames already stored. Requires P4 (automatic segmentation) and P5 (calibrated 2D rules).

> **Known gap (TODO, future phase):** `segment_serves` (`backend/app/engine/phases.py`) always returns
> at least one segment for any non-empty frame list — even a clip with no genuine serve motion
> falls through to a single whole-clip segment rather than an empty list. This makes the P6 iOS
> pipeline's `ProServeAnalysisError.noSegmentsDetected` path (and its "No serves detected in this
> clip" messaging) real and tested, but currently unreachable from the actual backend — a
> serve-free clip will instead produce one low-quality "Serve 1" section with unreliable cues
> instead of a clean error. Fixing this means teaching `segment_serves` (or a caller) to recognize
> a segment with no real motion and drop it, which is a heuristic change out of scope for P6 —
> revisit alongside P7 (which also depends on `segment_serves` for continuous multi-serve capture
> and would benefit from the same fix) or as a small standalone heuristic phase.

> **Known gap (TODO, future phase):** P6's original iOS-side per-frame JPEG-upload architecture
> (sample frames via `AVAssetImageGenerator`, encode via `UIImage.jpegData`, upload individually to
> `/v1/pose`/`/v1/detect`) was replaced mid-phase with server-side video-file upload
> (`POST /v1/segment/video`) after real-device testing found the on-device extraction/encoding
> pipeline wasn't pixel-equivalent enough to the OpenCV-based extraction `segment_serves` was tuned
> against — a real 3-serve clip was silently under-segmented to 1 detected serve. The pivot also
> locks Pro 2D live recording to 720×1280@30fps (`CameraService.swift`, mode-gated — Lite's `.high`
> preset is unchanged), matching the resolution/frame rate `segment_serves` was validated against;
> testing across 5 real clips found all three 60fps/4K clips under-segmented identically while
> 30fps clips did not have that failure mode. Two residual gaps remain, confirmed but not fixed
> during this pass (fixed threshold, percentile-adaptive threshold, peak-detection, and
> `MIN_REST_SECONDS` tuning were all tried and rejected — see
> `phases/2026-07-10-p6-automated-coaching-cues-assessment-2d/requirements.md` for the full
> investigation): (1) even at the locked 720×1280@30fps, a player with an elaborate pre-serve
> routine (multiple ball bounces, grip adjustments) can still false-split a single serve into two
> — confirmed via a real clip that over-segmented 2 genuine serves into 3; fixing this needs
> proper P4b-style calibration with a larger hand-labeled dataset covering varied player routines,
> not a quick constant tweak. (2) The 720×1280@30fps lock only applies to *live-recorded* Pro 2D
> clips — Photos-library imports are copied as-is (`LibraryVideoExporter.copyToTemp`, not
> re-encoded) and can still arrive at other resolutions/frame rates, carrying the same
> under-segmentation risk the lock was meant to close.

### Phase P7 — Goal Library & Set Goal Session Mode (2D)

Continuous recording session with automatic per-serve detection (P4) and per-serve analysis. Define a goal catalog; backend returns `goal_result: { passed: bool, spoken_cue: String }` alongside normal cues. Deliver audible pass/fail feedback via `AVSpeechSynthesizer` so the player can stay focused on the court between serves. Mac-hosted; becomes field-portable after the P17 Jetson migration.

**Pro 3D Mode Foundation (P8–P9)** — adds a stereo rig and true 3D angles for Mode 3 (Pro 3D). Mac + two USB webcams; no Jetson hardware needed.

### Phase P8 — Stereo Camera Rig & Calibration

Two USB webcams on the Mac; OpenCV stereo intrinsics/extrinsics calibration (`cv2.calibrateCamera` per camera, then `cv2.stereoCalibrate`); synchronized dual capture; calibration matrices saved to `stereoCalibration.json` and loaded at backend startup. Introduces `backend/tools/stereo_calibrate.py`. Proves the stereo geometry without any Jetson hardware — the iPhone shifts from primary camera to controller and display on this path.

**Extends the mode-selector to three-way.** Adds **Pro 3D** as a third option to the Lite/Pro-2D selector built in P6, gating which of the three capture pipelines and coaching modes runs downstream. This must not alter the Lite or Pro-2D routes already validated in P6 — the extension adds a third branch to the existing selector, it does not restructure the selector or either existing route.

### Phase P9 — 3D Pose Triangulation & Angles

Triangulate 2D keypoints from both stereo views into 3D joint coordinates using `cv2.triangulatePoints`. Compute true 3D biomechanical angles — for example, the Kovacs 172° shoulder external rotation target is measured in 3D; 2D projection from a single angle systematically underestimates it. Add `compute_angle_3d` to `backend/app/engine/angles.py` *alongside* the existing 2D `compute_angle` — both functions are retained; rules consume whichever angle source matches the active mode.

**Pro 3D Mode Coaching (P10–P12)** — each phase extends its Pro 2D counterpart; the shared cue UI and goal engine carry over, with the 3D angle source and re-calibrated thresholds as the key differences.

### Phase P10 — Rule Calibration (3D)

Re-run `backend/tools/analyze_angles.py` against 3D angles from P9 to derive 3D-calibrated thresholds. Add a Pro-3D-mode threshold variant to `rules.json` alongside the existing Pro-2D-mode thresholds (similar structure to the per-serve-type variants introduced in P14). Pro 3D mode now has rules that exploit the full biomechanical fidelity of triangulated joint positions.

### Phase P11 — Coaching Cues (3D)

Route Pro 3D mode through the same coaching-cue UI introduced in P6, backed by the 3D-calibrated rules from P10. Surface the active mode (Pro 2D or Pro 3D) on the results screen so the user understands which fidelity produced the cues.

### Phase P12 — Goal Library & Set Goal Session Mode (3D)

Extend the Set-Goal session mode from P7 to Pro 3D mode. Enables goals that only 3D can reliably measure — for example, true shoulder external rotation approaching the 172° Kovacs target — without the projection ambiguity of a single-camera view.

**Enhancements (P13–P16)** — additional capabilities layered on the foundation; each is independently testable and can be tackled in any order.

### Phase P13 — Pose Skeleton Overlay & Live Confidence Check

Pre-recording skeleton overlay on the live iPhone feed with a joint-confidence warning. Skeleton drawn on keyframe thumbnails in the results screen.

### Phase P14 — Serve-Type Awareness

Serve-type selection (flat, slice, kick) before recording. Backend applies serve-type-specific rule thresholds. `rules.json` restructured for per-type variants alongside the per-mode (Pro 2D / Pro 3D) variants introduced in P10. Pro-mode only — Lite mode has no rule thresholds to vary.

### Phase P15 — Multi-Angle Support

Pipeline extended to support behind-server and closed-side recording angles. Angle-selection step added to session setup; angle-specific segmentation heuristics and rule sets. Note: the stereo rig added in P8 already provides a second view for 3D triangulation — this phase adds the open-side / behind-server / closed-side *analysis angle* variants for single-camera sessions.

### Phase P16 — LLM Coaching Cues

Integrate the Claude API in the backend. Pass rule violations and keypoints to Claude to generate natural-language coaching paragraphs. Displayed as an expandable section below the structured cue list on the results screen. Mode-agnostic within Pro — enriches whichever of Pro 2D / Pro 3D mode is active; not applicable to Lite mode (no coaching cues exist there). Explicitly the lowest-priority feature phase; can be skipped if the structured cue list is sufficient.

**On-Court Deployment (P17)** — the full pipeline is developed and validated Mac-hosted. This phase is a pure portability migration with no algorithm changes.

### Phase P17 — Jetson Orin Nano Migration & On-Court Portability

Port the proven Mac pipeline to a Jetson Orin Nano for untethered, battery-powered court use. Export RTMPose and YOLO models to TensorRT; move stereo capture from USB webcams to the Jetson's CSI camera ports; run the FastAPI backend on the Jetson over a local court Wi-Fi network or Jetson-broadcast hotspot — no cloud round-trip, all data stays on court. Update `App/Services/BackendConfig.swift` from the Mac LAN IP to the Jetson's address. No backend logic, model, or iOS app changes — only the serving runtime (TensorRT vs. ONNX Runtime) and camera I/O differ. Deferrable: can be pulled forward whenever on-court portability is wanted; everything before it runs identically on the Mac.

**CV Model Rigor Upgrade (P18)** — deferred, lowest priority; doesn't block anything else on the roadmap.

### Phase P18 — CV Model Ground-Truth Accuracy Benchmark

Extends P3's lightweight baseline with hand-labeled ground truth (keypoint annotations for pose, bounding boxes for racket/ball) on a subset of the real serve footage in `backend/tools/calibration_data/`, computing rigorous accuracy metrics — PCK (Percentage of Correct Keypoints) for pose, mAP/IoU for object detection — rather than P3's ground-truth-free detection-rate/confidence statistics. Explicitly deferred, like P17: can be pulled forward whenever rigorous accuracy numbers are actually needed (for example, before committing to a specific model ahead of the P17 Jetson export). This is the rigor upgrade a future automated CV-model-improvement loop (see `specs/mission.md` Future Differentiators) would need for confident, quantified accept/reject decisions when trialing a candidate replacement model or approach — not scheduled itself, but this phase is a prerequisite for trusting that kind of automation.
