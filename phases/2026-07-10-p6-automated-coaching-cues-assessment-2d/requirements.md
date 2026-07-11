# Phase P6 — Automated Coaching Cues / Assessment (2D) — Requirements

## Scope

Build the first fully usable Pro 2D experience: a **Lite / Pro 2D mode selector** at session
entry, and — when Pro 2D is selected — a continuous multi-serve **Assessment** capture that
routes a recording through off-device pose (P1) and object-detection (P2) inference, the
already-proven backend segmentation (P4/P4b) and rule engine (P5), and displays the resulting
per-serve coaching cues on a new Pro-mode-gated results screen. This is the first phase to call
`POST /v1/analyze` from the app, and the first to expose serve segmentation (`segment_serves`)
over HTTP.

Per the user's explicit choice, this phase builds **full continuous multi-serve Assessment** (one
clip, multiple back-to-back serves, auto-segmented and each analyzed), not a single-serve-only
version — matching `specs/mission.md`'s Assessment workflow description literally rather than the
narrower single-serve reading of the roadmap's phase body text.

**Mid-phase architecture revision:** the capture pipeline originally built for this phase sampled
video frames on-device (`AVAssetImageGenerator`), JPEG-encoded them (`UIImage.jpegData`), and
uploaded them individually via multipart to `POST /v1/pose` and `POST /v1/detect`, then a JSON
`POST /v1/segment`. Real-device smoke testing found this on-device extraction/encoding pipeline
was not pixel-equivalent enough to the OpenCV-based extraction `segment_serves` was validated
against in P4/P4b — a real 3-serve clip was silently under-segmented to 1 detected serve, and
raising JPEG quality (0.85 → 0.95) did not reliably fix it. The pipeline was revised to upload the
raw video file to a new `POST /v1/segment/video` endpoint, which does frame extraction, pose,
detection, and segmentation entirely server-side using the exact code path the calibration tooling
already validated. This also fixed a second, independent finding — recording resolution/frame
rate materially affects segmentation reliability (see Key Decisions) — by locking Pro 2D live
recording to a known-good, fixed configuration rather than trying to make the segmentation
heuristic generalize across arbitrary camera settings. Both problems, and the investigation behind
each fix, are recorded in the Key Decisions table and Context below; a residual, disclosed
robustness gap (players with elaborate pre-serve routines can still cause a false split) is logged
as a roadmap TODO rather than fixed in this pass.

Scope spans both backend (new `/v1/segment/video` endpoint) and iOS (mode selector, video-upload
capture pipeline, camera resolution/fps locking, results screen, SwiftData persistence, History
integration).

## In Scope

- **Mode selector** — a Lite / Pro 2D segmented control added inline at the top of
  `VideoSourceSelectionView`'s body (not `ContentView`, which is a protected file). Last choice
  persisted via `@AppStorage` as the default for next session, always changeable before
  recording. Selecting Lite leaves the existing `RecordServeView` → `PoseAnalysisPipeline` →
  `PhaseReviewView` → `ReferenceFrameFetchView` path completely unchanged and reachable
  byte-for-byte as today. Selecting Pro 2D branches into the new pipeline below, reusing the same
  `RecordServeView` (camera) and `PhotosPicker` (library import) entry points unchanged — only
  post-capture processing differs by mode.
- **Video-upload capture pipeline (iOS)** — `ProServeAnalysisPipeline` that, given a
  recorded/imported video URL, streams the raw file to the backend
  (`VideoSegmentationServiceProtocol.segmentVideo(at:sessionId:)`, `URLSession.upload(for:fromFile:)`
  — no in-memory buffering of the whole clip) and receives back per-serve segments (`[ProServeSegment]`,
  each with `frames`/`detections` already extracted, pose-estimated, detected, and split
  server-side). Loops `POST /v1/analyze` once per returned segment (mirrors Phase 3's original
  framing: "Assessment loops one call per segmented serve"), collecting one `CoachingResult` per
  serve. No on-device frame sampling, JPEG encoding, or multipart frame upload — see "Mid-phase
  architecture revision" above.
- **Pro 2D camera resolution/fps lock (iOS)** — `CameraService.configure(position:sessionMode:)`
  locks Pro 2D live recording to `.hd1280x720` @ 30fps (fixed frame duration via
  `AVCaptureDevice.activeVideoMinFrameDuration`/`activeVideoMaxFrameDuration`), matching the
  resolution/frame rate `segment_serves` was validated against. Lite's `.high` preset is
  unchanged — `CameraService` is shared by both modes and is not on the protected Lite-isolation
  file list, but the lock is mode-gated to avoid any risk to Lite's separately-calibrated
  on-device segmentation. `SessionMode` threads through `VideoSourceSelectionView` →
  `RecordServeView` → `CameraViewModel` → `CameraService`. Only applies to live recording —
  Photos-library imports are copied as-is (see Out of Scope).
- **`LiveCoachingService.analyze()` extension** — add a `detections: [[Detection]]?` parameter/
  field to the request body, matching the backend's existing `AnalyzeRequest.detections`. New
  Swift `Detection`/`BoundingBox` `Codable` types mirroring `app/models.py`.
- **New backend endpoint `POST /v1/segment/video`** (`backend/app/routers/segment.py`) — accepts
  a streamed raw video body (`request.stream()` written to a temp file, no multipart envelope);
  samples frames via a newly-promoted `sample_video_frames` (moved from
  `backend/tools/pose_benchmark.py` into `backend/app/services/video_sampler.py`, re-exported from
  the tool for backward compatibility); runs pose (`RTMPoseModel`) + detection
  (`ObjectDetectionModel`) inference per frame; segments via `segment_serves` +
  `slice_detections_by_segments`; returns the same `SegmentResponse`/`ServeSegment` shape as the
  existing JSON `POST /v1/segment`, so downstream `/v1/analyze` consumption is unchanged. The
  original JSON `POST /v1/segment` (frames/detections already extracted) is kept as-is — a
  dormant-but-tested primitive, not this phase's iOS caller.
- **New Assessment results screen** — Pro-mode-gated, distinct from Lite's comparison screen. One
  section per detected serve in chronological order; each section shows its cue list (sorted
  major-before-minor, cues within each severity ordered by Kovacs phase sequence
  start→release→trophy_pose→racket_drop→contact→finish) and its `summary` string. A header shows
  total serve count and aggregate major/minor counts across the whole clip.
- **SwiftData persistence** — `ServeSession` gains a `mode: String` field (default `"lite"`, so
  existing Lite session rows need no explicit migration). New `@Model ServeResult` (`serveIndex`,
  `summary`, cascade-deleted `cues` relationship) and `@Model CueRecord` (`ruleId`, `phase`,
  `message`, `severity`). `ServeSession.results: [ServeResult]` (cascade delete), populated only
  for Pro sessions; Lite's existing `phases: [PhaseRecord]` relationship and behavior is untouched.
- **History screen integration** — `SessionHistoryView` / `SessionHistoryRowView` branch on
  `session.mode`: Pro rows show a "Pro 2D" badge and a cue-count subtitle instead of Lite's phase
  thumbnail; tapping a Pro row navigates to a new, read-only `AssessmentHistoryDetailView`
  (renders the same per-serve cue content as the live results screen) instead of
  `HistoryComparisonView`. `ContentView` itself is not modified.
- **Loading / error states** — reuse the existing `LoadingOverlayView` / `ErrorView` /
  error-banner patterns for the new pipeline's network calls (`/v1/pose`, `/v1/detect`,
  `/v1/segment`, `/v1/analyze`), consistent with the "network required, no offline fallback"
  architectural decision. A "no serves detected" case (zero segments returned) mirrors Lite's
  existing `noPoseDetected` handling.
- **Tests** — backend: `/v1/segment/video` endpoint tests (synthetic clip via
  `cv2.VideoWriter`, matching `test_pose_benchmark.py`'s fixture pattern, stub pose/detection
  models via `app.dependency_overrides`), confirmation `pose_benchmark.py`'s re-export keeps
  working after the `sample_video_frames` promotion. iOS: `VideoSegmentationService` tests
  (decode/error handling via `StubURLProtocol`, not streamed-body inspection — `upload(for:fromFile:)`
  doesn't expose its body the way `data(for:)` does), pipeline orchestration tests against mocked
  networking, SwiftData model tests for the new schema, view-model tests for mode-selector
  persistence/branching and results-screen grouping/sorting logic. The camera resolution/fps lock
  is not unit-testable (`AVCaptureDevice.default(...)` returns `nil` on Simulator/CI) — manual
  device verification only.

## Out of Scope

- **Set Goal session mode, goal library, audible pass/fail cues.** Still P7.
- **Pro 3D mode / the 3-way mode selector.** Still P8.
- **Manual QA/correction step for Pro-detected phase frames.** Per the P4 roadmap note, Phase 7's
  manual-correction UI becomes *optional* QA in Pro modes, not required — this phase does not
  build that optional QA screen; auto-detected frames are used as-is.
- **Cross-serve cue prioritization or merging beyond simple per-serve grouping and a
  severity/phase sort.** No ranking heuristic across serves — "prioritized list" in
  `specs/mission.md` is satisfied by the major-before-minor sort within each serve.
- **Skeleton overlay, live pre-recording confidence check.** Still P13.
- **Serve-type awareness, multi-angle support, LLM coaching cues.** Still P14/P15/P16.
- **Any change to `PhaseReviewView`, the Lite pipeline/segmentation services
  (`PoseAnalysisPipeline`, `PoseEstimationService`, `ServeSegmentationService`, `PhaseGuesser`),
  or `ContentView`.** Isolation rule, unconditional.
- **Jetson / on-court deployment.** Still P17.
- **Changing `rules.json` thresholds or `detect_phases`/`segment_serves` heuristics.** This phase
  wires already-calibrated (P4/P4b/P5) logic into the app; it does not re-tune it. The camera
  resolution/fps lock changes what the heuristic *receives*, not the heuristic itself.
- **Making `segment_serves` robust to players with elaborate pre-serve routines, or re-encoding
  Photos-library imports to the locked resolution/fps.** Both confirmed as real, residual gaps
  during this phase's investigation (see Context and the roadmap TODO); both need dedicated
  P4b-style calibration work, not a quick fix — logged as follow-up, not built here.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Phase scope | Full continuous multi-serve Assessment (auto-segment a clip into several serves, loop `/v1/analyze` per serve, aggregate cues) rather than single-serve-only | User's explicit choice — matches `specs/mission.md`'s Assessment workflow description; backend's `segment_serves` already exists and is tested, so exposing it is tractable within this phase. |
| Mode selector location | Inline segmented control at the top of `VideoSourceSelectionView`, not a new screen and not inside `ContentView` | `ContentView` is a protected file per the isolation rule; the roadmap allows "a wrapper/parent view... introduced at session entry" as long as Lite's downstream views are navigated to unchanged — `VideoSourceSelectionView` acting as its own wrapper satisfies this literally. |
| Mode persistence | `@AppStorage`-backed, remembered across sessions, always changeable before recording | User's explicit choice — lowest friction for repeated testing of both modes. |
| `/v1/segment/video` endpoint | New endpoint wrapping existing `segment_serves` + `slice_detections_by_segments` (already promoted into `app/engine/phases.py`) behind a promoted `sample_video_frames` (moved into `app/services/video_sampler.py`), reusing exactly the OpenCV extraction path the calibration tooling already validated | Root-caused via direct-backend testing: `segment_serves` itself was already correct (confirmed on `ag_three_serves.MOV`); the bug was iOS's on-device `AVAssetImageGenerator`+`UIImage.jpegData` frame extraction/encoding not being pixel-equivalent enough to OpenCV's. Server-side extraction eliminates that whole class of bug by construction rather than chasing JPEG quality (0.85 → 0.95 tested, did not reliably fix the real-device case). |
| Analyze looping | iOS calls `/v1/segment/video` once, then `/v1/analyze` once per returned segment (not a single bulk backend call) | Matches Phase 3 backend scaffold's original framing verbatim: "Assessment loops one call per segmented serve; Set Goal calls it once per detected serve" — keeps the per-serve contract shared by both future workflows; unchanged by the video-upload pivot. |
| Video upload mechanism | Raw-body stream (`Content-Type: video/quicktime`, `URLSession.upload(for:fromFile:)`, backend `request.stream()` to a temp file) — no multipart envelope | Simplest form for a single file already on disk; avoids materializing the whole clip as in-memory `Data`. The now-unused per-frame `MultipartFormEncoder` was deleted (no surviving caller). |
| Pro 2D camera resolution/fps lock | `CameraService` locks Pro 2D live recording to `.hd1280x720`@30fps via a mode-gated `sessionMode` parameter; Lite's `.high` preset is unchanged | Tested across 5 real clips (`ag_three_serves.MOV` + `new_3_serve_clip.MOV` + 3 user-provided `test_2_serve_clip_*.MOV`) at their native resolutions/frame rates: all three 60fps/4K clips under-segmented identically (1 detected serve regardless of actual count) via the *direct backend path* (no iOS involved), while both 30fps clips did not have that failure mode. Locking the input configuration was chosen over trying to make `segment_serves` generalize across arbitrary camera settings — a genuinely open-ended problem (see Context) — per the user's explicit proposal. `CameraService` is shared by both modes and isn't on the protected Lite-isolation file list, but the lock is mode-gated regardless, since changing Lite's actual recorded resolution/fps is an unquantified risk to Lite's own, separately-calibrated on-device segmentation. |
| Results screen structure | Per-serve sections in chronological order; cues within each serve sorted major-before-minor, then by Kovacs phase order | Simplest structure that satisfies mission.md's "prioritized list" language without inventing an unspecified cross-serve ranking algorithm. |
| History screen | Mode-aware branching added to `SessionHistoryView`/`SessionHistoryRowView`; new `AssessmentHistoryDetailView` for Pro rows; `ContentView` untouched | Keeps Pro sessions visible in the existing History tab (consistent UX) while respecting the protected-file boundary literally. |
| Persistence shape | New `ServeResult`/`CueRecord` SwiftData models plus a `ServeSession.mode` field; `ServeSession.phases` untouched | Additive schema change only — no migration risk to existing Lite session rows (SwiftData lightweight-migrates new fields/relationships with defaults). |
| Checkpoint before pivot | The original per-frame-upload implementation was committed to the branch (`checkpoint: per-frame upload pipeline before video-upload pivot`) before deleting any of it | User's explicit choice — preserves a fully-tested, working alternative implementation in git history rather than losing it outright, recoverable via `git revert`/`git checkout <sha> -- <path>` if the video-upload approach needed to be rolled back. |

## Context

- **P1** built `POST /v1/pose` as a dormant, uncalled service; **P2** built `POST /v1/detect`
  similarly. Both remain dormant-but-tested after this phase's pivot — the app's live capture path
  now calls `POST /v1/segment/video` instead, which runs the same underlying pose/detection models
  server-side rather than over per-frame HTTP calls from iOS. `LiveCoachingService.analyze()`
  (also built dormant in P1) *is* wired into the app for the first time this phase, via the
  per-segment `/v1/analyze` loop — that part of P1's original framing held.
- **P4/P4b** built `segment_serves` (continuous-clip → per-serve frame lists) and `detect_phases`
  (six-frame Kovacs detection within one serve) entirely backend-side, validated via
  `backend/tools/segmentation_report.py` against real calibration footage. That tool already
  contains the exact frame/detection-slicing logic (`slice_detections_by_segments`) this phase
  needs to expose over HTTP — promoting it rather than re-deriving it keeps the production
  endpoint behavior identical to what's already been visually validated.
- **Mid-phase investigation (root cause + camera lock):** a real-device smoke test on a genuine
  3-serve clip reported "1 serve analyzed." Direct-backend testing (bypassing iOS entirely) with
  `segmentation_report.py` against the same P4b reference clip (`ag_three_serves.MOV`) confirmed
  `segment_serves` itself was correct — ruling out a heuristic bug and pointing at the iOS-side
  frame extraction/encoding pipeline. A follow-up pre-flight check against the user's actual
  failing clip (not just the calibration clip) — per this phase's own "stop and reassess" process —
  found the direct-backend path *also* under-segmented it (1 detected instead of 3), surfacing a
  second, independent problem: recording resolution/frame rate. Testing across 5 real clips (3
  additional ones the user recorded specifically at varying resolutions/frame rates for this
  investigation) found all three 60fps/4K clips under-segmented identically while both 30fps clips
  did not — motivating the Pro 2D camera lock. Four heuristic-generalization approaches were tried
  and rejected as universal fixes before landing on the input-constraint approach: lower-body-only
  velocity metric, global percentile-adaptive threshold, peak-detection with relative-floor
  spacing, and `MIN_REST_SECONDS` sweeping — each either failed to generalize across the 5 clips or
  broke a previously-working one. A residual gap (elaborate pre-serve routines can still cause a
  false split even at the locked resolution/fps) is disclosed, not fixed — see the roadmap TODO.
- **P5** calibrated `rules.json`'s 9 open-side rules against real 2D-measured joint angles. This
  phase is the first to exercise those rules against real user-submitted footage end-to-end,
  rather than through calibration tooling.
- **Three-mode isolation rule** (`specs/mission.md`, `specs/tech-stack.md`): off-device pose,
  object-detection, and coaching code is additive and mode-gated, and must never run inside or
  replace the Lite path. This phase's mode selector is designed specifically to satisfy that rule
  literally — living inside `VideoSourceSelectionView` rather than `ContentView`, and leaving
  every Lite-path file it's adjacent to (`PhaseReviewView`, `PoseAnalysisPipeline`,
  `PoseEstimationService`, `ServeSegmentationService`, `PhaseGuesser`) unmodified.
- **Backend hosting**: unchanged — same Mac dev host, same `BackendConfig.baseURL` LAN IP, same
  FastAPI app. Pro 2D just adds new routes to it.
- **`Cue.phase` is already a plain `String`** in iOS's `CoachingResult` (not the 3-case Lite
  `ServePhase` enum, which is a different, unrelated type also named `ServePhase` defined in
  `App/Models/ServePhase.swift`) — no naming collision to resolve, but care is needed when writing
  the results-screen phase-order sort to use the six-key backend phase strings
  (`start`/`release`/`trophy_pose`/`racket_drop`/`contact`/`finish`), not the Lite enum's three
  cases.
