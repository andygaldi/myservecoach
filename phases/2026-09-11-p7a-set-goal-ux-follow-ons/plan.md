# Phase P7a — Plan

> **Isolation note:** Groups 3a/3b touch only `VideoSourceSelectionView`/`ViewModel` (the Pro-2D/
> Lite mode-selector shell). No group touches `PhaseReviewView`, the Lite pipeline/segmentation
> services, or `ContentView`.

> **Dependency note:** Group 5 (iOS skeleton overlay) consumes the `contact_frame` field Group 4
> (backend) adds to `GoalChunkResult` — run Group 4 before Group 5. Groups 1, 2, 3, 6 are each
> independent of every other group and of each other.

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

## Group 4 — Backend: Chunk Response Gains Contact-Frame Data (surface: `backend`)

13. `backend/app/models.py`: add
    ```python
    class GoalPhaseFrame(BaseModel):
        frame: Frame
        detections: list[Detection] = Field(default_factory=list)
    ```
    Add `contact_frame: GoalPhaseFrame | None = None` to `GoalChunkResult` — defaulted, so nothing
    about the existing response shape changes for a segment where the contact phase wasn't
    detected (already possible today per `score_segment`/`detect_phases`'s graceful `None`
    handling).
14. `backend/app/routers/goal_session.py`'s per-segment loop (currently `scored =
    score_segment(...); results.append(GoalChunkResult(segment_index=i, goal_result=
    scored.goal_result))`): also look up the contact phase from `scored.phases` (`PhaseDetection`
    list) — `contact_phase = next((p for p in scored.phases if p.phase ==
    ServePhase.contact), None)`. If found, build `GoalPhaseFrame(frame=segments[i][contact_phase.
    frame_index], detections=seg_detections[i][contact_phase.frame_index] if seg_detections[i]
    else [])` and pass as `contact_frame=` on the `GoalChunkResult`; otherwise `contact_frame=None`
    — mirrors the existing "frame still shows without a skeleton, rather than disappearing"
    tolerance already documented on the iOS `PhaseFrameOverlayView.frame` field.
15. `backend/tests/test_goal_session_endpoint.py`: extend the existing confirmed-segment case to
    assert `contact_frame` is present with the expected `frame.timestamp`/keypoints/detections
    matching the fixture's contact-phase frame; add a case where the fixture's frames never clear
    a detectable contact phase → `contact_frame is None`, response otherwise unchanged (`goal_
    result` still present).
16. Run `scripts/verify.sh backend` — confirm green.

## Group 5 — iOS: Skeleton Overlay on Set Goal Results (surface: `ios`)

> Depends on Group 4's `contact_frame` field.

17. New `MyServeCoach/MyServeCoach/App/Models/GoalPhaseFrame.swift`:
    ```swift
    struct GoalPhaseFrame: Decodable, Sendable {
        let frame: BackendFrame
        let detections: [BackendDetection]
    }
    ```
18. `GoalResult.swift`: extend `GoalChunkResult` with `let contactFrame: GoalPhaseFrame?`,
    `CodingKeys` adding `case contactFrame = "contact_frame"`.
19. `GoalAttemptDisplay.swift`: add `let contactFrame: GoalPhaseFrame?` and
    `var stillImage: UIImage?` — the latter is `var`, not `let`: populated after extraction in
    `finalizeVideo()`, not at construction time (the video doesn't exist yet when a chunk's result
    first arrives).
20. `SetGoalSessionViewModel.handleChunk`: pass `contactFrame: result.contactFrame,
    stillImage: nil` when building each `GoalAttemptDisplay`.
21. `SetGoalSessionViewModel.finalizeVideo()`: after `videoURL = try? await
    concatenator.concatenate(...)`, if `videoURL` is non-nil, batch-extract stills for every
    attempt with a non-nil `contactFrame` in one call to a new injected `any
    PhaseFrameImageProviding` (default `PhaseFrameImageExtractor()`), keyed by each attempt's
    `contactFrame!.frame.timestamp`. Unlike `PhaseFrameImageExtractor`'s existing exact (±0s) seek
    tolerance (used by Assessment), Set Goal's extraction needs a nonzero tolerance — see
    `requirements.md`'s "Known timing-precision limitation" — so `PhaseFrameImageProviding` gains a
    `tolerance: CMTime` parameter (default `.zero`, preserving Assessment's exact-seek behavior
    unchanged) that Set Goal's call site sets to `CMTime(seconds: 0.15, preferredTimescale: 600)`.
    Assign each returned `UIImage`/JPEG data back onto the matching attempt's `stillImage` (decode
    the JPEG data back to `UIImage`, or change the extractor's return type — keep whichever is
    less invasive to `PhaseFrameImageExtractorTests.swift`'s existing assertions).
22. New `MyServeCoach/MyServeCoach/App/Models/SwiftData/GoalPhaseFrameRecord.swift`, mirroring
    `PhaseFrameRecord.swift:10-35` minus `phaseKey` (always "contact" for Set Goal, not worth a
    stored field) and `result` (relationship named for its Set Goal parent instead):
    ```swift
    @Model
    final class GoalPhaseFrameRecord {
        var id: UUID = UUID()
        var frameTimestamp: Double = 0
        var frameImageData: Data = Data()
        var keypointsJSON: Data = Data()  // JSON-encoded BackendFrame
        var detectionsJSON: Data = Data()  // JSON-encoded [BackendDetection]
        var attempt: GoalAttemptRecord?

        init(frameTimestamp: Double, frameImageData: Data, keypointsJSON: Data, detectionsJSON: Data) { ... }
    }
    ```
23. `GoalAttemptRecord.swift`: add `@Relationship(deleteRule: .cascade) var phaseFrame:
    GoalPhaseFrameRecord?`.
24. `MyServeCoachApp.swift`: `ModelContainer` gains `GoalPhaseFrameRecord.self` in its schema list
    alongside `GoalSession.self`/`GoalAttemptRecord.self` (whichever of those is already explicit
    vs. relationship-reachable — check current container init before assuming a new top-level
    entry is needed).
25. `SetGoalSessionViewModel.persist(to:)`: for each attempt with non-nil `contactFrame` **and**
    non-nil `stillImage`, JSON-encode `contactFrame!.frame` → `keypointsJSON` and
    `contactFrame!.detections` → `detectionsJSON` (reuse `JSONEncoder`, matching how Assessment's
    `AssessmentResultViewModel`/persistence path already encodes these — check that call site for
    the exact encoder config before duplicating it ad hoc), build a `GoalPhaseFrameRecord`, and set
    it on the newly-built `GoalAttemptRecord.phaseFrame`. An attempt with no contact frame (rule
    never detected one, or extraction failed) persists with `phaseFrame == nil` — the row still
    saves and displays, just without the overlay, matching `PhaseFrameOverlayView`'s existing
    graceful-degradation contract.
26. `GoalAttemptRowView.swift`: extend to accept optional overlay inputs —
    ```swift
    struct GoalAttemptRowView: View {
        let segmentIndex: Int
        let passed: Bool
        let spokenCue: String
        var stillImage: UIImage? = nil
        var poseFrame: BackendFrame? = nil
    }
    ```
    When `stillImage` is non-nil, render `PhaseFrameOverlayView(image: stillImage!, frame:
    poseFrame, highlightedCue: nil)` above the existing pass/fail `HStack` (skeleton only, no
    highlight — see requirements.md's Key Decision); when nil, body is unchanged from today.
27. `SetGoalRecordingView.swift`'s `summarySheet`: pass `stillImage: attempt.stillImage,
    poseFrame: attempt.contactFrame?.frame` to each `GoalAttemptRowView(...)` call.
28. `GoalSessionHistoryDetailView.swift`: decode each `attempt.phaseFrame`'s `keypointsJSON` into
    `BackendFrame?` (nil on decode failure, matching `PhaseFrameOverlayView.frame`'s own
    documented tolerance) and `frameImageData` into `UIImage?`, pass to `GoalAttemptRowView`
    alongside the existing pass/fail fields. Update the file's doc comment (currently "no skeleton
    overlay: Set Goal never had phase-frame imagery to show") — no longer accurate.
29. New/extended test cases:
    - `PhaseFrameImageExtractorTests.swift`: a `tolerance` parameter of `0.15s` still returns the
      nearest frame within tolerance when the exact requested time has no keyframe at that instant
      (whatever fixture/mechanism the existing exact-seek tests already use, extended for the
      nonzero-tolerance path); default `.zero` behavior is unchanged (regression guard for
      Assessment's existing call site).
    - `SetGoalSessionViewModelTests.swift`: `finalizeVideo()` populates `stillImage` on every
      attempt with a `contactFrame`, using a mock `PhaseFrameImageProviding`; `persist(to:)` builds
      a `GoalPhaseFrameRecord` attached to the right `GoalAttemptRecord` when `stillImage`/
      `contactFrame` are present, and leaves `phaseFrame` nil when either is absent.
    - New `GoalSessionHistoryDetailViewTests.swift` (snapshot or ViewInspector, matching whatever
      pattern `AssessmentHistoryDetailView`'s equivalent test already uses): a session with a
      persisted `GoalPhaseFrameRecord` renders the overlay; a session without one (pre-P7a saved
      session, or an attempt with no detected contact phase) renders exactly as before — degrades
      gracefully, doesn't crash on `nil`.
30. Run `scripts/verify.sh ios` — confirm green.

## Group 6 — Backend: More Specific Spoken Cues on Goal Miss (surface: `backend`)

31. New `backend/app/engine/goal_cues.py` (or a section of `scoring.py` if the existing file
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
32. `backend/app/engine/scoring.py`'s `score_segment`: when constructing `goal_result` on a miss
    (`firing is not None`), call `directional_spoken_cue` (looking up the firing `Cue`'s
    corresponding `_Rule` by `rule_id`, and its `measured_value`) instead of using `firing.message`
    directly for `GoalResult.spoken_cue`. **`Cue.message` itself is unchanged** — this only alters
    what `GoalResult.spoken_cue` (Set Goal's audible-cue path) resolves to; Assessment's cue list
    (`AnalyzeResponse.cues`) is unaffected.
33. New `backend/tests/test_goal_cues.py` (or extend `test_scoring.py`): `directional_spoken_cue`
    returns the low-phrase when a `gte` rule's value is below threshold, the high-phrase when an
    `lte` rule's value is above threshold, the correct phrase for both `range` failure directions,
    and falls back to `rule.message` for a rule with no `_DIRECTION_PHRASES` entry.
34. `backend/tests/test_scoring.py`/`test_analyze.py`: extend an existing goal-miss case to assert
    `goal_result.spoken_cue` now returns the directional phrase (for a rule that has one defined)
    instead of the raw rule message — this is a deliberate behavior change from P7, so the
    existing assertion needs updating, not just a new case added alongside it.
35. Run `scripts/verify.sh backend` — confirm green.

## Group 7 — Cross-Cutting Verification (surface: `backend`, `ios`)

36. `git diff --name-only develop...HEAD` — confirm `PhaseReviewView.swift`, the Lite pipeline/
    segmentation service files, and `ContentView.swift` do not appear.
37. Run `scripts/verify.sh backend` and `scripts/verify.sh ios` — both green as the final
    automated gate.
38. Manual real-device check: verify all six items together on a physical device —
    - Front camera toggle works in `SetGoalRecordingView` before/between sessions (Group 1).
    - Discard on the summary sheet removes temp files and returns to mode selection without
      saving a `GoalSession` (Group 2) — confirm via History showing no new entry.
    - Lite never shows the workflow toggle; Lite → Record New → back arrow → Pro 2D shows it
      immediately (Group 3).
    - A saved Set Goal session's history detail view shows a still frame with skeleton overlay
      per serve with a detected contact phase (Group 4/5).
    - Spoken cues on a goal miss use the more specific directional phrasing for rules with one
      defined (Group 6) — listen during a live session.
39. **Mandatory — Check C re-run (this phase's core acceptance gate):** on the same physical
    device / backend config as P7's original check (`fused/mps`, Mac M3 Max,
    `DETECTION_MODEL_DEVICE=mps`), record a fresh multi-serve Set Goal session and measure
    wall-clock contact→spoken-cue latency the same way P7's `validation.md` did (stopwatch or
    timestamped console logs at contact-time and `speak()` call time). Bar: **median ≤5s, max
    ≤8s**, matching P7's baseline of ~4s. This directly answers the question that motivated
    speccing the skeleton overlay first: does adding it regress live latency. Record the measured
    numbers in `validation.md` Run Notes — a "should be fine because it's off the critical path"
    design assertion does not satisfy this row; only a measured re-run does.
40. Update `specs/roadmap.md`'s P7a entry status marker only as part of `/merge` (not this phase).
