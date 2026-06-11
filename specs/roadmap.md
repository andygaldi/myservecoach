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

Implement `rules.json` threshold config and angle computation utilities. Serve phase detection (trophy pose, racket drop, contact point — corresponding to Stages 4, 4–5, and 6 of the Kovacs 8-stage serve model; see Pro Version Phase P8 for full-model expansion). Unit-tested with pytest. Backend now returns real cues instead of hardcoded ones.

### Phase 5 — Video Library Import ✅

Video input selection screen presented at the start of a session. The user chooses between recording a new clip live or picking an existing video from their Photos library. Selecting a library video feeds it through the same Phase 2 pipeline (frame sampling → pose estimation → serve segmentation) and into the normal flow — results and persistence are identical regardless of input source. Uses SwiftUI's `PhotosPicker` (iOS 16+) to request only the video asset, avoiding a full Photos library permission prompt.

### Phase 6 — Segmentation Calibration ✅

Validate and tune the heuristic phase detection logic against real serve footage. Input videos come from two sources: clips recorded directly with the iOS app and external serve videos imported via the Phase 5 Photos library picker — both go through the same on-device Vision pose estimation pipeline. Export the keypoint JSON from the Xcode console and the video file from the device (AirDrop or Files app). A Python script in `backend/tools/` takes those two files, extracts frame images using OpenCV at the timestamps in the keypoint JSON, and produces an HTML report showing thumbnails of every sampled frame alongside highlighted images of the frame identified for each phase (trophy pose, racket drop, contact). No pose estimation happens in the Python tool — it only handles frame extraction and layout. Compare the report against the source video and adjust `phases.py` heuristics until all three phases land on the visually correct frames across a representative set of serves.

> **Outcome / pivot note**: Phase 6 established that on-device Vision pose estimation is not reliable enough for fully automated segmentation across real-world conditions (varied backgrounds, lighting, court lines). Automatic serve detection also cannot reliably identify racket position, which is critical for accurate phase classification. As a result, Phases 7+ pivot to a **Lite Version** model: the app still uses Vision for an initial phase-frame guess, but the user manually reviews and corrects the detected frames before comparison. Automated coaching cues (Assessment, Set Goal workflows) are deferred to a future Pro Version that requires better pose estimation.

### Phase 7 — Manual Frame Selection UI ⬜

After pose estimation runs and produces guessed phase frames (trophy pose, racket drop, contact point), present a "phase review" screen where the user can inspect each guessed frame and scrub through the video to select the correct frame if the guess is wrong. The three phases are shown in sequence; the user confirms each one. The confirmed frames are the canonical phase frames for the session — all downstream comparison and persistence use these frames, not the raw Vision output.

### Phase 8 — Reference Frame Backend & iOS Networking ⬜

Pivot the FastAPI backend from a coaching rule engine to a reference frame API. The backend hosts a curated library of phase frames from high-quality serves (trophy pose, racket drop, contact point), organized by phase key. Implement a `GET /reference-frames` endpoint that returns the reference frame library (URLs or base64-encoded images). iOS fetches reference frames via URLSession `async/await` at the end of the phase review step. Network required; show a clear error if the fetch fails.

### Phase 9 — Side-by-Side Comparison Screen ⬜

Dedicated SwiftUI results screen showing the user's confirmed phase frames alongside the fetched reference frames. One row per phase (trophy pose, racket drop, contact point): user's frame on the left, reference frame on the right, phase label above. The layout should make it immediately obvious which part of the motion each pair represents. Displayed immediately after the reference frames are fetched.

### Phase 10 — SwiftData Persistence ⬜

SwiftData models: `ServeSession` (clip metadata — date, source, input type) with child `ServePhase` records (one per confirmed phase frame, each holding the frame timestamp, the phase key, and the URL/identifier of the reference frame shown). History list screen shows past sessions; tap to re-open the comparison view.

### Phase 11 — Lite MVP Polish ⬜

Loading/progress states during pose estimation and reference frame fetch. Error handling (network failure, no pose detected, all phases unconfirmed). Empty states for history screen. Basic app icon and launch screen. **Lite Version MVP complete.**

---

## Pro Version (Deferred)

These phases require better pose estimation than Apple Vision currently provides — specifically, reliable racket-object detection and background removal for accurate automatic serve segmentation. They are defined here for continuity but are not scheduled.

### Phase P1 — Rule Calibration

Ground the rule thresholds in real biomechanics. Using the same serve videos from Phase 6, run a developer script (`backend/tools/analyze_angles.py`) that prints all joint angles and relative positions at each validated phase frame for each serve. Compare measured values from technically sound serves against the current `rules.json` thresholds. Update thresholds — and add, remove, or re-weight rules — to reflect what a good serve actually looks like.

### Phase P2 — Automated Coaching Cues (Assessment MVP)

For each confirmed (or auto-detected) phase frame, POST keypoints to the backend; receive and display a list of coaching cues. Requires accurate automatic segmentation — not dependent on user correction for every session. URLSession networking, results screen with coaching cue list, SwiftData persistence.

### Phase P3 — Goal Library & Set Goal Session Mode

Continuous recording session with on-device serve detection, per-serve analysis, and AVSpeechSynthesizer audible cues. Goal catalog defined; backend returns `goal_result: { passed: bool, spoken_cue: String }` alongside normal cues.

### Phase P4 — LLM Coaching Cues

Integrate Claude API in the backend. Pass rule violations + keypoints to Claude to generate natural-language coaching paragraphs. Displayed as an expandable section below the cue list.

### Phase P5 — Pose Skeleton Overlay & Live Confidence Check

Pre-recording skeleton overlay on the live feed with a joint-confidence warning. Skeleton drawn on keyframe thumbnails in the results screen.

### Phase P6 — Serve-Type Awareness

Serve-type selection (flat, slice, kick) before recording. Backend applies serve-type-specific rule thresholds. `rules.json` restructured for per-type variants.

### Phase P7 — Multi-Angle Support

Pipeline extended for behind-server and closed-side angles. Angle-selection step added to session setup; angle-specific segmentation heuristics and rule sets.

### Phase P8 — Full 8-Stage Serve Analysis (Kovacs Model)

Expand phase detection from the current 3-frame model to all 8 stages defined in Kovacs & Ellenbecker (2011) — *A Biomechanical Review of the Tennis Serve* ([PMC3445225](https://pmc.ncbi.nlm.nih.gov/articles/PMC3445225/)):

| Stage | Name | Description | Kovacs angles / criteria |
|---|---|---|---|
| 1 | Start | Stance and initial alignment | Minimal muscle activation; ground force generation begins |
| 2 | Release | Ball toss | Toss slightly lateral to overhead; ~100° arm abduction target |
| 3 | Loading | Weight transfer and coil | Front knee flexion >15°; shoulder/pelvis lateral rear tilt; vertical GRF 1.68–2.12× body weight |
| 4 | Cocking | Trophy pose → max external rotation | Shoulder abduction 101° ± 13°; ext. rotation 172° ± 12°; elbow flexion 104° ± 12° |
| 5 | Acceleration | External rotation → contact | Peak leg EMG; lead knee extension velocity 800° ± 400°/s; trunk rotation reversal |
| 6 | Contact | Ball strike | Trunk tilt 48° ± 7°; shoulder abduction ~100–110°; elbow flexion 20° ± 4° |
| 7 | Deceleration | Arm and trunk deceleration | Eccentric shoulder distraction 0.5–0.75× body weight; up to 300 N·m trunk-arm deceleration torque |
| 8 | Finish | Front-foot landing | Horizontal braking forces; eccentric lower-body loading |

The Lite MVP captures Stages 4, 4–5, and 6 only (trophy pose, racket drop, contact point). This phase adds the five remaining stages as detectable phase frames, enabling coaching cues and reference comparisons across the complete serve motion. Requires the improved off-device pose estimation planned for the Pro Version (Raspberry Pi pipeline) — current on-device Vision cannot reliably detect the subtle position cues for Stages 1–3 and 7–8.
