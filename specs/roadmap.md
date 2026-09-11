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

**Pro 2D mode coaching (P5–P7b)** — the first fully usable Pro experience; iPhone-only, no stereo hardware needed. The coaching engine built in Lite Phases 3–4 is dormant in Lite mode; these phases activate it for Pro 2D mode. **A mode-selection step (Lite / Pro 2D / Pro 3D) at session setup gates which pipeline runs; Pro coaching screens introduced by P6+ are separate from the Lite `PhaseReviewView`/comparison flow and do not modify it.**

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
>
> → **Now scheduled as Phase P6b.**

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
>
> → Residual gaps (1) and (2) **now scheduled as Phase P6b.**

### Phase P6b — Segmentation Robustness & Empty-Clip Detection (2D) ✅

Closes all three `segment_serves` known gaps left open by P6, scheduled ahead of P7 because P7's
continuous multi-serve capture inherits every fix. **Empty-clip detection:** teach `segment_serves`
(or its caller in `backend/app/engine/phases.py`) to recognize a segment with no genuine serve
motion and drop it, so a serve-free clip returns an empty segment list — making the
already-built-and-tested `ProServeAnalysisError.noSegmentsDetected` / "No serves detected in this
clip" path reachable end-to-end from the real backend. **False-split reduction:** P4b-style
calibration against an expanded hand-labeled dataset
(`backend/tools/segmentation_ground_truth.json`) covering varied pre-serve routines (multiple ball
bounces, grip adjustments), so an elaborate routine no longer over-segments one serve into two.
**Import normalization:** normalize Photos-library imports to the validated 720×1280@30fps before
segmentation (re-encode in `LibraryVideoExporter.copyToTemp` or a dedicated export path), mirroring
the live-recording lock already in `CameraService.swift` and closing the import path's
under-segmentation risk. Requires P4/P4b and P6.

### Phase P6c — Assessment Results Visualization (2D) ✅

Turns the plain per-serve cue list into an aggregate, visual assessment. **Backend:** extend
`AnalyzeResponse`/`Cue` (`backend/app/models.py`, `engine/rules.py`, `engine/phases.py`) to surface,
per detected phase, the frame index/timestamp, and per cue the measured metric value plus ideal
target/threshold (the deviation) — `detect_phases` and `evaluate_rules`/`_passes` already compute
both and currently discard them. **iOS — retain frames & keypoints:** carry the flagged-phase
frame's keypoints (`BackendFrame.keypoints`) and extract its image from the recorded/imported video
at the returned timestamp (reuse `FrameThumbnailGenerator`) into
`AssessmentServeResult`/`AssessmentServeDisplay`, persisted alongside cues via a new SwiftData field
mirroring Lite's `PhaseRecord.frameImageData`. **iOS — aggregate cue view:** group cues by `ruleId`
across all serves ("across X serves, 'Keep your tossing arm more vertical' was flagged N times")
instead of only per-serve bullets, in `AssessmentResultView.swift` /
`AssessmentResultViewModel.swift`. **iOS — skeleton overlay + deviation (pulled forward from P13):**
net-new `Canvas`/`Path` renderer drawing the pose skeleton on the phase frame plus a visual
indicator of the deviation from the rule's ideal alignment (e.g. measured toss-arm segment vs. the
ideal vertical for `trophy_toss_arm_vertical`); no overlay renderer exists in iOS today. This
delivers P13's "skeleton on results-screen keyframes" ahead of schedule — P13 is narrowed
accordingly (see below). Requires P6; benefits from P6b's cleaner segmentation.

### Phase P6d — Serve Count Robustness ✅

Replaces gap-detection with event-counting as the source of the serve count. Scheduled ahead of P7 because P7's continuous multi-serve capture depends on the count being right more directly than anything else on the roadmap, and ahead of P7b so a second camera view isn't calibrated on top of a miscount.

**The defect.** `segment_serves` infers the count from *absences* — sustained low-velocity gaps between serves. `_frame_velocity` divides displacement by `dt`, and `dt` is exactly `stride/fps` (fixed `DEFAULT_STRIDE = 2`, timestamps synthesized as `idx/fps` in `video_sampler.py`). The motion signal is genuinely fps-invariant; the keypoint *noise* is not. Measured on `ag_three_serves.MOV` — the 30fps clip every constant was calibrated against — by inferring pose once and subsampling so only `dt` varies:

| stride | dt | segments detected (true: 3) | p10 velocity |
|---|---|---|---|
| 1 | 0.033s | **1** | 0.0501 |
| 2 | 0.067s | 3 ✓ | 0.0422 |
| 3 | 0.100s | 4 | 0.0400 |
| 4 | 0.133s | 3 ✓ | 0.0368 |
| 6 | 0.200s | 4 | 0.0383 |

Noise scales as roughly `dt^-0.22` (temporally correlated, not white), so 60fps costs only ~1.2× — but the margin was never there: the 10th-percentile velocity exceeds `LOW_MOTION_VELOCITY_THRESHOLD = 0.03` at *every* stride, so rest detection survives on the bottom decile of the distribution. Counts are non-monotonic in `dt`, meaning stride 2 landing on the right answer is closer to coincidence than calibration. This is the root cause behind P6's finding that 60fps/4K clips return 1 serve regardless of true count — which P6 addressed by constraining the input (720×1280@30fps capture lock, import re-encode) rather than fixing the algorithm.

**Why it survived P4/P4b/P6/P6b.** The ground-truth corpus cannot observe it. `ag_three_serves.MOV` is the only multi-serve clip and it is 30fps; all five ~57–60fps clips are single-serve, where under-segmentation is invisible. `test_segmentation_is_fps_invariant` passes because its fixture emits an identical `x` every frame — rest velocity is exactly 0.0, so noise-driven failure is unobservable by construction.

**The approach.** Count a positive event instead: hitting-wrist height peaks, one per serve, via a body-relative floor (`neck + k·|neck − pelvis|`) plus greedy non-max suppression with a minimum temporal separation. Pose is the reliable signal — 100% person detection, 0.775 mean keypoint confidence — whereas ball detection is present in only **10.8%** of frames and is documented to vanish *at the contact instant* to motion blur, so a ball-based contact counter would depend on the weakest signal in the system exactly when it fails. Peak count becomes authoritative; velocity is demoted to *placing* boundaries rather than deciding how many there are. The hitting-side restriction is load-bearing — it is what rejects an aborted toss-and-catch, where the toss arm rises but the hitting arm does not.

**Corpus first.** New footage is a blocking prerequisite: an fps matrix (2/3/5 serves at both 60fps and 30fps), a held-out clip reserved from all tuning, and negative cases — toss-and-catch, elaborate ball-bounce routine, idle-only, shadow swing. Serve counts are the headline metric and need no timestamps. `segmentation_report.py` gains a `--score` mode (it computes no metrics today) and a keypoint-caching sweep tool makes parameter search instant rather than minutes of CPU per question.

**Escalates the handedness seam.** `HANDEDNESS` (`phases.py:13`) hardcodes a right-handed server. Today a wrong hitting side produces wrong cues; once the count derives from the hitting wrist it produces the wrong *serve count* — so P7b's handedness note is promoted from known limitation to prerequisite. Requires P6b. **Lite mode is untouched** — `segment_serves` is Pro-path only.

### Phase P7 — Goal Library & Set Goal Session Mode (2D) ✅

Continuous recording session with automatic per-serve detection (P4) and per-serve analysis. Define a goal catalog; backend returns `goal_result: { passed: bool, spoken_cue: String }` alongside normal cues. Deliver audible pass/fail feedback via `AVSpeechSynthesizer` so the player can stay focused on the court between serves. Mac-hosted; becomes field-portable after the P17 Jetson migration.

### Phase P7a — Set Goal UX Follow-Ons (2D) ✅

Small, independent fixes and enhancements surfaced during P7's manual real-device testing
(`phases/2026-08-28-p7-goal-library-set-goal-2d/validation.md` Run Notes), scheduled ahead of
P7b so the second camera angle isn't calibrated on top of a still-rough Set Goal UX.

- **Front camera for Set Goal.** Recording is currently locked to the rear camera; add front-camera
  selection to the Set Goal recording flow.
- **Cancel/discard from the results screen.** No way to abandon a Set Goal session without saving —
  add a Cancel action that returns to mode selection without persisting.
- **Lite mode hides the Assessment/Set Goal toggle.** The toggle is Pro-2D-only but currently
  remains visible after switching to Lite; should disappear.
- **Toggle-visibility state bug.** Lite → Record New → back arrow leaves the Assessment/Set Goal
  toggle hidden even after switching back to Pro 2D, until a Pro 2D → Record New → back-arrow cycle
  restores it. Root-cause and fix the underlying state, not just the symptom.
- **Skeleton overlay on Set Goal results.** Show a still frame with pose skeleton overlaid per serve
  on the results page, matching the Assessment history page's treatment.
- **More specific spoken cues on goal miss.** Replace generic phrasing ("elbow not in line with
  shoulders at trophy pose") with more actionable cues (e.g. "elbow too low").

Requires P7. Lite mode is untouched except for the toggle-visibility fixes above, which only
affect the Pro-2D/Lite mode-selector shell, not Lite's pipeline or views.

### Phase P7b — Behind-Server Camera Angle (2D)

Pulled forward from P15 and scheduled ahead of P8: proving a *second single-camera angle* end-to-end is a smaller, cheaper test of the "does the pipeline generalize beyond the one view it was calibrated on" question than building a stereo rig, and everything learned here — the view-tagged rule set, the angle-selection step, per-view segmentation calibration — is a prerequisite the P8/P9 3D path would otherwise have to invent under harder conditions.

**Step zero — confirm the pose model can tell left from right.** Every rule and every phase detector keys off anatomical joint names (`right_wrist`, `left_shoulder`). Those names are anatomical rather than image-relative, so they *should* be view-invariant — but pose models are measurably weaker at left/right disambiguation from behind, where the face and front-of-body cues are gone. A model that swaps sides on some frames makes everything downstream quietly wrong rather than absent, which is far harder to debug than a missing keypoint. Run the existing `/v1/pose` over the behind-server footage and check left/right consistency across frames **before** building anything. If it is unreliable, this is a model problem, not a threshold problem, and the phase's shape changes completely — so this gates the two task groups below rather than running alongside them.

**Segmentation from behind.** `segment_serves` and `detect_phases` were calibrated on open-side motion across P4/P4b/P6b; the dominant horizontal motion cues change substantially from behind, where the toss and racket travel largely *toward* the camera. Note the asymmetry to close: `evaluate_rules` got a `view` parameter, but `detect_phases` (`backend/app/engine/phases.py:240`) takes only `(frames, detections)` and every threshold it uses is a module-level constant. Assume per-view constants are needed rather than treating them as a fallback. The five detectors are not equally exposed — vertical comparisons survive a camera move, depth-axis motion does not:

| Detector | Signal | Behind-server risk |
|---|---|---|
| Release (`phases.py:254`) | `ball_y > toss_wrist_y > toss_shoulder_y` | **Low** — pure vertical comparisons |
| Trophy (`phases.py:292`) | hip height (vertical) + toss-arm elbow angle | Moderate — half the signal is robust |
| Contact (`_find_contact_idx`) | wrist height + racket-ball *image* distance | Moderate — image-close can be depth-far from behind, so more false peaks |
| **Racket drop (`phases.py:336`)** | `forearm_angle_from_vertical` | **Highest** — the forearm's swing "down and behind the body" is exactly the depth axis from this view, so it foreshortens hardest. Already the hardest phase to pin on the open side (P6b set `RACKET_DROP_SMOOTHING_WINDOW = 1` because its window is 1–4 frames on fast swings). |
| Finish (`phases.py:354`) | knee flexion, hip→knee→ankle | Moderate — foreshortened |

Spend calibration effort in that order. Extend `backend/tools/segmentation_ground_truth.json` with hand-labeled behind-server segments and re-run `segmentation_report.py` the way P6b did.

**Angle selection & plumbing.** Add a recording-angle step (open side / behind server) to Pro 2D session setup, alongside the existing mode selector. Angle is a separate axis from mode, so it belongs in its own `RecordingAngle` type and its own persisted field rather than as extra `SessionMode` cases — otherwise P15's closed-side variant turns a two-case enum into six. Thread the chosen view through `POST /v1/analyze` to `evaluate_rules`, which already takes a `view` parameter and already filters `_RULES` by it (`backend/app/engine/rules.py:112,117`) — but nothing calls it with anything other than the default, because `analyze.py` never passes one. The `_Rule.view` field is deliberately a plain `str`, not a `Literal`, so `"behind_server"` needs no model change.

**Behind-server rule set.** Import the existing behind-server footage into `backend/tools/calibration_data/behind_server/` and re-run `analyze_angles.py` to derive thresholds for this view, adding `"view": "behind_server"` rules to `rules.json` alongside the nine open-side rules, which stay untouched. Expect the rule *set* to differ, not just its thresholds: some open-side rules are meaningless or inverted from behind (`racket_drop_ball_front` measures `ball_offset_x`, which reads as depth rather than in-front-of-body from this view), while behind-server exposes biomechanics the open side cannot see — lateral toss placement and shoulder-hip separation being the obvious candidates. Rules that genuinely hold in both views are duplicated per view rather than shared, so each view's thresholds stay independently calibratable.

**Results & overlay reuse.** The P6c overlay renderer, aggregate cue view, and history replay are view-agnostic — they draw whatever joints a cue names — so this phase should add no new results-screen UI beyond surfacing which angle produced the session. If the overlay needs per-view special-casing, that is a signal the cue data model is wrong, not that the renderer needs a branch.

**Handedness seam — check what P6d left.** `HANDEDNESS` (`backend/app/engine/phases.py:13`) is a module-level constant hardcoding a right-handed server. It is orthogonal to view (joint names are anatomical, so they don't flip with the camera), but it is the same *shape* of problem: a per-session fact frozen into a global. P6d escalated this from a cue-quality issue to a count-correctness one and either resolved the seam or explicitly declared left-handed servers unsupported — confirm which before starting. If the seam is still open, this phase threads `view` through every call site that would also carry handedness, so it remains the cheap moment to put both in one per-session context rather than leaving two mechanisms for the same kind of variation.

**Sequencing.** Left/right sanity check → segmentation and phase detection → rules. A failure at the first step invalidates the other two, and thresholds calibrated on top of mis-detected phases are worse than no thresholds at all.

Requires P6c (the cue/overlay surface these rules render through) and P6b (segmentation baseline). Does not require P7 — the goal engine is orthogonal — but is scheduled after it to keep the Pro 2D block contiguous. **Lite mode is untouched and remains open-side only.**

**Pro 3D Mode Foundation (P8–P9)** — adds a stereo rig and true 3D angles for Mode 3 (Pro 3D). Mac + two USB webcams; no Jetson hardware needed. Benefits from P7b, which establishes per-view rule sets and angle selection before a second physical camera is introduced.

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

Pre-recording skeleton overlay on the live iPhone feed with a joint-confidence warning. (The results-screen keyframe skeleton overlay was delivered earlier in Phase P6c.)

### Phase P14 — Serve-Type Awareness

Serve-type selection (flat, slice, kick) before recording. Backend applies serve-type-specific rule thresholds. `rules.json` restructured for per-type variants alongside the per-mode (Pro 2D / Pro 3D) variants introduced in P10. Pro-mode only — Lite mode has no rule thresholds to vary.

### Phase P15 — Closed-Side Camera Angle

Adds the closed-side recording angle as a third single-camera view, following the per-view pattern established in P7b: a `"view": "closed_side"` rule set in `rules.json`, closed-side entries in `segmentation_ground_truth.json`, and a third option on the angle selector. (Behind-server support and the angle-selection step itself were delivered earlier in Phase P7b, which also proved the per-view plumbing this phase reuses — so this phase should be substantially smaller than P7b was.) Note: the stereo rig added in P8 provides a second *simultaneous* view for 3D triangulation; this phase is about single-camera analysis-angle variants, which remain useful in Pro 2D mode without any stereo hardware.

### Phase P16 — LLM Coaching Cues

Integrate the Claude API in the backend. Pass rule violations and keypoints to Claude to generate natural-language coaching paragraphs. Displayed as an expandable section below the structured cue list on the results screen. Mode-agnostic within Pro — enriches whichever of Pro 2D / Pro 3D mode is active; not applicable to Lite mode (no coaching cues exist there). Explicitly the lowest-priority feature phase; can be skipped if the structured cue list is sufficient.

**On-Court Deployment (P17)** — the full pipeline is developed and validated Mac-hosted. This phase is a pure portability migration with no algorithm changes.

### Phase P17 — Jetson Orin Nano Migration & On-Court Portability

Port the proven Mac pipeline to a Jetson Orin Nano for untethered, battery-powered court use. Export RTMPose and YOLO models to TensorRT; move stereo capture from USB webcams to the Jetson's CSI camera ports; run the FastAPI backend on the Jetson over a local court Wi-Fi network or Jetson-broadcast hotspot — no cloud round-trip, all data stays on court. Update `App/Services/BackendConfig.swift` from the Mac LAN IP to the Jetson's address. No backend logic, model, or iOS app changes — only the serving runtime (TensorRT vs. ONNX Runtime) and camera I/O differ. Deferrable: can be pulled forward whenever on-court portability is wanted; everything before it runs identically on the Mac.

**CV Model Rigor Upgrade (P18)** — deferred, lowest priority; doesn't block anything else on the roadmap.

### Phase P18 — CV Model Ground-Truth Accuracy Benchmark

Extends P3's lightweight baseline with hand-labeled ground truth (keypoint annotations for pose, bounding boxes for racket/ball) on a subset of the real serve footage in `backend/tools/calibration_data/`, computing rigorous accuracy metrics — PCK (Percentage of Correct Keypoints) for pose, mAP/IoU for object detection — rather than P3's ground-truth-free detection-rate/confidence statistics. Explicitly deferred, like P17: can be pulled forward whenever rigorous accuracy numbers are actually needed (for example, before committing to a specific model ahead of the P17 Jetson export). This is the rigor upgrade a future automated CV-model-improvement loop (see `specs/mission.md` Future Differentiators) would need for confident, quantified accept/reject decisions when trialing a candidate replacement model or approach — not scheduled itself, but this phase is a prerequisite for trusting that kind of automation.
