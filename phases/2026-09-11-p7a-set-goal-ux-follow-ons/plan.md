# Phase P7a — Plan

> **Isolation note:** Groups 3a/3b touch only `VideoSourceSelectionView`/`ViewModel` (the Pro-2D/
> Lite mode-selector shell). No group touches `PhaseReviewView`, the Lite pipeline/segmentation
> services, or `ContentView`.

> **Dependency note:** Group 5 (iOS skeleton overlay) consumes the `phase_frame`/`cue` fields
> Group 4 (backend) adds to `GoalChunkResult` — run Group 4 before Group 5. Groups 1, 2, 3, 6 are
> each independent of every other group and of each other.

## Group 1 — iOS: Front Camera for Set Goal (surface: `ios`)

1. `SetGoalRecordingView.swift`: add a camera-rotate button, structurally identical to
   `RecordServeView.swift:24-33` — an `HStack { Spacer(); Button(...) { Image(systemName:
   "camera.rotate") ... } }` placed above `tallyHeader`/`errorMessage`, calling
   `viewModel.cameraViewModel.toggleCamera()`, `.disabled(viewModel.isRecording)`. No changes to
   `CameraService`/`CameraViewModel` — `toggleCamera()` (`CameraViewModel.swift:67-73`) and its
   `!isRecording` guard already exist and already work correctly for Set Goal's chunked-recording
   `RecordingState.recording` state.
2. No new unit test needed beyond a snapshot/manual check — `toggleCamera()` itself already has
   coverage from P7/pre-P7; this task only adds a UI call site identical to an existing one.
   Manual check: covered by Group 7's end-to-end device pass (rotate camera before starting a Set
   Goal session, confirm preview flips and recording still works).
3. Run `scripts/verify.sh ios` — confirm green.

## Group 2 — iOS: Cancel/Discard from the Results Screen (surface: `ios`)

4. `SetGoalSessionViewModel.swift`: add `func discard()` — deletes `videoURL` (if set) and every
   URL in `chunkURLs` via `FileManager.default.removeItem(at:)` (best-effort, `try?`), matching
   the cleanup style already used elsewhere in this file and in
   `VideoSourceSelectionViewModel.dismissAssessmentResults()`. Does **not** call
   `context.insert(_:)` — no persistence side effect.
5. `SetGoalRecordingView.swift`'s `summarySheet` toolbar: add a second `ToolbarItem(placement:
   .cancellationAction)` with a "Discard" button calling `viewModel.discard()` then `onDone()` —
   same post-action navigation as the existing Save button.
6. New `SetGoalSessionViewModelTests.swift` case: `discard()` removes the concatenated video file
   and all chunk files from disk (assert via a test `FileManager`/temp-dir fixture, or by
   asserting `FileManager.default.fileExists(atPath:)` is false after calling it on real temp
   files created by the test), and does not touch `ModelContext` (no `insert` call — assert via a
   mock/spy `ModelContext` usage count if the existing test suite already has one, otherwise by
   confirming a subsequent `context.fetch` finds nothing new).
7. Run `scripts/verify.sh ios` — confirm green.

## Group 3 — iOS: Toggle-Visibility Investigation & Fix (surface: `ios`)

> Covers roadmap items "Lite mode hides the Assessment/Set Goal toggle" and "Toggle-visibility
> state bug" together — both are staleness bugs around `VideoSourceSelectionViewModel.selectedMode`
> gating `VideoSourceSelectionView.swift:35-43`'s workflow `Picker`, and are very likely the same
> root cause. Root-cause and fix the underlying state per the roadmap's explicit instruction — do
> not patch only the specific back-arrow repro in isolation.

8. **Diagnose first.** `selectedMode` (`VideoSourceSelectionViewModel.swift:37-40`) is a
   hand-written computed property (`UserDefaults`-backed custom `get`/`set`) on an `@Observable`
   class — every other piece of state on this class is a plain stored property. Confirm, with the
   Xcode Observation debugger or a temporary instrumented build, whether SwiftUI's dependency
   tracking actually invalidates `VideoSourceSelectionView`'s body when `selectedMode` changes via
   a path other than the `Picker`'s own binding (e.g., after a `NavigationStack` push/pop cycle
   where the view briefly leaves and re-enters the hierarchy). Record the confirmed root cause
   (or, if the computed-property theory doesn't hold up under testing, whatever the real cause
   turns out to be) in this file's Run Notes during `/phase`, before writing the fix.
9. **Fix**, informed by step 8's finding. If the computed-property theory is confirmed: convert
   `selectedMode` to a plain `@ObservationIgnored` stored property with an explicit
   `didSet { defaults.set(...) }` that also triggers observation manually (e.g. via a paired
   `access`/`withMutation` call, or simplest: keep a real stored `private var _selectedMode:
   SessionMode` that the macro *does* track, syncing it to/from `UserDefaults` only at `init` and
   inside the setter) — the concrete mechanism depends on step 8's finding, but the fix must result
   in every view reading `selectedMode` reliably re-rendering on every change, including after
   NavigationStack push/pop, not just on the `Picker`'s own binding write.
10. New `VideoSourceSelectionViewModelTests.swift` cases: setting `selectedMode` triggers observable
    change notification reliably (if testable via `withObservationTracking` or an equivalent
    mechanism already used elsewhere in the test suite — check for precedent before inventing a new
    pattern); `selectedWorkflow`'s visibility-gating condition (`selectedMode == .pro2D`) evaluates
    correctly immediately after `selectedMode` changes, covering both directions (Pro 2D → Lite and
    back).
11. Manual — real device: both roadmap repro scenarios pass — (a) Lite mode never shows the
    workflow toggle; (b) Lite → Record New → back arrow → Pro 2D shows the toggle immediately,
    without requiring an extra Record New/back-arrow cycle. Recorded in Group 7's manual pass, not
    a separate one.
12. Run `scripts/verify.sh ios` — confirm green.

## Group 4 — Backend: Chunk Response Gains Goal-Phase Frame + Firing Cue (surface: `backend`)

13. `backend/app/engine/rules.py`: add
    ```python
    RULES_BY_ID: dict[str, _Rule] = {rule.id: rule for rule in _RULES}
    ```
    alongside the existing `RULE_IDS` (line 58) — same computed-once-at-import pattern, gives
    `score_segment` a way to look up a goal rule's own `.phase` regardless of whether it fired.
14. `backend/app/models.py`:
    - Add `phase: ServePhase` and `cue: Cue | None = None` to `GoalResult` — `phase` is always
      populated (the `ServePhase` this goal's rule targets, e.g. `toss`, `trophy_pose`, `contact`;
      not always contact); `cue` is the full firing `Cue` on a miss (for the failing-joint
      highlight) and `None` on a pass (nothing to highlight).
    - Add
      ```python
      class GoalPhaseFrame(BaseModel):
          frame: Frame
          detections: list[Detection] = Field(default_factory=list)
      ```
      and `phase_frame: GoalPhaseFrame | None = None` on `GoalChunkResult` — defaulted, so nothing
      about the existing response shape changes for a segment where that phase wasn't detected
      (already possible today per `score_segment`/`detect_phases`'s graceful `None` handling).
15. `backend/app/engine/scoring.py`'s `score_segment`: where `goal_result` is currently built from
    `firing` (`passed=firing is None`, `spoken_cue=...`), also set `phase=RULES_BY_ID[goal_rule_id]
    .phase` and `cue=firing` — both values already exist at that point (`firing` is already
    computed; the rule lookup is the one new line from step 13). No new scoring logic.
16. `backend/app/routers/goal_session.py`'s per-segment loop (currently `scored =
    score_segment(...); results.append(GoalChunkResult(segment_index=i, goal_result=
    scored.goal_result))`): look up the frame for `scored.goal_result.phase` (not hardcoded
    `ServePhase.contact`) from `scored.phases` (`PhaseDetection` list) —
    `phase_detection = next((p for p in scored.phases if p.phase ==
    scored.goal_result.phase), None)`. If found, build `GoalPhaseFrame(frame=segments[i]
    [phase_detection.frame_index], detections=seg_detections[i][phase_detection.frame_index] if
    seg_detections[i] else [])` and pass as `phase_frame=` on the `GoalChunkResult`; otherwise
    `phase_frame=None` — mirrors the existing "frame still shows without a skeleton, rather than
    disappearing" tolerance already documented on the iOS `PhaseFrameOverlayView.frame` field.
17. `backend/tests/test_goal_session_endpoint.py`: extend the existing confirmed-segment case to
    assert `phase_frame` is present with the expected `frame.timestamp`/keypoints/detections
    matching the fixture's frame at the goal rule's own phase (use a fixture goal whose rule
    targets a non-contact phase, e.g. `trophy_pose`, to prove the phase-matching — not just
    contact); assert `goal_result.cue` is present and matches the firing rule on a miss, and is
    `None` on a pass with `goal_result.phase` still populated either way. Add a case where the
    fixture's frames never clear a detectable frame at the goal's phase → `phase_frame is None`,
    response otherwise unchanged (`goal_result` still present).
18. Run `scripts/verify.sh backend` — confirm green.

## Group 5 — iOS: Skeleton Overlay + Failing-Joint Highlight on Set Goal Results (surface: `ios`)

> Depends on Group 4's `phase_frame`/`cue`/`phase` fields.

19. New `MyServeCoach/MyServeCoach/App/Models/GoalPhaseFrame.swift`:
    ```swift
    struct GoalPhaseFrame: Decodable, Sendable {
        let frame: BackendFrame
        let detections: [BackendDetection]
    }
    ```
20. `GoalResult.swift`:
    - Extend `GoalResult` (the pass/fail struct) with `let phase: String` (raw backend phase
      string — matches the existing pattern of `Cue.phase`, decode as `String` rather than
      round-tripping through the iOS `ServePhase` enum unless one already exists for decoding;
      check `ServePhase.swift` for a `Decodable` case before introducing a second decode path) and
      `let cue: Cue?`, `CodingKeys` adding `case cue` (already-matching key) — `Cue` is the type
      already defined at `CoachingService.swift:12`, decodes as-is with no changes.
    - Extend `GoalChunkResult` with `let phaseFrame: GoalPhaseFrame?`, `CodingKeys` adding
      `case phaseFrame = "phase_frame"`.
21. `GoalAttemptDisplay.swift`: add `let phaseFrame: GoalPhaseFrame?`, `let cue: Cue?`, and
    `var stillImage: UIImage?` — the latter is `var`, not `let`: populated after extraction in
    `finalizeVideo()`, not at construction time (the video doesn't exist yet when a chunk's result
    first arrives).
22. `SetGoalSessionViewModel.handleChunk`: pass `phaseFrame: result.phaseFrame, cue:
    result.goalResult.cue, stillImage: nil` when building each `GoalAttemptDisplay`.
23. `SetGoalSessionViewModel.finalizeVideo()`: after `videoURL = try? await
    concatenator.concatenate(...)`, if `videoURL` is non-nil, batch-extract stills for every
    attempt with a non-nil `phaseFrame` in one call to a new injected `any
    PhaseFrameImageProviding` (default `PhaseFrameImageExtractor()`), keyed by each attempt's
    `phaseFrame!.frame.timestamp`. Unlike `PhaseFrameImageExtractor`'s existing exact (±0s) seek
    tolerance (used by Assessment), Set Goal's extraction needs a nonzero tolerance — see
    `requirements.md`'s "Known timing-precision limitation" — so `PhaseFrameImageProviding` gains a
    `tolerance: CMTime` parameter (default `.zero`, preserving Assessment's exact-seek behavior
    unchanged) that Set Goal's call site sets to `CMTime(seconds: 0.15, preferredTimescale: 600)`.
    Assign each returned `UIImage`/JPEG data back onto the matching attempt's `stillImage` (decode
    the JPEG data back to `UIImage`, or change the extractor's return type — keep whichever is
    less invasive to `PhaseFrameImageExtractorTests.swift`'s existing assertions).
24. New `MyServeCoach/MyServeCoach/App/Models/SwiftData/GoalPhaseFrameRecord.swift`, mirroring
    `PhaseFrameRecord.swift:10-35` minus `phaseKey` (Set Goal only ever has one phase per session —
    the goal's own — so it's derivable from the parent `GoalSession.goalRuleId` rather than worth
    a second stored field) and `result` (relationship named for its Set Goal parent instead), plus
    a new `cueJSON` field for the failing-joint highlight data:
    ```swift
    @Model
    final class GoalPhaseFrameRecord {
        var id: UUID = UUID()
        var frameTimestamp: Double = 0
        var frameImageData: Data = Data()
        var keypointsJSON: Data = Data()  // JSON-encoded BackendFrame
        var detectionsJSON: Data = Data()  // JSON-encoded [BackendDetection]
        var cueJSON: Data? = nil  // JSON-encoded Cue, nil when the serve passed (nothing to highlight)
        var attempt: GoalAttemptRecord?

        init(frameTimestamp: Double, frameImageData: Data, keypointsJSON: Data, detectionsJSON: Data, cueJSON: Data?) { ... }
    }
    ```
25. `GoalAttemptRecord.swift`: add `@Relationship(deleteRule: .cascade) var phaseFrame:
    GoalPhaseFrameRecord?`.
26. `MyServeCoachApp.swift`: `ModelContainer` gains `GoalPhaseFrameRecord.self` in its schema list
    alongside `GoalSession.self`/`GoalAttemptRecord.self` (whichever of those is already explicit
    vs. relationship-reachable — check current container init before assuming a new top-level
    entry is needed).
27. `SetGoalSessionViewModel.persist(to:)`: for each attempt with non-nil `phaseFrame` **and**
    non-nil `stillImage`, JSON-encode `phaseFrame!.frame` → `keypointsJSON`, `phaseFrame!.
    detections` → `detectionsJSON`, and (when `cue` is non-nil) `cue` → `cueJSON` (`nil` when the
    attempt passed) — reuse `JSONEncoder`, matching how Assessment's `AssessmentResultViewModel`/
    persistence path already encodes these (check that call site for the exact encoder config
    before duplicating it ad hoc). Build a `GoalPhaseFrameRecord` and set it on the newly-built
    `GoalAttemptRecord.phaseFrame`. An attempt with no phase frame (rule never detected one, or
    extraction failed) persists with `phaseFrame == nil` — the row still saves and displays, just
    without the overlay, matching `PhaseFrameOverlayView`'s existing graceful-degradation contract.
28. `GoalAttemptRowView.swift`: extend to accept optional overlay inputs —
    ```swift
    struct GoalAttemptRowView: View {
        let segmentIndex: Int
        let passed: Bool
        let spokenCue: String
        var stillImage: UIImage? = nil
        var poseFrame: BackendFrame? = nil
        var highlightedCue: Cue? = nil
    }
    ```
    When `stillImage` is non-nil, render `PhaseFrameOverlayView(image: stillImage!, frame:
    poseFrame, highlightedCue: highlightedCue)` above the existing pass/fail `HStack` — on a
    failed serve this draws the failing-joint highlight using the same geometry Assessment already
    built (`PhaseFrameOverlayView`/`CueOverlayGeometry` unchanged, reused as-is); on a passed serve
    `highlightedCue` is `nil` (skeleton only, no highlight — there's nothing to highlight). When
    `stillImage` is nil, body is unchanged from today.
29. `SetGoalRecordingView.swift`'s `summarySheet`: pass `stillImage: attempt.stillImage,
    poseFrame: attempt.phaseFrame?.frame, highlightedCue: attempt.cue` to each
    `GoalAttemptRowView(...)` call.
30. `GoalSessionHistoryDetailView.swift`: decode each `attempt.phaseFrame`'s `keypointsJSON` into
    `BackendFrame?` (nil on decode failure, matching `PhaseFrameOverlayView.frame`'s own
    documented tolerance), `frameImageData` into `UIImage?`, and `cueJSON` (if non-nil) into
    `Cue?`, pass to `GoalAttemptRowView` alongside the existing pass/fail fields. Update the file's
    doc comment (currently "no skeleton overlay: Set Goal never had phase-frame imagery to show")
    — no longer accurate.
31. New/extended test cases:
    - `PhaseFrameImageExtractorTests.swift`: a `tolerance` parameter of `0.15s` still returns the
      nearest frame within tolerance when the exact requested time has no keyframe at that instant
      (whatever fixture/mechanism the existing exact-seek tests already use, extended for the
      nonzero-tolerance path); default `.zero` behavior is unchanged (regression guard for
      Assessment's existing call site).
    - `SetGoalSessionViewModelTests.swift`: `finalizeVideo()` populates `stillImage` on every
      attempt with a `phaseFrame`, using a mock `PhaseFrameImageProviding`; `persist(to:)` builds a
      `GoalPhaseFrameRecord` attached to the right `GoalAttemptRecord` when `stillImage`/
      `phaseFrame` are present (including `cueJSON` populated on a miss and nil on a pass), and
      leaves `phaseFrame` nil when `stillImage`/backend `phase_frame` is absent.
    - New `GoalSessionHistoryDetailViewTests.swift` (snapshot or ViewInspector, matching whatever
      pattern `AssessmentHistoryDetailView`'s equivalent test already uses): a session with a
      persisted `GoalPhaseFrameRecord` renders the overlay — with the failing-joint highlight
      visible on a missed serve and skeleton-only on a passed serve; a session without a
      `GoalPhaseFrameRecord` (pre-P7a saved session, or an attempt with no detected phase frame)
      renders exactly as before — degrades gracefully, doesn't crash on `nil`.
32. Run `scripts/verify.sh ios` — confirm green.

## Group 6 — Backend: More Specific Spoken Cues on Goal Miss (surface: `backend`)

33. New `backend/app/engine/goal_cues.py` (or a section of `scoring.py` if the existing file
    structure makes a new module unnecessary — check current file sizes before splitting):
    ```python
    # rule_id -> (low_phrase, high_phrase), used only when a rule's comparison direction can be
    # determined for the failing value. Not every rule maps cleanly to "too low"/"too high" — the
    # phrase is worded per rule, not templated generically.
    _DIRECTION_PHRASES: dict[str, tuple[str, str]] = {
        "trophy_hitting_elbow_shoulder_line": ("elbow too low", "elbow too high"),
        # ... one entry per rule where a directional phrase is meaningfully more actionable than
        # rule.message alone; rules without an entry fall back to rule.message unchanged.
    }

    def directional_spoken_cue(rule: _Rule, value: float) -> str:
        """Returns a more specific spoken-cue phrase for a failed rule when one is defined,
        else rule.message unchanged. `value` is the metric value that failed `rule`'s
        comparison — direction is derived from which bound it violated (gte: below threshold
        means "low"; lte: above threshold means "high"; range: below min means "low", above max
        means "high"), reusing the calibrated threshold rather than a new one.
        """
    ```
34. `backend/app/engine/scoring.py`'s `score_segment`: when constructing `goal_result` on a miss
    (`firing is not None`), call `directional_spoken_cue` (looking up the firing `Cue`'s
    corresponding `_Rule` by `rule_id`, and its `measured_value`) instead of using `firing.message`
    directly for `GoalResult.spoken_cue`. **`Cue.message` itself is unchanged** — this only alters
    what `GoalResult.spoken_cue` (Set Goal's audible-cue path) resolves to; Assessment's cue list
    (`AnalyzeResponse.cues`) is unaffected.
35. New `backend/tests/test_goal_cues.py` (or extend `test_scoring.py`): `directional_spoken_cue`
    returns the low-phrase when a `gte` rule's value is below threshold, the high-phrase when an
    `lte` rule's value is above threshold, the correct phrase for both `range` failure directions,
    and falls back to `rule.message` for a rule with no `_DIRECTION_PHRASES` entry.
36. `backend/tests/test_scoring.py`/`test_analyze.py`: extend an existing goal-miss case to assert
    `goal_result.spoken_cue` now returns the directional phrase (for a rule that has one defined)
    instead of the raw rule message — this is a deliberate behavior change from P7, so the
    existing assertion needs updating, not just a new case added alongside it.
37. Run `scripts/verify.sh backend` — confirm green.

## Group 7 — Cross-Cutting Verification (surface: `backend`, `ios`)

38. `git diff --name-only develop...HEAD` — confirm `PhaseReviewView.swift`, the Lite pipeline/
    segmentation service files, and `ContentView.swift` do not appear.
39. Run `scripts/verify.sh backend` and `scripts/verify.sh ios` — both green as the final
    automated gate.
40. Manual real-device check: verify all six items together on a physical device —
    - Front camera toggle works in `SetGoalRecordingView` before/between sessions (Group 1).
    - Discard on the summary sheet removes temp files and returns to mode selection without
      saving a `GoalSession` (Group 2) — confirm via History showing no new entry.
    - Lite never shows the workflow toggle; Lite → Record New → back arrow → Pro 2D shows it
      immediately (Group 3).
    - A saved Set Goal session's history detail view shows a still frame with skeleton overlay
      at the goal's own phase (not always contact — verify with a goal whose rule targets a
      different phase), including the failing-joint highlight on a missed serve and skeleton-only
      on a passed serve (Group 4/5).
    - Spoken cues on a goal miss use the more specific directional phrasing for rules with one
      defined (Group 6) — listen during a live session.
41. **Mandatory — Check C re-run (this phase's core acceptance gate):** on the same physical
    device / backend config as P7's original check (`fused/mps`, Mac M3 Max,
    `DETECTION_MODEL_DEVICE=mps`), record a fresh multi-serve Set Goal session and measure
    wall-clock contact→spoken-cue latency the same way P7's `validation.md` did (stopwatch or
    timestamped console logs at contact-time and `speak()` call time). Bar: **median ≤5s, max
    ≤8s**, matching P7's baseline of ~4s. This directly answers the question that motivated
    speccing the skeleton overlay first: does adding it regress live latency. Record the measured
    numbers in `validation.md` Run Notes — a "should be fine because it's off the critical path"
    design assertion does not satisfy this row; only a measured re-run does.
42. Update `specs/roadmap.md`'s P7a entry status marker only as part of `/merge` (not this phase).
