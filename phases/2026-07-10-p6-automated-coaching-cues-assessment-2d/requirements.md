# Phase P6 — Automated Coaching Cues / Assessment (2D) — Requirements

## Scope

Build the first fully usable Pro 2D experience: a **Lite / Pro 2D mode selector** at session
entry, and — when Pro 2D is selected — a continuous multi-serve **Assessment** capture that
routes a recording through the off-device pose (P1) and object-detection (P2) services, the
already-proven backend segmentation (P4/P4b) and rule engine (P5), and displays the resulting
per-serve coaching cues on a new Pro-mode-gated results screen. This is the first phase to call
`POST /v1/pose`, `POST /v1/detect`, and `POST /v1/analyze` from the app, and the first to expose
serve segmentation (`segment_serves`) over HTTP.

Per the user's explicit choice, this phase builds **full continuous multi-serve Assessment** (one
clip, multiple back-to-back serves, auto-segmented and each analyzed), not a single-serve-only
version — matching `specs/mission.md`'s Assessment workflow description literally rather than the
narrower single-serve reading of the roadmap's phase body text.

Scope spans both backend (new `/v1/segment` endpoint) and iOS (mode selector, off-device capture
pipeline, results screen, SwiftData persistence, History integration).

## In Scope

- **Mode selector** — a Lite / Pro 2D segmented control added inline at the top of
  `VideoSourceSelectionView`'s body (not `ContentView`, which is a protected file). Last choice
  persisted via `@AppStorage` as the default for next session, always changeable before
  recording. Selecting Lite leaves the existing `RecordServeView` → `PoseAnalysisPipeline` →
  `PhaseReviewView` → `ReferenceFrameFetchView` path completely unchanged and reachable
  byte-for-byte as today. Selecting Pro 2D branches into the new pipeline below, reusing the same
  `RecordServeView` (camera) and `PhotosPicker` (library import) entry points unchanged — only
  post-capture processing differs by mode.
- **Off-device capture pipeline (iOS)** — new pipeline (e.g. `ProServeAnalysisPipeline`) that,
  given a recorded/imported video URL:
  1. Samples the full clip via the existing `FrameSamplerService.sampleFrames(from:)` at
     **stride 2** (matching P4b's real-footage-validated density for the off-device pipeline —
     not Lite's Vision-tuned `PoseConstants.kPoseSampleStride = 3`).
  2. JPEG-encodes each sampled `CGImage` and uploads all frames concurrently (`async let`) to
     `POST /v1/pose` and `POST /v1/detect` via a new small multipart form-data encoder utility
     (the first multipart HTTP caller in the app — P1 built both endpoints service-layer-only
     with no client).
  3. POSTs the combined `frames` + `detections` to the new `POST /v1/segment` endpoint to split
     the clip into per-serve segments.
  4. Loops `POST /v1/analyze` once per returned segment (mirrors Phase 3's original framing:
     "Assessment loops one call per segmented serve"), collecting one `CoachingResult` per serve.
- **`LiveCoachingService.analyze()` extension** — add a `detections: [[Detection]]?` parameter/
  field to the request body, matching the backend's existing `AnalyzeRequest.detections`. New
  Swift `Detection`/`BoundingBox` `Codable` types mirroring `app/models.py`.
- **New backend endpoint `POST /v1/segment`** (`backend/app/routers/segment.py`) — request shape
  mirrors `AnalyzeRequest` (`frames`, `detections`, `session_id`); response is a list of segments,
  each with its own `frames` and `detections`, ready to feed directly into a subsequent
  `/v1/analyze` call. Implemented by promoting `segment_serves` (already in
  `app/engine/phases.py`) and `slice_detections_by_segments` (currently only in
  `backend/tools/segmentation_report.py`) into production engine code; `segmentation_report.py`
  updated to import the promoted helper instead of defining its own copy.
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
- **Tests** — backend: `/v1/segment` endpoint tests, tests for the promoted
  `slice_detections_by_segments` helper, confirmation `segmentation_report.py` still produces
  identical output after the promotion. iOS: multipart encoder unit tests, pipeline orchestration
  tests against mocked networking, SwiftData model tests for the new schema, view-model tests for
  mode-selector persistence/branching and results-screen grouping/sorting logic.

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
  wires already-calibrated (P4/P4b/P5) logic into the app; it does not re-tune it.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Phase scope | Full continuous multi-serve Assessment (auto-segment a clip into several serves, loop `/v1/analyze` per serve, aggregate cues) rather than single-serve-only | User's explicit choice — matches `specs/mission.md`'s Assessment workflow description; backend's `segment_serves` already exists and is tested, so exposing it is tractable within this phase. |
| Mode selector location | Inline segmented control at the top of `VideoSourceSelectionView`, not a new screen and not inside `ContentView` | `ContentView` is a protected file per the isolation rule; the roadmap allows "a wrapper/parent view... introduced at session entry" as long as Lite's downstream views are navigated to unchanged — `VideoSourceSelectionView` acting as its own wrapper satisfies this literally. |
| Mode persistence | `@AppStorage`-backed, remembered across sessions, always changeable before recording | User's explicit choice — lowest friction for repeated testing of both modes. |
| `/v1/segment` endpoint | New endpoint wrapping existing `segment_serves` + a promoted `slice_detections_by_segments` (moved from `tools/segmentation_report.py` into `app/engine/phases.py`) | Reuses already-tested logic rather than duplicating it; promoting the helper out of `tools/` into production engine code is the natural home now that it's used by more than one dev tool. |
| Analyze looping | iOS calls `/v1/segment` once, then `/v1/analyze` once per returned segment (not a single bulk backend call) | Matches Phase 3 backend scaffold's original framing verbatim: "Assessment loops one call per segmented serve; Set Goal calls it once per detected serve" — keeps the per-serve contract shared by both future workflows. |
| Capture sample stride | 2 (not Lite's `kPoseSampleStride = 3`) | P4b explicitly tuned stride 2 against real footage for the off-device pose+detection pipeline specifically to avoid missing fast swings between samples; reusing Lite's Vision-tuned constant would reintroduce the problem P4b fixed. |
| Multipart upload | New `MultipartFormEncoder` utility, first HTTP multipart caller in the app | `/v1/pose` and `/v1/detect` were built service-layer-only in P1 with no client; this phase is their first caller and needs the encoding utility that was intentionally deferred then. |
| `/v1/pose` + `/v1/detect` concurrency | Called concurrently via `async let` on the same sampled frames | Both take identical input independently; no reason to serialize two independent model-inference calls. |
| Results screen structure | Per-serve sections in chronological order; cues within each serve sorted major-before-minor, then by Kovacs phase order | Simplest structure that satisfies mission.md's "prioritized list" language without inventing an unspecified cross-serve ranking algorithm. |
| History screen | Mode-aware branching added to `SessionHistoryView`/`SessionHistoryRowView`; new `AssessmentHistoryDetailView` for Pro rows; `ContentView` untouched | Keeps Pro sessions visible in the existing History tab (consistent UX) while respecting the protected-file boundary literally. |
| Persistence shape | New `ServeResult`/`CueRecord` SwiftData models plus a `ServeSession.mode` field; `ServeSession.phases` untouched | Additive schema change only — no migration risk to existing Lite session rows (SwiftData lightweight-migrates new fields/relationships with defaults). |

## Context

- **P1** built `POST /v1/pose` and `LiveCoachingService.analyze()` as dormant, uncalled
  services — explicitly deferring the in-app caller and multipart encoding to a later phase. This
  phase is that caller.
- **P2** built the racket/ball object detector behind `POST /v1/detect`, also previously uncalled
  from the app.
- **P4/P4b** built `segment_serves` (continuous-clip → per-serve frame lists) and `detect_phases`
  (six-frame Kovacs detection within one serve) entirely backend-side, validated via
  `backend/tools/segmentation_report.py` against real calibration footage. That tool already
  contains the exact frame/detection-slicing logic (`slice_detections_by_segments`) this phase
  needs to expose over HTTP — promoting it rather than re-deriving it keeps the production
  endpoint behavior identical to what's already been visually validated.
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
