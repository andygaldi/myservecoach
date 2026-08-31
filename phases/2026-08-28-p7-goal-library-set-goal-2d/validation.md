# Phase P7 — Validation

## Definition of Done

Set Goal is a fully working second Pro 2D workflow: player picks a goal, records continuously,
hears an audible pass/fail cue after each auto-detected serve while still on court, sees a live
tally, and gets a saved, replayable session in History. Assessment's existing `/v1/analyze`
contract is unchanged for callers that don't send `goal_rule_id`. Lite mode, `PhaseReviewView`,
and `ContentView` are untouched.

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
| Segment confirmation rule holds across chunks | `pytest backend/tests/test_goal_session_endpoint.py` — a first chunk containing one full serve confirms 0 segments (provisional); a second chunk revealing a second serve's peak confirms segment 0 only; an `is_final=true` chunk confirms all remaining segments and returns them. |
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
| Chunk finalize → upload → tally update → spoken cue | `SetGoalSessionViewModelTests.swift` — simulated chunk finalize via the mock camera's chunk-trigger helper leads to `uploadChunk` called with correct `sessionId`/`goalRuleId`/`isFinal`; each returned result appends a `GoalAttemptDisplay` and calls `spokenFeedback.speak` with its `spokenCue`. |
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

## Merge Criteria

- `scripts/verify.sh backend` and `scripts/verify.sh ios` both green.
- The Group 8 manual real-device end-to-end check (including the Group 6 audio-quality check)
  completed and passing — **hard gate**, not deferred to a follow-up, since live audible feedback
  during recording is this phase's core, only-manually-verifiable behavior.
- No changes outside the Pro-2D path into `PhaseReviewView`, Lite pipeline/segmentation services,
  or `ContentView`.
- Assessment's existing `/v1/analyze` behavior (no `goal_rule_id`) unchanged, confirmed by
  Group 1's regression cases.

## Run Notes

_(Filled in during `/phase` / `/phase-review` — sweep results, defects found and fixed, manual
device check outcome.)_
