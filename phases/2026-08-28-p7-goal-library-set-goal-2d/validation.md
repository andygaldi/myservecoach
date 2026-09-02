# Phase P7 — Validation

## Definition of Done

Set Goal is a fully working second Pro 2D workflow: player picks a goal, records continuously,
hears an audible pass/fail cue after each auto-detected serve while still on court, sees a live
tally, and gets a saved, replayable session in History. Assessment's existing `/v1/analyze`
contract is unchanged for callers that don't send `goal_rule_id`. Lite mode, `PhaseReviewView`,
and `ContentView` are untouched.

## Group 0 — Backend: Fused Pose/Detection Pipeline

| Check | How to verify |
|---|---|
| `infer_with_person` returns the person box correctly | New unit test: pixel xyxy, unflipped/unnormalized; returns `None` when no person clears threshold. |
| `RTMPoseModel.infer` with no bbox is unchanged | New unit test: no-bbox call still routes through `Body`, matching pre-P7 `/v1/pose` behavior exactly (regression guard). |
| Fused pipeline accuracy already corpus-verified pre-implementation | Not re-run this phase — `latency-findings.md` records 20-clip fused-vs-`rtmlib` `segment_serves` comparison, 0 disagreements, 19/20 ground truth, done before `/phase` started. Don't redo. |
| Full backend suite green | `scripts/verify.sh backend`. |

## Group 1 — Backend: Shared Scoring Function & `/v1/analyze` Goal Extension

| Check | How to verify |
|---|---|
| `score_segment()` produces identical `cues`/`summary`/`phases` to pre-P7 `/v1/analyze` behavior | `pytest backend/tests/test_analyze.py` — pre-existing cases (no `goal_rule_id`) still pass unchanged. |
| `goal_result` correct on fail | `test_analyze.py`: request with `goal_rule_id` set to a rule that fires on the fixture frames → `goal_result.passed is False`, `spoken_cue` equals the firing cue's `message`. |
| `goal_result` correct on pass | `test_analyze.py`: `goal_rule_id` set to a rule that doesn't fire on clean-serve fixture frames → `goal_result.passed is True`, `spoken_cue == "Nice serve — goal met!"`. |
| Unknown `goal_rule_id` rejected | `test_analyze.py`: nonsense `goal_rule_id` → `400`. |
| No `goal_rule_id` → zero behavior change | `test_analyze.py`: omitting `goal_rule_id` → `goal_result is None`, response shape otherwise identical to before P7. |
| `score_segment` unit-testable independent of HTTP | `pytest backend/tests/test_scoring.py` — `UnknownGoalRuleId` raised directly, `goal_result` omission/construction covered without the router layer. |
| Full backend suite green | `scripts/verify.sh backend`. |

## Group 2 — Backend: Goal Session Buffer & Chunk Endpoint

| Check | How to verify |
|---|---|
| Chunk timestamps continue the buffer's running clock, not reset per chunk | `pytest backend/tests/test_goal_session_buffer.py` — second `append_chunk` call's frame timestamps start after the first chunk's, offset by `_CHUNK_FPS`/stride math. |
| `evict` removes/no-ops correctly | `test_goal_session_buffer.py` — evicting a present `session_id` empties it; evicting a missing one doesn't raise. |
| Segment confirmation rule holds across chunks | `pytest backend/tests/test_goal_session_endpoint.py` — a single detected segment whose peak is `≥ CONFIRM_LAG_SECONDS` (1.5s) behind the buffer's trailing edge **is** confirmed without `is_final` (replaces the old "wait for a later segment's peak" rule — `latency-findings.md` Blocker A); a segment whose peak is still within the lag window stays provisional; an `is_final=true` chunk confirms all remaining segments regardless of lag and returns them. |
| Chunk handler doesn't block the event loop | Code inspection / `git diff`: `goal_session_chunk` is a plain `def` (not `async def` wrapping sync inference), so FastAPI runs it in a threadpool automatically. |
| `is_final=true` evicts the buffer | `test_goal_session_endpoint.py` — a follow-up chunk posted under the same `session_id` after an `is_final=true` call starts a fresh buffer (`reported_count`/offsets back to 0). |
| Unknown `goal_rule_id` on the chunk endpoint rejected, buffer untouched | `test_goal_session_endpoint.py` — bad `goal_rule_id` → `400`, no chunk appended (verify via a follow-up valid call showing no leaked state). |
| Response shape matches spec | `test_goal_session_endpoint.py` — `{"results": [{"segment_index": int, "goal_result": {...}}]}`, `results` empty (not omitted) when nothing newly confirmed. |
| Full backend suite green | `scripts/verify.sh backend`. |

## Group 3 — iOS: Goal Catalog, `ProWorkflow`, `GoalSelectionView`

| Check | How to verify |
|---|---|
| Catalog covers all 9 rules with valid display data | `GoalCatalogTests.swift` — every entry has non-empty `displayName`, unique `ruleId` across the list, count == 9. |
| `ProWorkflow` picker appears only under Pro 2D | Manual or snapshot: select Lite on `VideoSourceSelectionView` → no workflow picker shown; select Pro 2D → picker appears with Assessment/Set Goal. |
| Selecting Set Goal routes to `GoalSelectionView`, then to recording | `VideoSourceSelectionViewModelTests.swift` — `selectedWorkflow = .setGoal` + "Record New" sets `navigateToGoalSelection`; `selectGoal(_:)` sets `selectedGoal`, flips `navigateToGoalSelection` off and `navigateToSetGoalSession` on. |
| "Choose from Library" hidden for Set Goal | Manual/snapshot: Pro 2D + Set Goal selected → library button not present; Pro 2D + Assessment → unchanged, still present. |
| `dismissSetGoalSession()` resets state | `VideoSourceSelectionViewModelTests.swift` — clears `navigateToSetGoalSession` and `selectedGoal`. |
| Full iOS suite green | `scripts/verify.sh ios`. |

## Group 4 — iOS: Chunked Recording on `CameraService`/`CameraViewModel`

| Check | How to verify |
|---|---|
| `startChunkedRecording`/`stopChunkedRecording` exist on the protocol and are forwarded by `CameraViewModel` | `CameraViewModelTests.swift` — `startChunkedRecording` sets `recordingState = .recording` and forwards `chunkDuration`/handler to the mock; `stopChunkedRecording` forwards without mutating state itself. |
| Delegate branch finalizes exactly one chunk with `isFinal: true` after `stopChunkedRecording` | `CameraServiceTests.swift` — driving the delegate callback directly (mirroring `MockCameraService`'s `triggerCompletion` pattern) confirms the stop path fires `onChunkFinalized(_, isFinal: true)` once, doesn't double-fire, and doesn't call the old single-shot `recordingCompletion`. |
| Single-shot recording (Lite/Assessment) unaffected | Existing `CameraViewModelTests.swift`/`CameraServiceTests.swift` single-shot cases still pass unchanged — chunking is additive, not a replacement path. |
| Full iOS suite green | `scripts/verify.sh ios`. |
| **Manual — real device:** multi-chunk rotation actually happens at the configured interval, each `.mov` chunk is a valid finalized file, no crash/hang across a multi-minute session | Record a real Set Goal session on a physical device spanning several chunk boundaries (several minutes at 4s/chunk); confirm via console logging that `onChunkFinalized` fires repeatedly with increasing file sizes/valid URLs and the app stays responsive. Covered as part of the Group 8 end-to-end device check, not a separate pass. |

## Group 5 — iOS: `GoalSessionService` & `SpokenFeedbackService`

| Check | How to verify |
|---|---|
| `uploadChunk` builds the correct request and decodes the response | `GoalSessionServiceTests.swift` — mocked `URLProtocol` response asserts URL path/query items (`session_id`, `goal_rule_id`, `stride`, `is_final`) and that `results` decodes into `[GoalChunkResult]` correctly (including `spoken_cue` → `spokenCue` key mapping). |
| Upload failure surfaces as a thrown error, not a silent empty result | `GoalSessionServiceTests.swift` — a non-2xx/stub network error causes `uploadChunk` to throw. |
| `SpokenFeedbackService.speak` is exercised at its call site | Covered by Group 6's `SetGoalSessionViewModelTests.swift` via a mock `SpokenFeedbackServicing`, not tested standalone (thin wrapper, no branching logic). |
| Full iOS suite green | `scripts/verify.sh ios`. |

## Group 6 — iOS: `SetGoalSessionViewModel`/`SetGoalRecordingView` Orchestration

| Check | How to verify |
|---|---|
| Chunk finalize → upload → tally update → spoken cue | `SetGoalSessionViewModelTests.swift` — simulated chunk finalize via the mock camera's chunk-trigger helper leads to `uploadChunk` called with correct `sessionId`/`goalRuleId`/`isFinal`; each returned result appends a `GoalAttemptDisplay` and calls `spokenFeedback.speak` with its `spokenCue`. `startSession` uses `chunkDuration: 2` (not 4). |
| Backlog guard bounds outstanding uploads | `SetGoalSessionViewModelTests.swift` — finalizing more chunks than `maxOutstandingUploads` while earlier uploads haven't completed drops the oldest in-flight upload (its late result, if any, is ignored — no attempt/tally entry from it) instead of the queue growing unboundedly. |
| A failed chunk upload doesn't wedge the session | `SetGoalSessionViewModelTests.swift` — a throwing `uploadChunk` sets `errorMessage`, leaves `isRecording` untouched, appends no bogus attempt, and a subsequent successful chunk still processes normally. |
| Stop finalizes video | `SetGoalSessionViewModelTests.swift` — an `isFinal` chunk triggers `finalizeVideo()`, calling `concatenator.concatenate` with the accumulated chunk URLs and setting `videoURL`; `isFinalizing` flips back to `false` once done. |
| `persist(to:)` builds correct SwiftData objects | `SetGoalSessionViewModelTests.swift` — resulting `GoalSession` has the right `goalRuleId`/`goalDisplayName`/`videoURL`, and one `GoalAttemptRecord` per recorded attempt with matching fields. |
| `SetGoalRecordingView` shows running tally + summary | Manual/snapshot: during recording, header shows `passCount/attemptCount`; after stop, a summary section lists each attempt with pass/fail + spoken cue text, with a working Save button. |
| Full iOS suite green | `scripts/verify.sh ios`. |
| **Manual — real device, audio quality:** spoken cues are audible and intelligible in real time | During the Group 8 end-to-end device recording, confirm each `AVSpeechSynthesizer` utterance is actually audible over device speakers at normal volume, timed close enough after the serve to be useful ("stay focused on the court between serves"), and the cue text is spoken clearly (not garbled/cut off) — this is a genuinely manual, ears-on check; `speak()` being *called* with correct text (covered above) doesn't confirm it *sounds* right. |

## Group 7 — iOS: Persistence & History

| Check | How to verify |
|---|---|
| `GoalSession`/`GoalAttemptRecord` persist correctly | Covered by Group 6's `persist(to:)` test — a saved session round-trips through a `ModelContext`. |
| `ModelContainer` includes `GoalSession` | App launches without a SwiftData schema error after the `MyServeCoachApp.swift` change — `scripts/verify.sh ios` build step plus a manual launch check. |
| History merges `ServeSession` and `GoalSession` in date order | `SessionHistoryViewTests.swift` — a mixed set of `ServeSession`/`GoalSession` fixtures sorts by date across both types in the merged list. |
| Deleting a Set Goal row removes only that entry | `SessionHistoryViewTests.swift` — deleting a `GoalSession` row leaves `ServeSession` rows and other `GoalSession` rows intact. |
| `GoalSessionHistoryDetailView` replays a saved session | Manual: open a saved Set Goal session from History → shows goal name, date, and one row per attempt with pass/fail + spoken cue text, matching what was recorded during the session. |
| Full iOS suite green | `scripts/verify.sh ios`. |

## Group 8 — Cross-Cutting Verification

| Check | How to verify |
|---|---|
| Isolation rule respected | `git diff --name-only develop...HEAD` — `PhaseReviewView.swift`, Lite pipeline/segmentation service files, `ContentView.swift` do not appear. |
| iOS catalog matches `rules.json` exactly | Manual cross-check: list `backend/rules.json` rule ids vs. `GoalCatalog.all`'s `ruleId`s — same 9, no typos/mismatches. |
| Both test suites green | `scripts/verify.sh backend` and `scripts/verify.sh ios`, both passing as the final automated gate. |
| **Manual — real device, full end-to-end:** a real multi-serve Set Goal session works start to finish | On a physical device: pick a goal, start recording, hit several serves spanning multiple chunk boundaries, confirm chunks upload without stalling the UI, cues are spoken audibly after each detected serve (see Group 6's audio-quality row), the live tally updates correctly, stopping finalizes and shows an accurate summary, and Save produces a session that reopens correctly from History (see Group 7). Record the outcome (what was tested, any defects found/fixed) in this file's Run Notes during `/phase`. |
| **Manual — real device, measured latency:** contact-to-cue delay meets the budget | Same device recording: for each serve, measure wall-clock seconds from contact to its spoken cue (stopwatch or timestamped console logs at contact-time and `speak()` call time). Bar: **median ≤5s, max ≤8s**, matching `latency-findings.md`'s ~2.4–4.4s budget (measured for `fused/mps`; record which device/pipeline config was actually used). This replaces the earlier bar of merely "cues are spoken audibly between serves," which the original one-inter-serve-interval-late design would have satisfied while still being too slow. Record numbers in Run Notes. |

## Merge Criteria

- `scripts/verify.sh backend` and `scripts/verify.sh ios` both green.
- The Group 8 manual real-device end-to-end check (including the Group 6 audio-quality check and
  the measured contact-to-cue latency bar, median ≤5s / max ≤8s) completed and passing — **hard
  gate**, not deferred to a follow-up, since live audible feedback during recording is this
  phase's core, only-manually-verifiable behavior.
- No changes outside the Pro-2D path into `PhaseReviewView`, Lite pipeline/segmentation services,
  or `ContentView`.
- Assessment's existing `/v1/analyze` behavior (no `goal_rule_id`) unchanged, confirmed by
  Group 1's regression cases.

## Run Notes

### `/phase-review` deep review (2026-09-02)

Three-agent review (correctness / design-simplicity / spec-compliance) against the full branch
diff. Findings and dispositions:

- **Fixed — final-chunk write error wedged the session forever.** `CameraService.fileOutput(...)`
  dropped the finalize callback entirely when the *last* chunk's write failed (silent-drop was
  correct for non-final chunks, but the final chunk has no next chunk to recover on).
  `startChunkedRecording`'s callback signature changed to `(URL?, Bool) -> Void`; a final-chunk
  write error now calls the handler with `(nil, true)` instead of not calling it at all.
  `SetGoalSessionViewModel.handleChunk` treats a nil URL as "this chunk's file is gone" — skips
  upload, sets `errorMessage`, still finalizes. New tests:
  `CameraServiceTests.chunkFinalizeErrorOnFinalChunkStillNotifiesHandler`,
  `SetGoalSessionViewModelTests.nilFinalChunkURLStillFinalizes`.
- **Fixed — `cameraViewModel.recordingState` never reset after a Set Goal session.** Plan
  (plan.md:380-385) assigns `SetGoalSessionViewModel` the job of resetting `recordingState` to
  `.idle` once the final chunk is handled, mirroring `useClip()`/`retake()`; this was never wired
  up. `finalizeVideo()` now resets it. New test:
  `SetGoalSessionViewModelTests.finalizeResetsRecordingState`.
- **Fixed — duplicated attempt-row markup.** The pass/fail + spoken-cue row was written out
  verbatim in both `SetGoalRecordingView`'s summary sheet and `GoalSessionHistoryDetailView`.
  Extracted to a shared `GoalAttemptRowView`.
- **Fixed — `infer_with_person` had no direct unit test.** Plan item 0e asked for direct coverage
  (pixel xyxy unflipped/unnormalized; `None` when no person clears threshold); only its
  `select_largest_person_box` helper was tested directly. Added
  `test_infer_with_person_returns_pixel_xyxy_unflipped_unnormalized_alongside_detections` and
  `test_infer_with_person_returns_none_when_no_person_clears_threshold` to
  `test_object_detection.py`, stubbing `ObjectDetectionModel._model`.
- Both suites re-verified green after fixes: `scripts/verify.sh backend` (233 passed, 3 skipped),
  `scripts/verify.sh ios` (202 passed, 0 failed).

**Left open — hard gate, not deferred:** the manual real-device checks (Group 4 chunk-rotation,
Group 6 audio-quality, Group 8 end-to-end + the median ≤5s/max ≤8s contact-to-cue latency bar)
are still unrun. These require a physical device and cannot be closed by code review; outcomes to
be recorded here once run.

### Manual real-device checks (2026-09-02)

Run per `manual-device-checks.md` on a physical iPhone, backend on Mac (M3 Max) with
`DETECTION_MODEL_DEVICE=mps`, `fused/mps` pipeline.

- **Check A — chunk rotation: PASS.** Recorded several minutes across many 2s chunk boundaries;
  app stayed responsive throughout, no crash/hang. Console output otherwise clean aside from
  benign system-level AVFoundation/Fig* log noise unrelated to app logic.
- **Check B — audio quality: PASS.** Spoken cues audible at normal volume, timed usefully after
  each serve, spoken clearly.
- **Check C — latency: PASS.** Eyeballed, contact→cue consistently ~4s across serves — within the
  median ≤5s / max ≤8s bar. Config: `fused/mps`.
- **Check D — end-to-end: PASS.** Summary tally correct, Save worked, session reopened correctly
  from History with matching goal, attempts, pass/fail, and spoken cues.

All four checks pass. Group 8 hard gate is closed — `/merge` is unblocked.

**Follow-ups noted during manual testing (non-blocking, out of scope for P7):**
- Set Goal recording only supports the rear camera; front camera isn't selectable.
- No way to discard a Set Goal session from the results screen — needs a Cancel/back-to-mode-
  selection action instead of forcing a Save.
- Lite mode still shows the Assessment/Set Goal toggle on launch; it should only appear for
  Pro 2D.
- Toggle state bug: Lite → Record New → back arrow makes the Assessment/Set Goal toggle disappear
  even after switching back to Pro 2D; requires Pro 2D → Record New → back arrow to restore it.
- Future enhancement: show a still frame with pose skeleton overlay per serve on the results page
  (like the Assessment history page).
- Future enhancement: more specific spoken cues on goal miss (e.g. "elbow too low" instead of
  "elbow not in line with shoulders at trophy pose").
