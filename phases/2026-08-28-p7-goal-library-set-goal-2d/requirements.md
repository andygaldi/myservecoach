# Phase P7 — Goal Library & Set Goal Session Mode (2D) — Requirements

## Scope

Set Goal is the second Pro 2D workflow (alongside Assessment, P6): a continuous recording
session focused on one technique goal, with an audible pass/fail cue spoken after each
auto-detected serve **while the player is still on court recording** — not a post-session
playback. The roadmap's literal framing ("stay focused on the court between serves") requires
true live feedback, which the current architecture doesn't support (Assessment uploads one
whole finished clip, then batch-processes it). This phase adds the streaming pieces needed for
live feedback, reusing P4/P5/P6d's segmentation and rule-evaluation logic unchanged.

## In Scope

### Goal catalog (iOS)

- A curated, static Swift list of goals — one goal per existing `rules.json` rule_id, with a
  friendly display name and its phase, e.g. `trophy_hitting_elbow_shoulder_line` → "Trophy pose
  elbow line". Covers all 9 rules currently in `rules.json`. No new backend threshold logic or
  calibration surface — Set Goal reuses Pro 2D's already-calibrated (P5) rules unchanged.
- Backend validates the `goal_rule_id` it receives against `rules.json` at request time (400 on
  an unknown id) — the runtime check that catches iOS/backend catalog drift, rather than a
  synced-catalog-fetch endpoint.

### Backend — `/v1/analyze` goal extension

- `AnalyzeRequest` gains an optional `goal_rule_id: str | None`.
- `AnalyzeResponse` gains an optional `goal_result: GoalResult | None`, where
  `GoalResult = { passed: bool, spoken_cue: str }`.
- When `goal_rule_id` is present: `passed` is `False` if a cue with that `rule_id` fired for
  this serve, `True` otherwise. `spoken_cue` is the firing cue's `message` on fail, or a short
  canned success phrase on pass.
- Assessment's existing calls (no `goal_rule_id`) are unaffected — `goal_result` stays `None`,
  zero behavior change to the existing contract.
- The scoring logic (`detect_phases` + `evaluate_rules` + the new goal check) is factored into a
  single reusable function, called by both `POST /v1/analyze` and the new chunk endpoint below —
  one scoring code path, not two.

### Backend — live session buffer & chunk endpoint

- New router `backend/app/routers/goal_session.py`:
  `POST /v1/goal/session/chunk?session_id=&goal_rule_id=&stride=2&is_final=false`, body a raw
  video chunk file (same upload style as `/v1/segment/video`).
- New `backend/app/services/goal_session_buffer.py`: an in-memory, process-lifetime dict keyed
  by `session_id`, holding the accumulated `Frame`/`Detection` lists (each chunk's frame
  timestamps continued from the buffer's running clock, not reset to 0) and how many segments
  have already been scored and returned (`reported_count`).
- On each chunk: extract + infer its frames (reusing `sample_video_frames` /
  `build_frame_sequence`'s pattern), append to the session's buffer, re-run `segment_serves`
  (P6d's peak-detection algorithm) over the full accumulated buffer.
- **Segment confirmation rule:** a segment is safe to score and speak once a *later* segment's
  peak has been detected (i.e. all but the currently-last segment), or — on the final chunk
  (`is_final=true`) — including the last one too. This mirrors how peak detection already treats
  trailing motion as provisional until a following boundary (or end of input) resolves it.
- Response: `{"results": [{"segment_index": int, "goal_result": GoalResult}, ...]}` — the
  newly-confirmed segments since the last chunk (usually 0 or 1, occasionally more on a chunk
  spanning two boundaries).
- `is_final=true` also evicts the session's buffer entry.
- Single in-memory dict, no persistence, no locking, no multi-worker safety — a documented,
  single-device/single-concurrent-session assumption (see Key Decisions), not a production
  session store.

### iOS — Pro 2D workflow selector

- New `ProWorkflow` enum (`.assessment`, `.setGoal`), chosen as a second step after selecting
  Pro 2D mode on `VideoSourceSelectionView` — the existing Lite/Pro 2D `SessionMode` picker is
  unchanged. Selecting Set Goal navigates to a new `GoalSelectionView` (pick one
  `GoalDefinition` from the catalog) before recording starts.

### iOS — chunked live recording

- New capability on `CameraService`/`CameraViewModel`: `startChunkedRecording(chunkDuration:
  onChunkFinalized:)` — internally stops and immediately restarts the movie file output on a
  fixed interval (default 4s), invoking a callback with each finalized chunk's file URL. Only
  used by the new Set Goal recording flow; Lite and Assessment's single-shot recording is
  unchanged.
- New `GoalSessionService` (URLSession) uploads each finalized chunk to
  `/v1/goal/session/chunk` with the session's `session_id`/`goal_rule_id`, `is_final=true` on
  the last chunk after the player stops recording, and decodes the results list.
- New `SpokenFeedbackService` wrapping `AVSpeechSynthesizer` (first use of speech synthesis in
  the app) — speaks each newly-returned `spoken_cue` as soon as its chunk response arrives.
- New `SetGoalRecordingView`/`SetGoalSessionViewModel` orchestrating: start chunked recording →
  per finalized chunk, upload + speak → on stop, upload the final chunk → show a live running
  tally (attempts, pass count) during recording, then a summary screen after stop.

### iOS — persistence

- New SwiftData models: `GoalSession` (id, date, goalRuleId, goalDisplayName, videoURL — mirrors
  `ServeSession`'s shape) with child `GoalAttemptRecord` (segmentIndex, passed, spokenCue,
  timestamp). No phase-frame imagery persisted — a pass/fail drill doesn't need Assessment's
  P6c skeleton-overlay/deviation machinery.
- `SessionHistoryView`'s existing `session.mode` string branch gains a `"setGoal"` case routing
  to a new `GoalSessionHistoryDetailView` — a simple read-only list of attempts, mirroring
  `AssessmentHistoryDetailView`'s read-from-SwiftData pattern.

## Out of Scope

- **Pro 3D goal mode.** Deferred to P12 per the roadmap.
- **Multiple simultaneous goals per session.** One goal per session, per the roadmap's "single
  technique goal" framing.
- **Any change to `rules.json` thresholds or rule definitions.** Set Goal reuses Pro 2D's P5
  rules unchanged.
- **Any change to Lite mode, or to Assessment's existing `/v1/analyze`/`/v1/segment/video` call
  sites** beyond the additive, defaulted `goal_rule_id`/`goal_result` fields.
- **Production-grade session state** (Redis, TTL eviction, multi-worker safety, auth). The
  single in-memory buffer is a documented limitation, not fixed this phase.
- **Recovering a session after an app crash or background suspension mid-recording.** The
  buffer is lost, matching the ephemeral nature of any other in-progress unsaved recording in
  the app today.
- **A gap-free chunk rotation.** Stopping/restarting `AVCaptureMovieFileOutput` has a small
  inherent gap at each boundary; closing it is a separate AVFoundation effort (see Key
  Decisions).
- **Skeleton overlay / deviation-caption UI for Set Goal.** That's Assessment/P6c-specific and
  isn't needed for a pass/fail drill.
- **A `GET /v1/goals` catalog-sync endpoint.** The runtime `goal_rule_id` validation on
  `/v1/analyze`/the chunk endpoint is the drift check; no separate sync mechanism this phase.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Audible feedback timing | True live, during recording — not post-hoc playback | User confirmed; matches the roadmap's literal "stay focused on the court between serves" framing over a simpler post-session-playback alternative. |
| Streaming mechanism | Rotating short-clip chunk uploads to a new stateful session-buffer endpoint, not WebSocket/raw frame streaming | User confirmed as the concretely implementable design; reuses P6d's peak-detection segmentation and the existing single-file-upload pattern (`/v1/segment/video`) chunk-by-chunk instead of inventing a new transport. |
| Goal definition | One goal = one existing `rules.json` rule_id, with a curated iOS display name | User confirmed; avoids a second threshold-calibration surface — Set Goal reuses Pro 2D's already-calibrated rules unchanged. |
| Backend contract | Extend `POST /v1/analyze`'s request/response (optional `goal_rule_id`/`goal_result`); the chunk endpoint reuses the same scoring function | User confirmed; one scoring code path serves both Assessment-style single-shot analysis and Set Goal's per-segment live scoring. |
| Set Goal entry point | A second, nested choice under Pro 2D (Assessment vs. Set Goal), not a third top-level `SessionMode` case | User confirmed; matches `mission.md`'s framing of Assessment/Set Goal as two Pro 2D workflows, and avoids the case-explosion risk P7b's own spec already flagged for a different axis (recording angle). |
| Segment confirmation rule | A segment is confirmed once a later segment's peak is detected, or on the session's final chunk | Mirrors how peak detection already treats trailing motion as provisional until a following boundary resolves it — avoids speaking a false pass/fail before a serve's full follow-through has been captured. |
| Session state | New process-lifetime, single-session in-memory buffer (no DB/Redis) | Matches the project's local-first, no-new-infra posture; Mac-dev-hosted and single-device/single-user in practice. Disclosed limitation, not a production session store. |
| Chunk rotation gap | Accepted, documented limitation | Stop/restart on `AVCaptureMovieFileOutput` has an inherent small gap; a seamless dual-buffer rotation is a larger AVFoundation effort, out of scope here. |
| Persistence depth | New `GoalSession`/`GoalAttemptRecord` SwiftData models, no phase-frame imagery | Matches the project's every-session-is-saved precedent (History screen) without pulling in Assessment's P6c overlay machinery, which a pass/fail drill doesn't need. |
| Goal catalog scope | All 9 existing `rules.json` rules, one goal each | Simplest complete option — no basis yet for excluding any rule from being a selectable goal. |

## Context

- Builds directly on **P4** (automatic six-frame segmentation), **P4b/P6b** (segmentation
  robustness), **P6d** (peak-based serve counting — the exact `segment_serves` algorithm the new
  session buffer re-runs on its growing frame list), **P5** (calibrated 2D rule thresholds), and
  **P6/P6c**'s `/v1/analyze` contract, `Cue` model, and cue-priority ordering.
- `specs/mission.md`'s Set Goal workflow: "Continuous recording session focused on a single
  technique goal... After each auto-detected serve, the app speaks an audible pass/fail cue so
  the player stays focused on the court."
- **Isolation rule** (`mission.md`/`tech-stack.md`): none of this touches Lite mode. All new code
  is Pro-2D-path-only and additive — `PhaseReviewView`, the Lite pipeline/segmentation services,
  and `ContentView` are untouched.
- `HANDEDNESS`'s hardcoding (flagged in P6d as a P7b prerequisite) is orthogonal to this phase —
  Set Goal calls `segment_serves`/`detect_phases` unchanged and inherits whatever handedness
  assumption they already make; no new handedness surface is introduced here.
- `POST /v1/segment/video`'s existing single-file-upload pattern
  (`backend/app/routers/segment.py`) is the direct model for the new chunk endpoint's per-request
  extract-and-infer step; the new piece is accumulating results *across* requests in a
  session-keyed buffer, which no existing endpoint does today.
