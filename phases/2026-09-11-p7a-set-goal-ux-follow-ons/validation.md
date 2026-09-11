# Phase P7a — Validation

## Definition of Done

Every row below passes, `scripts/verify.sh backend` and `scripts/verify.sh ios` are green, and
the mandatory Check C re-run (row 12) meets P7's original bar on a real device.

### Group 1 — Front Camera

| # | Check | How to verify |
|---|-------|----------------|
| 1 | Rotate-camera button present in `SetGoalRecordingView`, mirrors `RecordServeView`'s | Real device: open Set Goal recording screen (not yet recording), tap rotate button, confirm preview flips front/back. |
| 2 | Toggle disabled mid-recording | Real device: start a Set Goal session, confirm the rotate button is disabled/unresponsive while `isRecording` is true. |

### Group 2 — Cancel/Discard

| # | Check | How to verify |
|---|-------|----------------|
| 3 | `discard()` removes temp video + chunk files, doesn't persist | `SetGoalSessionViewModelTests`: assert files removed from disk and no `GoalSession` inserted into `ModelContext`. |
| 4 | Discard button on summary sheet returns to mode selection | Real device: complete a Set Goal session, tap Discard on the results sheet, confirm no entry appears in Goal History afterward. |

### Group 3 — Toggle-Visibility Bug

| # | Check | How to verify |
|---|-------|----------------|
| 5 | Lite mode never shows the Assessment/Set Goal workflow toggle | Real device: select Lite, confirm the workflow `Picker` from `VideoSourceSelectionView.swift:35-43` is not shown. |
| 6 | Toggle reappears immediately after Lite → Record New → back-arrow → Pro 2D, no extra navigation cycle needed | Real device: repro the exact sequence from the roadmap bullet, confirm the toggle is visible on first return to Pro 2D, not after a second round trip. |
| 7 | Unit coverage for `selectedMode` observability | `VideoSourceSelectionViewModelTests`: new cases from plan.md step 10 pass. |

*Rows 5–6 are outcome-based — they verify the symptom is gone regardless of which root cause
`/phase` step 8 confirms. The specific fix mechanism in plan.md step 9 is a starting hypothesis,
not a hard requirement, provided rows 5–6 pass and the fix is a real root-cause fix (not a
targeted patch for only the back-arrow repro, per requirements.md's explicit instruction).*

### Group 4 — Backend Goal-Phase Frame + Firing Cue

| # | Check | How to verify |
|---|-------|----------------|
| 8 | `GoalChunkResult.phase_frame` populated when a frame at the goal's own phase is detected, `None` otherwise; `GoalResult.phase` always populated; `GoalResult.cue` present on a miss, `None` on a pass | `test_goal_session_endpoint.py` new cases from plan.md step 17 pass — including a case where the goal targets a **non-contact** phase (e.g. `trophy_pose`), proving the frame follows the goal's phase rather than being hardcoded to contact. |
| 9 | Existing chunk-response fields (`goal_result.passed`/`spoken_cue`, etc.) unchanged for callers ignoring the new fields | Existing `test_goal_session_endpoint.py` assertions still pass unmodified — additive-only change. |

### Group 5 — iOS Skeleton Overlay + Failing-Joint Highlight

| # | Check | How to verify |
|---|-------|----------------|
| 10 | Goal-phase still image + skeleton + cue persisted per attempt via `GoalPhaseFrameRecord` | `SetGoalSessionViewModelTests` new cases (plan.md step 31) pass — `finalizeVideo()` populates `stillImage`, `persist(to:)` attaches `GoalPhaseFrameRecord` with `cueJSON` set on a miss and nil on a pass. |
| 11 | Overlay renders on both the live results sheet and saved history detail view, with the failing-joint highlight visible on a missed serve and skeleton-only on a passed serve; degrades gracefully (no crash, pass/fail-only fallback) when no phase frame exists | `GoalSessionHistoryDetailViewTests` snapshot/ViewInspector cases (plan.md step 31) pass — **required for merge**, not best-effort, matching Assessment's own overlay test coverage precedent. Real device: confirm visually on both screens, including a passed serve (no highlight), a missed serve (highlight present), and a serve with no detected phase frame. |
| 12 | **Mandatory — Check C re-run: contact→spoken-cue latency unaffected by this phase** | Real device, same config as P7's baseline (`fused/mps`). Record a fresh multi-serve Set Goal session, measure wall-clock contact→spoken-cue latency the same way P7 measured it. **Bar: median ≤5s, max ≤8s** (P7 baseline ~4s). Record the measured numbers in this file's Run Notes. **This is a hard merge blocker** — if the bar isn't met, Group 5's extraction/persistence design must be revisited (e.g., confirm no accidental synchronous work landed on the per-chunk path) before merge, not just noted as a known issue. |
| 13 | `PhaseFrameImageExtractor`'s new `tolerance` parameter defaults to `.zero`, preserving Assessment's existing exact-seek behavior | `PhaseFrameImageExtractorTests` regression case (plan.md step 31) — Assessment's existing exact-seek tests still pass unmodified. |
| 14 | Frame shown matches the goal's own phase, not always contact | Real device: set a goal whose rule targets a non-contact phase (e.g. a trophy-pose rule), confirm the history detail view shows the trophy-pose frame for that session, not a contact frame. |

### Group 6 — Directional Spoken Cues

| # | Check | How to verify |
|---|-------|----------------|
| 15 | `directional_spoken_cue` returns correct low/high phrase per rule comparison type (`gte`/`lte`/`range`, both range directions), falls back to `rule.message` when no phrase is defined | `test_goal_cues.py` (or `test_scoring.py`) new cases from plan.md step 35 pass. |
| 16 | `GoalResult.spoken_cue` uses directional phrasing on a miss; `Cue.message`/Assessment's `AnalyzeResponse.cues` unaffected | `test_scoring.py`/`test_analyze.py` updated case (plan.md step 36) — Set Goal path changed, Assessment path unchanged. |
| 17 | Directional cues audible in a live session | Real device: force a goal miss on a rule with a defined directional phrase (e.g., trophy elbow-line), confirm the spoken cue uses the more specific phrasing. |

### Cross-Cutting

| # | Check | How to verify |
|---|-------|----------------|
| 18 | No changes outside this phase's scope | `git diff --name-only develop...HEAD` — confirm `PhaseReviewView.swift`, Lite pipeline/segmentation service files, and `ContentView.swift` do not appear. |
| 19 | Full automated suite green | `scripts/verify.sh backend` and `scripts/verify.sh ios` both pass. |

## Merge Criteria

- All Definition of Done rows above pass.
- `scripts/verify.sh backend` and `scripts/verify.sh ios` are green.
- **Row 12 (Check C re-run) is a hard blocker** — median ≤5s / max ≤8s on a real device, matching
  P7's ~4s baseline. A design argument that the overlay work is off the critical path does not
  satisfy this row; only a measured re-run does.
- Row 11's snapshot/ViewInspector coverage for the new overlay views is required, not optional,
  matching the coverage precedent already established for Assessment's equivalent views, and must
  cover both the failing-joint-highlight and skeleton-only rendering paths.
- Group 3's fix is verified by the two outcome-based repro checks (rows 5–6), not by matching a
  predetermined fix mechanism.

## Run Notes

_(Filled in during `/phase` and `/phase-review` — Check C measured numbers, root cause confirmed
for Group 3, any deferred follow-ups.)_

### Group 3 root cause (confirmed via source inspection)

`selectedMode` (`VideoSourceSelectionViewModel.swift`) was a fully hand-written computed
property (explicit `get`/`set`, backed directly by `UserDefaults`) on an `@Observable` class.
Swift's `@Observable` macro only injects `access(keyPath:)`/`withMutation(keyPath:)` tracking
calls for property declarations it transforms itself (plain stored `var`s, or ones with
`willSet`/`didSet`). A property already written as a full computed `get`/`set` is left
untouched by the macro — its reads never register a dependency with SwiftUI's observation
registrar, and its writes never fire an invalidation. Every other property on this class is a
plain stored property and gets this instrumentation automatically; `selectedMode` was the one
exception.

Effect: `VideoSourceSelectionView`'s body only picks up the current `selectedMode` value when it
happens to re-render for some other, properly-tracked reason (e.g. `selectedWorkflow` or a
navigation flag changing) — not when `selectedMode` itself changes. This explains both roadmap
repros as the same bug: the toggle's visibility condition (`selectedMode == .pro2D`) reads a
value that isn't wired into observation at all, so it goes stale until an unrelated re-render
happens to refresh it. A patch scoped to only the back-arrow repro would not have addressed the
Lite-mode symptom (or any other path that hits the same untracked read).

Fix: replaced the hand-rolled computed property with a real `@ObservationIgnored`-free stored
property (`_selectedMode`, tracked by the macro) plus a computed `selectedMode` wrapper whose
setter both updates the tracked stored value and mirrors it to `UserDefaults` as a side effect;
the getter reads the tracked stored value directly (no longer round-tripping through
`UserDefaults` on every read). `UserDefaults` is now only touched on write and at `init` (to
restore the last-persisted value), not on every read.

### Automated verification (2026-09-11)

- `scripts/verify.sh backend`: 241 passed, 3 skipped — green.
- `scripts/verify.sh ios` (raw `xcodebuild test`, iPhone 17 Pro / iOS 26.4): **TEST SUCCEEDED** — green.
- `git diff --name-only develop...HEAD` (working tree): only files under `MyServeCoach/MyServeCoach/App/**`, `MyServeCoach/MyServeCoachTests/**`, `backend/app/**`, `backend/tests/**`, and this phase's own `phases/2026-09-11-p7a-set-goal-ux-follow-ons/` docs. `PhaseReviewView.swift`, the Lite pipeline/segmentation service files, and `ContentView.swift` do not appear — row 18 confirmed.
- Rows 1–17 requiring a real device (1, 2, 4, 5, 6, 11's visual half, 12, 14, 17) are **not yet exercised** — they need physical-device hands-on verification before merge, most critically **row 12's Check C latency re-run, a hard merge blocker**. Numbers to be filled in here once run.

### Real-device manual pass (2026-09-11)

All rows requiring a real device (1, 2, 4, 5, 6, 11, 12, 14, 17) now pass. Four bugs surfaced and
fixed during this pass:

1. **False serve-detection triggering on front camera only.** `CameraService._updateMirroring`
   was mirroring `movieOutput`'s `AVCaptureConnection` (the recorded/uploaded file), not just the
   preview connection. A mirrored recording flips left/right, corrupting pose left/right wrist
   semantics against the backend's hardcoded `HANDEDNESS` (right-handed) assumption in
   `phases.py`, producing spurious serve peaks on idle motion. Fixed by excluding `movieOutput`'s
   connection from the mirroring loop — only the preview connection mirrors now.
2. **No stillImage/skeleton overlays rendered anywhere.** `ChunkVideoConcatenator` used
   `AVAssetExportPresetHighestQuality`, which intermittently failed
   (`exportFailed("Operation Stopped")`, likely encoder issues with inter-chunk audio format
   variance) — previously swallowed silently by a bare `try?` in
   `SetGoalSessionViewModel.finalizeVideo()`, so the failure was invisible. Fixed by switching to
   `AVAssetExportPresetPassthrough` (valid here since every chunk in a session shares identical
   locked capture settings, and the output is only ever used for still-frame extraction, never
   played back) and by logging the real error instead of swallowing it.
3. **stillImage correct on serve 1, wrong on later serves (skeleton stayed correct throughout).**
   Root cause: `goal_session_buffer.append_chunk`'s `next_offset` advanced by an approximation
   (`len(sampled) * stride / 30fps`, hardcoded fps, ignoring unsampled tail frames) instead of
   each chunk's true duration — a small per-chunk error that compounded across chunks, drifting
   the backend's buffer-relative phase-frame timestamp further from the client's own
   independently-concatenated video timeline with each additional serve. Fixed by adding
   `video_sampler.video_duration_seconds()` (true `frame_count / fps` per chunk) and threading
   that real duration into `append_chunk` in place of the approximation.
4. **Directional cue for `trophy_hitting_elbow_shoulder_line` always said "Raise," regardless of
   whether the elbow was too high or too low.** Root cause: this rule's "angle" metric is an
   unsigned vertex angle (`math.acos`, clamped to [0, 180]), and its range's `threshold_max` is
   180 — the metric's own ceiling. A real miss is therefore always `value < threshold_min`; the
   "too high" branch of the generic value-vs-threshold direction logic was mathematically
   unreachable. Fixed by adding a frame-based signed check (`_trophy_elbow_direction` in
   `goal_cues.py`, using the 2D cross product of the shoulder line against the shoulder→elbow
   vector — sign survives, unlike `acos`) used only for this rule's phrase selection; pass/fail
   threshold logic is unchanged.

`scripts/verify.sh backend`: 246 passed, 3 skipped — green.
`scripts/verify.sh ios`: exit 0, all reported test cases passed — green.

**Row 12 (Check C re-run):** contact→spoken-cue latency measured on real device, `fused/mps`
config, fresh multi-serve Set Goal session — median ~4s, matching P7's baseline. Passes the
median ≤5s / max ≤8s bar. Hard merge blocker satisfied.

### Phase-review findings (2026-09-11) — fixed

- **Backend**: `directional_spoken_cue`'s `_DIRECTION_PHRASES` gained test coverage for the two
  previously-untested range rules (`trophy_hitting_elbow_shoulder_line`,
  `contact_shoulders_stacked`); table type narrowed to `str | tuple[str, str]` so single-direction
  (`gte`/`lte`) rules no longer carry a duplicate identical phrase in both tuple slots.
- **iOS**: `discardRemovesFilesAndDoesNotPersist`'s vacuous non-persistence assertion (checked an
  unrelated fresh `ModelContext`, not one `discard()` could ever touch — `discard()` takes no
  `ModelContext` parameter) removed; renamed to `discardRemovesFiles`/reflects what it actually
  tests. Non-persistence remains a caller-side contract verified by the manual device pass (row 4).
  `GoalResult.init`'s `phase` parameter lost its test-only `"contact"` default (all call sites now
  pass it explicitly). Extracted shared `PhaseFrameDecoding` helper, deduplicating the
  image/keypoints/detections decode between `AssessmentHistoryPresenter` and the renamed
  `PersistedGoalAttemptDisplay` (was `GoalAttemptRowDisplay` — renamed to disambiguate from the
  live-session `GoalAttemptDisplay`, and marked `@MainActor` to match the precedent it mirrors).
  `GoalPhaseFrameRecord.cueJSON`'s departure from Assessment's typed `CueRecord` pattern now has an
  explanatory comment (no aggregation/query need here, unlike Assessment's major/minor counts).
- **Left as documented, not fixed**: the two untested-rule findings above are pinning tests for
  already-implemented behavior, not new calibration — sign correctness still rests on validation.md
  row 17's manual real-device listen, per the original phase-review note.
