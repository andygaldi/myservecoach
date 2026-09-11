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
