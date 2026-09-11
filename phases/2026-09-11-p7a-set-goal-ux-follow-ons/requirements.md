# Phase P7a — Set Goal UX Follow-Ons (2D) — Requirements

## Scope

Six small, independent fixes/enhancements surfaced during P7's manual real-device testing
(`phases/2026-08-28-p7-goal-library-set-goal-2d/validation.md` Run Notes, "Follow-ups noted
during manual testing"), scheduled ahead of P7b so the second camera angle isn't calibrated on
top of a still-rough Set Goal UX. Each item below is independently shippable; none depends on
another within this phase.

## In Scope

### 1. Front camera for Set Goal

- `CameraService`/`CameraViewModel` already support camera-position toggling —
  `CameraViewModel.toggleCamera()` (`CameraViewModel.swift:67-73`) guards on `!isRecording` and
  calls `cameraService.toggleCamera(currentPosition:)`; `RecordServeView` already wires a rotate
  button to it (`RecordServeView.swift:24-33`, disabled while `cameraViewModel.isRecording`).
  `SetGoalSessionViewModel.cameraViewModel.isRecording` reflects `RecordingState.recording`, which
  `startChunkedRecording` sets (`CameraViewModel.swift:87`), so the same guard already prevents
  toggling mid-session with zero new logic.
- `SetGoalRecordingView` adds the identical rotate button (mirroring `RecordServeView.swift:24-33`
  verbatim in structure) bound to `viewModel.cameraViewModel.toggleCamera()`, disabled while
  `viewModel.isRecording`. No `CameraService`/`CameraViewModel` changes — this is a UI-only
  addition reusing existing capability.

### 2. Cancel/discard from the results screen

- `SetGoalRecordingView`'s summary sheet (`SetGoalRecordingView.swift:94-111`) gains a Cancel
  action alongside the existing Save button (`.cancellationAction` toolbar placement).
- Cancel discards the session: deletes the concatenated video at `viewModel.videoURL` (temp file
  from `ChunkVideoConcatenator`, never persisted to SwiftData) and the source chunk files, does
  **not** call `persist(to:)`, then calls `onDone()` — same navigation-back path as Save, just
  skipping persistence and cleaning up temp files instead of leaving them orphaned.
- Scope is the summary sheet only, per the roadmap's literal "results screen" wording — no new
  mid-recording abort affordance (recording can already be stopped via the existing Stop button;
  the summary sheet is the only place a completed-but-unwanted session currently has no exit
  besides force-saving).

### 3. Lite mode hides the Assessment/Set Goal toggle

- Investigate why the workflow `Picker` (`VideoSourceSelectionView.swift:35-43`, already gated
  `if viewModel.selectedMode == .pro2D`) is observed staying visible after switching to Lite,
  despite the gating conditional appearing correct in source. Likely candidate (to confirm, not
  assume): `selectedMode` (`VideoSourceSelectionViewModel.swift:37-40`) is a hand-written
  computed property (`UserDefaults`-backed get/set) on an `@Observable` class, rather than a
  plain stored property — worth checking directly whether SwiftUI's observation tracking is
  actually invalidating views that read it, since this is the one thing that structurally
  differs from every other `@Observable` property on this class.
- Fix is whatever the confirmed root cause requires — this item and #4 below likely share a root
  cause (both are `selectedMode`-visibility staleness bugs), so investigate together, but
  validate both repro scenarios independently since the roadmap lists them separately.

### 4. Toggle-visibility state bug (Lite → Record New → back arrow)

- Repro (from roadmap/validation.md): Lite → Record New → back arrow leaves the Assessment/Set
  Goal toggle hidden even after switching back to Pro 2D, until a Pro 2D → Record New → back
  arrow cycle restores it. "Root-cause and fix the underlying state, not just the symptom" per
  the roadmap's explicit instruction — a patch that only fixes this specific repro sequence
  without addressing #3's general staleness is not acceptable.

### 5. Skeleton overlay on Set Goal results

- Show one still frame with pose skeleton overlaid per serve on `GoalSessionHistoryDetailView`
  (currently pass/fail text only, `GoalSessionHistoryDetailView.swift`), matching Assessment's
  treatment (`PhaseFrameOverlayView.swift:8-15`, reused as-is — no changes to that view). "Matching
  the treatment" means the same skeleton-drawn-over-a-still-frame rendering, **including**
  Assessment's failing-joint highlight — see the highlight bullet below.
- **Single frame per serve** (roadmap: "a still frame... per serve", singular) — not Assessment's
  four-phase treatment. **Frame phase matches the active goal's own phase, not always contact.**
  Each `rules.json` rule already declares which `ServePhase` it evaluates (`_Rule.phase`,
  `backend/app/engine/rules.py:23`) — e.g. a toss-related goal (`view`/metric keyed to the toss
  phase) shows the toss-phase frame, a trophy-pose goal shows the trophy-pose frame, a contact
  goal shows the contact frame, etc. Since a Set Goal session evaluates exactly one
  `goal_rule_id` for its whole duration, this is still a single, well-defined frame per serve —
  just keyed off that rule's `phase` field instead of hardcoding `ServePhase.contact`.
- **Failing-joint highlight**: `PhaseFrameOverlayView` is called with the real firing `Cue` as
  `highlightedCue` when the serve fails the goal (reusing Assessment's existing highlight geometry
  — `Cue.joints`/`measured_value`/`comparison`/`threshold*` already carry everything
  `PhaseFrameOverlayView` needs, no new drawing logic required), and `highlightedCue: nil` (skeleton
  only) when the serve passes, since there's no failing joint to highlight on a pass. This means
  the backend must return the firing `Cue` itself (not just pass/fail + `spoken_cue`) alongside the
  phase frame's keypoints/detections — see the keypoints bullet below.
- **Extraction: iOS, post-finalize** — mirrors Assessment's own approach
  (`ProServeAnalysisPipeline.swift:75-87`'s `PhaseFrameImageExtractor`, extracting stills
  client-side from the fully assembled local video). No backend image work. Concretely: after
  `ChunkVideoConcatenator.concatenate` produces the session's single video
  (`SetGoalSessionViewModel.swift` `finalizeVideo()`), extract the goal-phase still frame for
  each confirmed segment from that assembled video, at the timestamp the backend reports for that
  phase (see below).
- **Keypoints + cue**: the backend already computes per-chunk `Frame`/`Detection` data for scoring
  (`goal_session.py:69-71`) but discards it on `is_final=true` (`goal_session.py:93-94`) and never
  returns it to iOS; `score_segment` also already evaluates every rule's cue internally
  (`scoring.py`'s `cues` list) — the goal rule's own cue (fired or not) is already computed, not
  new work. Extending `GoalChunkResult` to include the goal-phase frame's keypoints/detections
  (backend-computed, not re-derived client-side — iOS has no pose model) plus the firing `Cue`
  (`None` on a pass) is in scope; this is additive to the existing chunk response and happens on
  the same request/response the session already makes, **not** a new round trip. This does not
  touch Check C's critical path: per the pre-research finding, Check C times contact→spoken-cue
  during live recording, before `stopSession()`/`finalizeVideo()`; the additional response payload
  (one small JSON object per newly-confirmed segment — comparable in size to the existing `cues`
  on `/v1/analyze`) adds negligible per-chunk transfer/encode time, well within the existing
  latency budget's margin (`latency-findings.md`'s ~2.4–4.4s budget vs. the measured ~4s actual).
  No frame **image** is sent from the backend — only keypoints/detections/cue (small JSON), keeping
  payload size in the same class as today's response.
- **New SwiftData model**: `GoalPhaseFrameRecord` (Set Goal's equivalent of `PhaseFrameRecord`,
  `PhaseFrameRecord.swift:10-20`) storing `frameImageData` (extracted client-side),
  `keypointsJSON`/`detectionsJSON`/`cueJSON` (from the backend response, `cueJSON` empty/absent on
  a pass), keyed per `GoalAttemptRecord`.
- **Known timing-precision limitation, inherited from P7**: the backend's buffer timestamps
  (`goal_session_buffer.append_chunk`) are computed from an assumed-fps approximation of each
  chunk's duration (`_CHUNK_FPS`, `len(sampled) * stride / _CHUNK_FPS`), not each chunk's actual
  recorded duration — and P7 already accepted a small real-time gap at every chunk boundary
  (`AVCaptureMovieFileOutput` stop/restart, `requirements.md`'s "Chunk rotation gap" Out of
  Scope item). Both effects mean the backend's contact-frame timestamp can drift slightly from
  where that instant actually lands in `ChunkVideoConcatenator`'s concatenated video, growing
  with more chunks/longer sessions. Unlike Assessment's exact (±0s) seek
  (`PhaseFrameImageExtractor.swift:33-34`, whose comment explains why: keypoints must land on
  the same frame they were drawn from), Set Goal's extraction uses a small nonzero tolerance
  (~±0.15s, roughly the width of a few sampled frames at `stride=2`/30fps) to absorb this drift
  rather than risk silently returning no frame. This is a deliberate, documented approximation
  for a display-only overlay on a pass/fail drill, not a precision-critical measurement.
- **Mandatory latency re-check**: a real-device re-run of Check C (contact→spoken-cue, median
  ≤5s/max ≤8s, matching `validation.md`'s ~4s baseline) is required post-implementation — not a
  design assertion. This is the acceptance criterion that actually closes the loop on the
  pre-research question that motivated this phase.

### 6. More specific spoken cues on goal miss

- Each `rules.json` rule already encodes a comparison direction against a threshold (`gte`/`lte`/
  `range`, `backend/app/engine/rules.py:60-108`) — a failing value is provably either below a
  `gte` threshold, above an `lte` threshold, or outside a `range`'s min/max. This is enough
  information to derive *which direction* the metric missed by, without any new calibration.
- Add a per-rule direction-phrase pair (e.g. `{low: "too low", high: "too high"}`, worded per
  rule since "too low"/"too high" doesn't fit every metric — e.g. an angle rule might need "not
  bent enough"/"too bent") in backend code, not `rules.json` — `rules.json` stays the calibrated-
  threshold source of truth; the phrase table is presentation logic. Combined with the existing
  rule `message` template at scoring time (`score_segment`/`evaluate_rules`) to produce a more
  actionable `spoken_cue` for Set Goal specifically. Regular Assessment cues (`Cue.message`) are
  unaffected — this only changes `GoalResult.spoken_cue` construction, not `evaluate_rules`'s
  `Cue.message` output used elsewhere.

## Out of Scope

- **Multi-frame (4-phase) skeleton overlay parity with Assessment.** Single contact frame only,
  per the roadmap's singular wording (#5 above).
- **Backend-side frame image capture/persistence for the skeleton overlay.** iOS extracts the
  still image client-side from the assembled video; the backend returns keypoints/detections
  only, not image bytes (#5 above).
- **A new `GET`/session-recovery endpoint for retrieving pose data after buffer eviction.** The
  contact-frame keypoints/detections ride the existing per-chunk response; no new backend surface.
- **Changing any `rules.json` threshold or calibration.** #6's directional cues are a
  presentation-layer addition over already-calibrated (P5) comparisons.
- **Mid-recording session abort UI.** #2's Cancel is results-screen-only, per the roadmap's
  literal scope.
- **Any change to Assessment's existing skeleton overlay, `Cue.message`, or `/v1/analyze`
  contract.** #5 and #6 are additive/Set-Goal-scoped; Assessment's existing behavior is
  unchanged.
- **Pro 3D, P7b (behind-server camera), or any other roadmap phase's scope.**

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Skeleton overlay frame count | Single frame per serve, at the active goal's own `ServePhase` | User confirmed both the single-frame count (matches roadmap's singular "a still frame... per serve" wording) and that the phase must match the goal, not be hardcoded to contact — e.g. a toss goal shows the toss frame. Each rule already declares its `phase` (`_Rule.phase`), so this is a lookup, not new calibration. |
| Skeleton overlay extraction owner | iOS, client-side, post-finalize | User confirmed; mirrors Assessment's existing `PhaseFrameImageExtractor` pattern; keeps zero cost on Check C's critical path (extraction happens after `stopSession()`, after every spoken cue for the session has already fired) and requires no new backend round trip. |
| Skeleton overlay keypoint source | Backend-computed, riding the existing chunk response (not a new endpoint) | Backend already computes per-chunk pose/detections for scoring (`goal_session.py:69-71`); returning them alongside the existing `GoalResult` on the same request avoids re-deriving pose on-device (iOS has no pose model) without adding a new round trip. |
| Failing-joint highlight | Included — pass the firing `Cue` as `highlightedCue` on a miss, `nil` on a pass | User confirmed. `Cue` already carries the joints/measured-value/threshold data `PhaseFrameOverlayView`'s highlight geometry needs (built for Assessment), and `score_segment` already evaluates the goal rule's cue every chunk — no new computation, just returning what already exists. |
| Skeleton overlay frame-extraction tolerance | ~±0.15s (not Assessment's exact ±0s) | Backend buffer timestamps are an assumed-fps approximation of chunk duration, and P7 already accepted a small real-time gap at each chunk boundary; both drift the backend's contact-frame timestamp away from its true position in the concatenated video as sessions get longer. A small tolerance absorbs this for a display-only overlay rather than risking a silently-missing frame. |
| Latency re-verification | Mandatory real-device Check C re-run (median ≤5s/max ≤8s) post-implementation | The pre-research question that motivated speccing this item first — a design argument alone doesn't close it; only a measured re-run does. |
| Spoken cue directionality | Derive from existing rule comparison direction (gte/lte/range) in backend code; `rules.json` unchanged | User confirmed; reuses calibrated thresholds as-is, no new calibration surface, no risk of hand-authored variant messages drifting from the actual threshold logic. |
| Cancel/discard scope | Summary sheet only | User confirmed; matches the roadmap's literal "results screen" wording; Stop already exists as the mid-recording exit. |
| Toggle-visibility bug fix depth | Root-cause both #3 and #4 together (likely shared cause), validate both repro scenarios independently | Roadmap explicitly requires root-causing rather than patching the specific back-arrow repro; the two bullets are almost certainly the same underlying `selectedMode`-observability issue. |
| Camera-toggle reuse | Reuse `CameraViewModel.toggleCamera()`/`CameraService.toggleCamera(currentPosition:)` unchanged | Already built and already guards against mid-recording toggling (`!isRecording`); Set Goal needs only the same UI affordance `RecordServeView` already has, zero new camera logic. |

## Context

- Directly follows **P7** (`phases/2026-08-28-p7-goal-library-set-goal-2d/`), whose
  `validation.md` Run Notes recorded these six items as non-blocking follow-ups from the
  2026-09-02 manual real-device pass. P7's own `requirements.md` explicitly deferred skeleton
  overlay: "Skeleton overlay / deviation-caption UI for Set Goal... isn't needed for a pass/fail
  drill" (`requirements.md:147-148`) and its `plan.md` built `GoalSessionHistoryDetailView`
  intentionally without it (`plan.md:687-692`).
- **Check C is the latency gate this phase must not regress.** P7's `validation.md:169-170`:
  "Check C — latency: PASS. Eyeballed, contact→cue consistently ~4s across serves — within the
  median ≤5s / max ≤8s bar. Config: `fused/mps`." Check C times the live per-chunk pipeline
  (contact detection → spoken cue via `AVSpeechSynthesizer`), measured *during recording*, before
  `stopSession()`/`finalizeVideo()` run. The skeleton overlay (#5) only renders on the results
  screen, which is only reachable after `stopSession()` completes — structurally after every cue
  in the session has already been spoken. The one design that *would* regress Check C — bundling
  frame/keypoint data into the per-chunk response in a way that meaningfully grows its payload or
  adds synchronous work before `speak()` can fire — is explicitly avoided by this phase's design
  (small additive JSON fields on the existing response, no image bytes, no new round trip).
- Reuses existing machinery throughout: `PhaseFrameOverlayView` (Canvas skeleton renderer),
  `CameraViewModel.toggleCamera()`, `ChunkVideoConcatenator`, the P7 chunk-response shape
  (`GoalChunkResult`), and P5's calibrated `rules.json` thresholds — no new calibration, no new
  transport mechanism, no new pose model.
- **Isolation rule** (`mission.md`/`tech-stack.md`): none of this touches Lite mode's pipeline —
  #3/#4 touch only the Pro-2D/Lite mode-selector shell (`VideoSourceSelectionView`/`ViewModel`),
  not `PhaseReviewView`, the Lite pipeline/segmentation services, or `ContentView`. Matches the
  roadmap's own P7a framing: "Lite mode is untouched except for the toggle-visibility fixes
  above, which only affect the Pro-2D/Lite mode-selector shell, not Lite's pipeline or views."
