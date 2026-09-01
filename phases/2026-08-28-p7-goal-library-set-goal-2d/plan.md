# Phase P7 — Plan

> **Isolation note:** no group touches `PhaseReviewView`, the Lite pipeline/segmentation services,
> or `ContentView`. All iOS code is new files or additive changes to Pro-2D-path files
> (`VideoSourceSelectionView`/`ViewModel`, `CameraService`/`CameraViewModel`, `SessionHistoryView`).

> **History screen design note (applies to Group 7):** requirements.md frames the History routing
> change as "`SessionHistoryView`'s existing `session.mode` string branch gains a `setGoal` case,"
> but `GoalSession` is specified as its own top-level SwiftData model (not a new `ServeSession.mode`
> value), so it cannot participate in a single `@Query(...) [ServeSession]`/`session.mode` branch.
> Group 7 resolves this by giving `SessionHistoryView` a second `@Query` over `[GoalSession]`,
> merging both into one date-sorted list for display, and keeping two separate
> `.navigationDestination(for:)` modifiers (one per model type) — SwiftUI supports multiple
> concurrent `navigationDestination(for:)` on one stack. This preserves the requirement's intent
> (Set Goal sessions appear in the same unified History list) without forcing an artificial shared
> model shape.

> **Chunk-rotation verification (applies to Group 4):** `AVCaptureMovieFileOutput` stop/restart
> timing and the chunk-rotation gap can't be exercised on Simulator or via `CameraServiceProtocol`
> mocks. Group 4's automated tests cover the timer/callback wiring and stop/restart sequencing
> logic only; the real on-device rotation behavior is a manual real-device check recorded in
> `validation.md`.

## Group 0 — Backend: Fused Pose/Detection Pipeline (surface: `backend`)

> Pre-implementation latency review (`latency-findings.md`) found `rtmlib`'s bundled YOLOX-m
> person detector is 92% of pose cost and runs at 0.44x realtime on CPU — an unbounded backlog
> over a live Set Goal session. This group wires the measured fix (2.24x–3.72x realtime, 0
> corpus disagreements) before the chunk endpoint (Group 2) exists to consume it.

0a. Keep `backend/tools/goal_latency_probe.py` (already written, untracked) as a committed sibling
    to `pose_benchmark.py` — it's the reproducible evidence and the regression check if the
    pipeline changes again. Commit it as-is; no changes needed.
0b. `backend/app/services/pose_model.py`: add a person-bbox-accepting path to `RTMPoseModel` —
    `infer(image, person_bbox=None)`, loading a standalone `rtmlib.RTMPose` (same checkpoint and
    input size `Body` uses) and skipping YOLOX when a bbox is supplied. `Body` stays as the
    no-bbox fallback so `POST /v1/pose` and all existing callers are untouched. Subject selection
    for the bbox must pick the **largest-area** person box (mirroring `select_primary_person`,
    `pose_model.py:57-65`), not highest-confidence — copy `goal_latency_probe.py`'s `FusedPipeline`
    logic rather than re-deriving it.
0c. `backend/app/services/object_detection.py`: expose the already-computed person box, e.g.
    `infer_with_person(image) -> tuple[list[Detection], list[float] | None]` returning the
    largest-area class-0 box in **pixel xyxy, unflipped and unnormalized** (the y-flip in
    `map_yolo_results_to_detections` is for the backend's own coordinate convention and must not
    be applied here). `DETECTION_CLASS_MAP` and the existing `infer` are unchanged, so racket/ball
    output stays bit-identical.
0d. Document `DETECTION_MODEL_DEVICE=mps` in dev-run docs as an optional speedup; do **not**
    hard-code it — `fused/cpu` already clears the latency gate at 2.24x, so nothing depends on
    CoreML/MPS (rtmlib's YOLOX-m detector fails under CoreML: `CoreML static output shape
    ({1,1,1,8400,8400}) and inferred shape ({1,8400}) have different ranks`; the fused path
    sidesteps this entirely by dropping YOLOX-m).
0e. New unit coverage: `infer_with_person` returns pixel xyxy (unflipped, unnormalized); returns
    `None` when no person clears threshold; `RTMPoseModel.infer` with no bbox still routes through
    `Body` unchanged (regression guard for existing `/v1/pose` callers).
0f. Run `scripts/verify.sh backend` — confirm green. Only Set Goal's chunk endpoint (Group 2) will
    call the new fused path this phase; `/v1/analyze` and `/v1/segment/video` are unchanged.

## Group 1 — Backend: Shared Scoring Function & `/v1/analyze` Goal Extension (surface: `backend`)

1. `backend/app/models.py`: add
   ```python
   class GoalResult(BaseModel):
       passed: bool
       spoken_cue: str
   ```
   Add `goal_rule_id: str | None = None` to `AnalyzeRequest`. Add `goal_result: GoalResult | None = None`
   to `AnalyzeResponse` (defaulted — existing Assessment callers that never send `goal_rule_id` get
   `goal_result: None`, zero wire-shape change to their responses).
2. `backend/app/engine/rules.py`: add a module-level
   `RULE_IDS: frozenset[str] = frozenset(rule.id for rule in _RULES)` — the drift-check surface for
   goal validation, computed once at import time alongside `_RULES`.
3. New `backend/app/engine/scoring.py`:
   ```python
   class UnknownGoalRuleId(ValueError):
       """Raised when a request's goal_rule_id doesn't match any rule in rules.json."""

   _GOAL_PASS_MESSAGE = "Nice serve — goal met!"
   _CLEAN_SERVE_SUMMARY = "No major issues detected — good serve!"  # moved verbatim from analyze.py

   def score_segment(
       frames: list[Frame],
       detections: list[list[Detection]] | None = None,
       goal_rule_id: str | None = None,
       view: str = "open_side",
   ) -> AnalyzeResponse:
       """One serve segment's full scoring: phase detection, rule evaluation, and (when
       goal_rule_id is set) the pass/fail goal check. Called by both POST /v1/analyze (one segment
       per request) and the goal session chunk endpoint (one call per newly-confirmed segment) —
       the single scoring code path both share."""
   ```
   Body: moves `analyze()`'s current logic verbatim — `detect_phases`, the `frame_indices`/
   `id_to_detections` identity joins, `evaluate_rules`, the `PhaseDetection` list build, and the
   clean-serve `summary` line — from `backend/app/routers/analyze.py` into this function, operating
   on the passed-in `frames`/`detections`/`view` instead of `request.frames`/`request.detections`.
   Adds, before evaluating rules: `if goal_rule_id is not None and goal_rule_id not in RULE_IDS: raise UnknownGoalRuleId(f"unknown goal_rule_id: {goal_rule_id!r}")`. After `cues` is computed, if
   `goal_rule_id is not None`: `firing = next((c for c in cues if c.rule_id == goal_rule_id), None)`;
   `goal_result = GoalResult(passed=firing is None, spoken_cue=firing.message if firing else _GOAL_PASS_MESSAGE)`; else `goal_result = None`. Returns `AnalyzeResponse(cues=cues, summary=summary, phases=phases, goal_result=goal_result)`.
4. Rewrite `backend/app/routers/analyze.py` to a thin wrapper:
   ```python
   @router.post("/analyze", response_model=AnalyzeResponse)
   async def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
       try:
           return score_segment(request.frames, request.detections, goal_rule_id=request.goal_rule_id)
       except UnknownGoalRuleId as e:
           raise HTTPException(400, str(e))
   ```
   Delete the now-unused `_CLEAN_SERVE_SUMMARY` constant and the moved logic from this file.
5. `backend/tests/test_analyze.py`: add cases — `goal_rule_id` matching a rule that fires on
   `BAD_ELBOW_FRAME`-style input → `goal_result.passed is False`, `spoken_cue` equals the firing
   cue's `message`; `goal_rule_id` matching a rule that doesn't fire on `CLEAN_SERVE_FRAMES` →
   `goal_result.passed is True`, `spoken_cue == "Nice serve — goal met!"`; unrecognized
   `goal_rule_id` → `400`; a request with no `goal_rule_id` (existing calls) → `goal_result is None`,
   confirming zero behavior change to pre-P7 callers.
6. New `backend/tests/test_scoring.py`: unit tests directly on `score_segment` (no HTTP layer) —
   `UnknownGoalRuleId` raised for a bad id, `goal_result` omitted (`None`) when `goal_rule_id` is
   `None`, pass/fail construction covered independent of the endpoint. This is the direct coverage
   for the function the chunk endpoint (Group 2) will also call.
7. Run `scripts/verify.sh backend` — confirm green.

## Group 2 — Backend: Goal Session Buffer & Chunk Endpoint (surface: `backend`)

8. New `backend/app/services/goal_session_buffer.py`:
   ```python
   from dataclasses import dataclass, field

   # Matches CameraService's Pro 2D live-recording lock (720x1280@30fps) — see
   # backend/app/routers/segment.py's DEFAULT_STRIDE and CameraService.swift's _configure. Used
   # only to convert each chunk's locally-zeroed sample timestamps into the buffer's running
   # clock; a session recorded at a different fps would drift, matching the same fixed-fps
   # assumption Pro 2D already relies on elsewhere.
   _CHUNK_FPS = 30.0

   @dataclass
   class _SessionBuffer:
       frames: list[Frame] = field(default_factory=list)
       detections: list[list[Detection]] = field(default_factory=list)
       reported_count: int = 0
       next_offset: float = 0.0

   _SESSIONS: dict[str, _SessionBuffer] = {}

   def append_chunk(
       session_id: str,
       stride: int,
       sampled: list[tuple[float, Frame, list[Detection]]],
   ) -> _SessionBuffer:
       """Appends one chunk's (local_timestamp, frame, detections) triples to session_id's buffer,
       offsetting each frame's timestamp by the buffer's running clock so chunk boundaries don't
       reset time to 0. Frame objects are rebuilt with the offset timestamp (Frame is immutable
       enough that reconstruction, not mutation, is simplest)."""

   def evict(session_id: str) -> None:
       """Removes session_id's buffer entry, if present. No-op if already evicted/missing."""

   def clear_all() -> None:
       """Test-only reset of the module-global dict — this buffer is process-lifetime, so tests
       must not leak state into each other via the same import."""
   ```
   `append_chunk` computes each frame's stored timestamp as `buffer.next_offset + local_ts`, then
   advances `buffer.next_offset += len(sampled) * (stride / _CHUNK_FPS)` once per call (not per
   frame) — approximating the chunk's real duration from its known sample count and stride,
   consistent with the fixed-fps assumption above.
9. `backend/app/models.py`: add
   ```python
   class GoalChunkResult(BaseModel):
       segment_index: int
       goal_result: GoalResult

   class GoalChunkResponse(BaseModel):
       results: list[GoalChunkResult] = Field(default_factory=list)
   ```
10. New `backend/app/routers/goal_session.py`:
    ```python
    router = APIRouter()

    @router.post("/goal/session/chunk", response_model=GoalChunkResponse)
    def goal_session_chunk(  # sync def, not async — see latency note below
        request: Request,
        session_id: str,
        goal_rule_id: str,
        stride: int = DEFAULT_STRIDE,  # imported from app.routers.segment, not redefined
        is_final: bool = False,
        pose_model: RTMPoseModel = Depends(get_pose_model),
        detection_model: ObjectDetectionModel = Depends(get_object_detection_model),
    ) -> GoalChunkResponse:
    ```
    **Latency note (`latency-findings.md`):** the handler is a plain `def`, not `async def` — as
    originally planned it would be `async def` with synchronous CPU-bound inference inline, which
    stalls FastAPI's event loop for every concurrent request including a queued `is_final=true`
    chunk. FastAPI runs sync `def` route handlers in a threadpool automatically, so this is the
    fix, not `run_in_threadpool` inside an `async def`.

    Body, mirroring `segment_video`'s tempfile-write-then-process shape:
    - Validate `goal_rule_id in RULE_IDS` up front (reuse `scoring.UnknownGoalRuleId` → `HTTPException(400, ...)`), before touching the buffer or writing the temp file.
    - Write the streamed body to a temp file, `sample_video_frames(tmp_path, stride)`, infer
      pose/detections per sampled frame using **Group 0's fused pipeline**
      (`detection_model.infer_with_person`'s box fed to `pose_model.infer(image, person_bbox=...)`),
      not `Body`/`rtmlib`'s bundled detector — this is the pipeline the latency gate was measured
      against. Build `sampled: list[tuple[float, Frame, list[Detection]]]`.
    - `buffer = goal_session_buffer.append_chunk(session_id, stride, sampled)`.
    - `segments = segment_serves(buffer.frames)`; `seg_detections = slice_detections_by_segments(buffer.detections, segments)`.
    - `confirmed_count`: **not** "all but the last segment" — see Blocker A in `latency-findings.md`,
      which measured that rule as one full inter-serve interval (~10–30s) late per verdict. Instead,
      confirm every segment whose peak is `CONFIRM_LAG_SECONDS` (= `MIN_PEAK_SEPARATION_SECONDS`,
      1.5s in `phases.py`) or more behind the buffer's trailing edge:
      ```python
      CONFIRM_LAG_SECONDS = MIN_PEAK_SEPARATION_SECONDS
      buffer_end = buffer.frames[-1].timestamp
      confirmed_count = len(segments) if is_final else sum(
          1 for seg in segments if _peak_timestamp(seg) <= buffer_end - CONFIRM_LAG_SECONDS
      )
      ```
      Uses the new `phases.py` peak-timestamp helper (see below) rather than re-deriving peaks in
      the router.
    - For `i in range(buffer.reported_count, confirmed_count)`: `result = score_segment(segments[i], seg_detections[i], goal_rule_id=goal_rule_id)`; append `GoalChunkResult(segment_index=i, goal_result=result.goal_result)`.
    - `buffer.reported_count = confirmed_count`.
    - If `is_final`: `goal_session_buffer.evict(session_id)` after building the results list (not before — the buffer is still needed to compute this call's results).
    - `finally: tmp_path.unlink(missing_ok=True)`, matching `segment_video`.
10a. `backend/app/engine/phases.py`: add an additive helper exposing a confirmed segment's peak
    timestamp — `segment_serves` returns segments, not peaks, so the router needs a way to get
    accepted peak timestamps without re-deriving them, e.g. `_peak_timestamp(segment) -> float` (or
    a parallel `segment_serves_with_peaks` returning `(segment, peak_timestamp)` pairs) built from
    the same peak data `_find_serve_peaks` already computes internally. Existing `segment_serves`
    callers (`/v1/segment/video`, `test_segment_serves.py`) are unaffected — this is additive.
11. `backend/app/main.py`: `from app.routers import ..., goal_session` and
    `app.include_router(goal_session.router, prefix="/v1")`.
12. New `backend/tests/test_goal_session_buffer.py`: `append_chunk` offsets a second chunk's
    timestamps past the first chunk's using `_CHUNK_FPS`/stride math; `evict` removes an entry and
    is a no-op on a missing `session_id`; a `clear_all()`-reset dict starts empty. Add a
    `clear_all()` call in this file's and the endpoint test file's fixture teardown.
13. New `backend/tests/test_goal_session_endpoint.py` (dependency-override stub-model pattern from
    `test_segment_video_endpoint.py`): a single chunk whose one detected segment's peak is
    `≥ CONFIRM_LAG_SECONDS` behind the buffer's trailing edge **is** confirmed without `is_final`
    — the behavior most worth a direct test, since it's the whole point of the lag-based rule
    (`latency-findings.md`'s Blocker A fix; the old "wait for a later segment's peak" rule would
    have left this provisional). A segment whose peak is *within* the lag window stays provisional
    until either the buffer grows past it or `is_final=true`; a final chunk confirms all remaining
    segments regardless of lag and evicts the buffer — a follow-up chunk with the same `session_id`
    after that starts a fresh buffer (buffer's `reported_count`/`next_offset` back to 0, observable
    via a subsequent request's results starting again from segment 0). Unknown `goal_rule_id` →
    `400`, buffer untouched (no chunk appended on validation failure).
14. Run `scripts/verify.sh backend` — confirm green.

## Group 3 — iOS: Goal Catalog, `ProWorkflow`, `GoalSelectionView` (surface: `ios`)

15. New `MyServeCoach/MyServeCoach/App/Models/GoalDefinition.swift`:
    ```swift
    struct GoalDefinition: Identifiable, Hashable, Sendable {
        let ruleId: String
        let displayName: String
        let phase: String
        var id: String { ruleId }
    }

    enum GoalCatalog {
        static let all: [GoalDefinition] = [
            GoalDefinition(ruleId: "release_toss_arm_straight", displayName: "Toss arm straight at release", phase: "release"),
            GoalDefinition(ruleId: "release_toss_hand_eye_height", displayName: "Toss height at eye level", phase: "release"),
            GoalDefinition(ruleId: "trophy_hitting_elbow_shoulder_line", displayName: "Trophy pose elbow line", phase: "trophy_pose"),
            GoalDefinition(ruleId: "trophy_toss_arm_straight", displayName: "Trophy pose toss arm straight", phase: "trophy_pose"),
            GoalDefinition(ruleId: "trophy_toss_arm_vertical", displayName: "Trophy pose toss arm vertical", phase: "trophy_pose"),
            GoalDefinition(ruleId: "racket_drop_ball_height", displayName: "Racket drop toss height", phase: "racket_drop"),
            GoalDefinition(ruleId: "racket_drop_ball_front", displayName: "Racket drop toss placement", phase: "racket_drop"),
            GoalDefinition(ruleId: "contact_left_hip_angle", displayName: "Hip drive at contact", phase: "contact"),
            GoalDefinition(ruleId: "contact_shoulders_stacked", displayName: "Shoulders stacked at contact", phase: "contact"),
        ]
    }
    ```
    Every `ruleId` matches a `backend/rules.json` id verbatim (checked by Group 8's cross-cutting
    verification, not automatically synced — matches requirements.md's runtime-validation-not-sync
    decision).
16. New `MyServeCoach/MyServeCoach/App/Models/ProWorkflow.swift`:
    ```swift
    enum ProWorkflow: String, CaseIterable, Identifiable {
        case assessment = "Assessment"
        case setGoal = "Set Goal"
        var id: String { rawValue }
    }
    ```
17. New `MyServeCoach/MyServeCoach/App/Views/GoalSelectionView.swift`: a `List` of
    `GoalCatalog.all`, one row per `GoalDefinition` (`displayName`, phase as a caption). Signature:
    `struct GoalSelectionView: View { var onGoalSelected: (GoalDefinition) -> Void }` — tapping a
    row calls `onGoalSelected(goal)`. Navigation title "Choose a Goal".
18. `VideoSourceSelectionViewModel`: add `var selectedWorkflow: ProWorkflow = .assessment` (not
    `UserDefaults`-persisted, unlike `selectedMode` — resets to Assessment each visit; only read
    when `selectedMode == .pro2D`), `var navigateToGoalSelection = false`,
    `private(set) var selectedGoal: GoalDefinition?`, `var navigateToSetGoalSession = false`. Add
    `func selectGoal(_ goal: GoalDefinition)` setting `selectedGoal = goal`,
    `navigateToGoalSelection = false`, `navigateToSetGoalSession = true`. Add
    `func dismissSetGoalSession()` mirroring `dismissAssessmentResults()`'s reset shape (clears
    `navigateToSetGoalSession`, `selectedGoal`).
19. `VideoSourceSelectionView`: when `viewModel.selectedMode == .pro2D`, show a second `Picker`
    bound to `viewModel.selectedWorkflow` (`ProWorkflow.allCases`) below the existing Mode picker.
    "Record New" button's action becomes: if `.pro2D` + `.setGoal`,
    `viewModel.navigateToGoalSelection = true`; otherwise unchanged
    (`viewModel.navigateToRecord = true`). "Choose from Library" is hidden when workflow is
    `.setGoal` — Set Goal is a live-recording-only workflow per `mission.md`'s "continuous recording
    session" framing, no library-import entry point. Add
    `.navigationDestination(isPresented: $viewModel.navigateToGoalSelection) { GoalSelectionView(onGoalSelected: viewModel.selectGoal) }`
    and
    `.navigationDestination(isPresented: $viewModel.navigateToSetGoalSession) { if let goal = viewModel.selectedGoal { SetGoalRecordingView(goal: goal, onDone: viewModel.dismissSetGoalSession) } }`.
20. New `MyServeCoach/MyServeCoachTests/GoalCatalogTests.swift`: every `GoalCatalog.all` entry has
    a non-empty `displayName` and a `ruleId` unique across the list (catches an accidental
    duplicate/typo at test time, short of the real backend-drift check).
21. New/extended `VideoSourceSelectionViewModelTests.swift` cases: `selectGoal` sets
    `selectedGoal`/flips both navigation flags correctly; `dismissSetGoalSession` resets them.
22. Run `scripts/verify.sh ios` — confirm green.

## Group 4 — iOS: Chunked Recording on `CameraService`/`CameraViewModel` (surface: `ios`)

23. `CameraServiceProtocol` (`CameraService.swift`): add
    ```swift
    func startChunkedRecording(chunkDuration: TimeInterval, onChunkFinalized: @escaping (URL, Bool) -> Void)
    func stopChunkedRecording()
    ```
    (`Bool` = `isFinal` — `true` on the chunk finalized after `stopChunkedRecording()` was called,
    so callers don't need separate bookkeeping to know which upload should carry `is_final=true`.)
24. `CameraService`: add private state `chunkOnFinalized: ((URL, Bool) -> Void)?`,
    `chunkDuration: TimeInterval = 0`, `isChunking = false`, `chunkTimer: DispatchSourceTimer?`.
    ```swift
    func startChunkedRecording(chunkDuration: TimeInterval, onChunkFinalized: @escaping (URL, Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isChunking = true
            self.chunkDuration = chunkDuration
            chunkOnFinalized = onChunkFinalized
            _beginNextChunk()
        }
    }

    func stopChunkedRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isChunking = false
            chunkTimer?.cancel()
            chunkTimer = nil
            movieOutput.stopRecording()
        }
    }

    // sessionQueue only
    private func _beginNextChunk() {
        let url = _tempChunkURL()
        isRecording = true
        movieOutput.startRecording(to: url, recordingDelegate: self)
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + chunkDuration)
        timer.setEventHandler { [weak self] in self?.movieOutput.stopRecording() }
        timer.resume()
        chunkTimer = timer
    }

    private func _tempChunkURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
    }
    ```
25. `CameraService`'s existing `AVCaptureFileOutputRecordingDelegate.fileOutput(...)`: branch at the
    top on whether chunking is active —
    ```swift
    sessionQueue.async { [weak self] in
        guard let self else { return }
        isRecording = false
        if let chunkHandler = chunkOnFinalized {
            let isFinal = !isChunking
            if isFinal { chunkOnFinalized = nil } else { _beginNextChunk() }
            if error == nil { chunkHandler(outputFileURL, isFinal) }
            return
        }
        let completion = recordingCompletion
        recordingCompletion = nil
        let result: Result<URL, Error> = error.map { .failure($0) } ?? .success(outputFileURL)
        completion?(result)
    }
    ```
    A finalize error (rare — disk full, etc.) drops that chunk silently rather than calling
    `chunkHandler` with a bad URL; `isChunking` continues driving whether the *next* chunk starts,
    so a mid-session error doesn't wedge the rotation, only loses one chunk's upload.
26. `CameraViewModel`: add pass-through methods
    `func startChunkedRecording(chunkDuration: TimeInterval, onChunkFinalized: @escaping (URL, Bool) -> Void)`
    (sets `recordingState = .recording`, forwards to `cameraService`) and
    `func stopChunkedRecording()` (forwards only — `recordingState` reset is the caller's job once
    the final chunk callback fires, mirroring how `useClip()`/`retake()` already own
    `recordingState` transitions rather than `CameraService`).
27. `MockCameraService` (`CameraViewModelTests.swift`): add conformance —
    `startChunkedRecording`/`stopChunkedRecording` store their handler and a `triggerChunk(url:isFinal:)`
    test helper analogous to the existing `triggerCompletion(result:)`.
28. New `CameraViewModelTests.swift` cases: `startChunkedRecording` sets `recordingState` to
    `.recording` and forwards `chunkDuration`/the handler to the mock; `stopChunkedRecording` calls
    through without mutating `recordingState` itself.
29. New `CameraServiceTests.swift` (if none exists yet — check before creating) or extend an
    existing suite: `stopChunkedRecording` before any chunk fires still results in exactly one
    `onChunkFinalized(_, isFinal: true)` call once the in-flight recording finishes — this is the
    one piece of the delegate-branch logic that's meaningfully unit-testable without a real capture
    session, by driving the delegate callback directly the way `MockCameraService`'s
    `triggerCompletion` does today for single-shot recording. (Full timer-driven multi-chunk
    rotation requires a real `AVCaptureSession`/device and is the manual real-device check noted at
    the top of this plan.)
30. Run `scripts/verify.sh ios` — confirm green.

## Group 5 — iOS: `GoalSessionService` & `SpokenFeedbackService` (surface: `ios`)

31. New `MyServeCoach/MyServeCoach/App/Models/GoalResult.swift`:
    ```swift
    struct GoalResult: Codable, Sendable {
        let passed: Bool
        let spokenCue: String
        enum CodingKeys: String, CodingKey { case passed; case spokenCue = "spoken_cue" }
    }

    struct GoalChunkResult: Decodable, Sendable {
        let segmentIndex: Int
        let goalResult: GoalResult
        enum CodingKeys: String, CodingKey { case segmentIndex = "segment_index"; case goalResult = "goal_result" }
    }
    ```
32. New `MyServeCoach/MyServeCoach/App/Services/Coaching/GoalSessionService.swift`:
    ```swift
    protocol GoalSessionServicing: Sendable {
        func uploadChunk(fileURL: URL, sessionId: String, goalRuleId: String, isFinal: Bool) async throws -> [GoalChunkResult]
    }

    final class LiveGoalSessionService: GoalSessionServicing {
        private struct ResponseBody: Decodable { let results: [GoalChunkResult] }
        private let baseURL: URL
        private let session: URLSession
        private let stride = 2  // matches segment.py's DEFAULT_STRIDE

        init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) { ... }

        func uploadChunk(fileURL: URL, sessionId: String, goalRuleId: String, isFinal: Bool) async throws -> [GoalChunkResult] {
            var components = URLComponents(url: baseURL.appendingPathComponent("v1/goal/session/chunk"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "session_id", value: sessionId),
                URLQueryItem(name: "goal_rule_id", value: goalRuleId),
                URLQueryItem(name: "stride", value: String(stride)),
                URLQueryItem(name: "is_final", value: String(isFinal)),
            ]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
            let body: ResponseBody = try await sendUploadAndDecode(request, fromFile: fileURL, session: session)
            return body.results
        }
    }
    ```
    Mirrors `LiveVideoSegmentationService`'s upload style exactly (same `sendUploadAndDecode`
    helper, same query-param-on-URL + raw-file-body shape).
33. New `MyServeCoach/MyServeCoach/App/Services/Coaching/SpokenFeedbackService.swift`:
    ```swift
    protocol SpokenFeedbackServicing: Sendable {
        func speak(_ text: String)
    }

    final class SpokenFeedbackService: SpokenFeedbackServicing {
        private let synthesizer = AVSpeechSynthesizer()
        func speak(_ text: String) {
            synthesizer.speak(AVSpeechUtterance(string: text))
        }
    }
    ```
34. New `MyServeCoach/MyServeCoachTests/GoalSessionServiceTests.swift`: `uploadChunk` builds the
    expected URL/query items and decodes a stubbed `results` response (mock `URLProtocol`, matching
    the existing pattern `LiveVideoSegmentationService`'s tests already use — locate and reuse
    that helper rather than inventing a second one).
35. `SpokenFeedbackService` has no meaningful unit test (it's a thin `AVSpeechSynthesizer` wrapper
    with no branching logic) — not tested directly; Group 6's `SetGoalSessionViewModel` tests cover
    its *call site* via a mock `SpokenFeedbackServicing`.
36. Run `scripts/verify.sh ios` — confirm green.

## Group 6 — iOS: `SetGoalSessionViewModel`/`SetGoalRecordingView` Orchestration (surface: `ios`)

37. New `MyServeCoach/MyServeCoach/App/Services/Video/ChunkVideoConcatenator.swift`: assembles the
    session's finalized chunk files into one playable video for persistence (`GoalSession.videoURL`
    mirrors `ServeSession`'s shape, which requires a single file, not a chunk list).
    ```swift
    protocol ChunkVideoConcatenating: Sendable {
        func concatenate(chunkURLs: [URL]) async throws -> URL
    }

    final class ChunkVideoConcatenator: ChunkVideoConcatenating {
        func concatenate(chunkURLs: [URL]) async throws -> URL {
            // AVMutableComposition: insert each chunk's video (and audio, if present) track
            // sequentially in order, then export via AVAssetExportSession(preset: .highestQuality)
            // to a new temp .mov file. Single-chunk sessions (a very short drill) still go through
            // this path for a uniform return type rather than a single-chunk special case.
        }
    }
    ```
38. New `MyServeCoach/MyServeCoach/App/Models/GoalAttemptDisplay.swift`:
    ```swift
    struct GoalAttemptDisplay: Identifiable, Sendable {
        let id = UUID()
        let segmentIndex: Int
        let passed: Bool
        let spokenCue: String
    }
    ```
39. New `MyServeCoach/MyServeCoach/App/ViewModels/SetGoalSessionViewModel.swift`:
    ```swift
    @MainActor
    @Observable
    final class SetGoalSessionViewModel {
        let goal: GoalDefinition
        private(set) var attempts: [GoalAttemptDisplay] = []
        private(set) var isRecording = false
        private(set) var isFinalizing = false  // true between "stop tapped" and the summary being ready
        var errorMessage: String?

        private let sessionId = UUID().uuidString
        private let cameraViewModel: CameraViewModel
        private let goalSessionService: any GoalSessionServicing
        private let spokenFeedback: any SpokenFeedbackServicing
        private let concatenator: any ChunkVideoConcatenating
        private var chunkURLs: [URL] = []

        init(
            goal: GoalDefinition,
            cameraViewModel: CameraViewModel = CameraViewModel(sessionMode: .pro2D),
            goalSessionService: any GoalSessionServicing = LiveGoalSessionService(),
            spokenFeedback: any SpokenFeedbackServicing = SpokenFeedbackService(),
            concatenator: any ChunkVideoConcatenating = ChunkVideoConcatenator()
        ) { ... }

        func startSession() {
            isRecording = true
            // chunkDuration: 2, not 4 — halves the 0-4s chunk-quantization term in the cue-latency
            // budget (latency-findings.md's "Resulting latency budget" table).
            cameraViewModel.startChunkedRecording(chunkDuration: 2) { [weak self] url, isFinal in
                Task { @MainActor [weak self] in await self?.handleChunk(url: url, isFinal: isFinal) }
            }
        }

        func stopSession() {
            isRecording = false
            isFinalizing = true
            cameraViewModel.stopChunkedRecording()
        }

        // Backlog guard (latency-findings.md): with 2s chunks, a slow/stalled upload must not let
        // outstanding chunk uploads queue unboundedly — that drifts every later cue later and later
        // instead of degrading predictably. Cap outstanding (in-flight, not-yet-responded) uploads
        // at a small bound; a new chunk finalizing while already at the bound drops the oldest
        // still-in-flight upload (abandons awaiting its result; a stray late response is ignored)
        // rather than letting the queue grow — losing an occasional serve's cue under sustained
        // backlog is the accepted degradation mode, not silence or unbounded lateness.
        private let maxOutstandingUploads = 2
        private var outstandingUploadIDs: [UUID] = []

        private func handleChunk(url: URL, isFinal: Bool) async {
            chunkURLs.append(url)
            let uploadID = UUID()
            if !isFinal, outstandingUploadIDs.count >= maxOutstandingUploads {
                outstandingUploadIDs.removeFirst()  // drop oldest in-flight upload
            }
            outstandingUploadIDs.append(uploadID)
            defer { outstandingUploadIDs.removeAll { $0 == uploadID } }
            do {
                let results = try await goalSessionService.uploadChunk(
                    fileURL: url, sessionId: sessionId, goalRuleId: goal.ruleId, isFinal: isFinal
                )
                for result in results {
                    let display = GoalAttemptDisplay(
                        segmentIndex: result.segmentIndex,
                        passed: result.goalResult.passed,
                        spokenCue: result.goalResult.spokenCue
                    )
                    attempts.append(display)
                    spokenFeedback.speak(display.spokenCue)
                }
            } catch {
                errorMessage = "Could not analyze that serve. Continuing session."
                print("[SetGoalSession] chunk upload failed: \(error)")
            }
            if isFinal { await finalizeVideo() }
        }

        private func finalizeVideo() async {
            defer { isFinalizing = false }
            videoURL = try? await concatenator.concatenate(chunkURLs: chunkURLs)
        }

        private(set) var videoURL: URL?

        var passCount: Int { attempts.filter(\.passed).count }
        var attemptCount: Int { attempts.count }

        func persist(to context: ModelContext) {
            let session = GoalSession(goalRuleId: goal.ruleId, goalDisplayName: goal.displayName, videoURL: videoURL)
            session.attempts = attempts.map {
                GoalAttemptRecord(segmentIndex: $0.segmentIndex, passed: $0.passed, spokenCue: $0.spokenCue)
            }
            context.insert(session)
        }
    }
    ```
    A chunk-upload failure (network error, transient backend issue) is logged and skipped —
    `errorMessage` surfaces once but recording continues uninterrupted, matching the live/on-court
    framing (never block the player mid-serve on a single failed upload).
40. New `MyServeCoach/MyServeCoach/App/Views/SetGoalRecordingView.swift`:
    `struct SetGoalRecordingView: View { let goal: GoalDefinition; var onDone: () -> Void }` — owns
    a `@State private var viewModel: SetGoalSessionViewModel`. Body: camera preview
    (`CameraPreviewView(session: viewModel.cameraViewModel.session)` — expose `cameraViewModel` as
    `let`/internal on the view model for this), a running tally header ("`\(passCount)/\(attemptCount)`
    passed") shown while `isRecording`, a Start/Stop button toggling `startSession()`/`stopSession()`,
    and — once `!isFinalizing && !isRecording && !attempts.isEmpty` — a summary sheet/section listing
    each `GoalAttemptDisplay` (pass/fail + spoken cue) with a "Save" button calling
    `viewModel.persist(to: modelContext)` then `onDone()`. `#if targetEnvironment(simulator)` shows
    `SimulatorPlaceholderView()`, matching `RecordServeView`'s existing simulator guard (chunked
    capture needs a real camera).
41. New `MyServeCoach/MyServeCoachTests/SetGoalSessionViewModelTests.swift` (mock
    `GoalSessionServicing`/`SpokenFeedbackServicing`/`ChunkVideoConcatenating`, and a
    `CameraViewModel` built with `MockCameraService`): `startSession` → simulated chunk finalize
    (via the mock camera's chunk-trigger helper from Group 4) → `uploadChunk` called with the right
    `sessionId`/`goalRuleId`/`isFinal`; each returned result appends an attempt and calls
    `spokenFeedback.speak` with its `spokenCue`; a failed `uploadChunk` sets `errorMessage` but
    leaves `isRecording` untouched and doesn't append a bogus attempt; `stopSession` → an `isFinal`
    chunk → `finalizeVideo` calls `concatenator.concatenate` with the accumulated chunk URLs and
    sets `videoURL`; `persist(to:)` builds a `GoalSession` with the right child
    `GoalAttemptRecord`s.
42. Run `scripts/verify.sh ios` — confirm green.

## Group 7 — iOS: Persistence & History (surface: `ios`)

43. New `MyServeCoach/MyServeCoach/App/Models/SwiftData/GoalSession.swift`:
    ```swift
    @Model
    final class GoalSession {
        var id: UUID = UUID()
        var date: Date = Date.now
        var goalRuleId: String = ""
        var goalDisplayName: String = ""
        var videoURL: URL?
        @Relationship(deleteRule: .cascade) var attempts: [GoalAttemptRecord] = []

        init(goalRuleId: String, goalDisplayName: String, videoURL: URL?) {
            self.goalRuleId = goalRuleId
            self.goalDisplayName = goalDisplayName
            self.videoURL = videoURL
        }
    }
    ```
44. New `MyServeCoach/MyServeCoach/App/Models/SwiftData/GoalAttemptRecord.swift`:
    ```swift
    @Model
    final class GoalAttemptRecord {
        var id: UUID = UUID()
        var segmentIndex: Int = 0
        var passed: Bool = false
        var spokenCue: String = ""
        var timestamp: Date = Date.now
        var session: GoalSession?

        init(segmentIndex: Int, passed: Bool, spokenCue: String) {
            self.segmentIndex = segmentIndex
            self.passed = passed
            self.spokenCue = spokenCue
        }
    }
    ```
45. `MyServeCoachApp.swift`: `container = try ModelContainer(for: ServeSession.self, GoalSession.self)`
    — `GoalSession` is a second schema root (not reachable from `ServeSession`'s relationship
    graph), so it needs its own entry.
46. `SessionHistoryView`: add `@Query(sort: \GoalSession.date, order: .reverse) private var goalSessions: [GoalSession]`. Build a merged, date-sorted list for display:
    ```swift
    private enum HistoryEntry: Identifiable {
        case serve(ServeSession)
        case goal(GoalSession)
        var id: UUID { switch self { case .serve(let s): s.id; case .goal(let g): g.id } }
        var date: Date { switch self { case .serve(let s): s.date; case .goal(let g): g.date } }
    }
    private var entries: [HistoryEntry] {
        (sessions.map(HistoryEntry.serve) + goalSessions.map(HistoryEntry.goal)).sorted { $0.date > $1.date }
    }
    ```
    `List` iterates `entries`; each row is `NavigationLink(value: session)` (existing) or
    `NavigationLink(value: goalSession)` (new) wrapping a new `GoalSessionHistoryRowView`. Keep the
    existing `.navigationDestination(for: ServeSession.self)` and add
    `.navigationDestination(for: GoalSession.self) { GoalSessionHistoryDetailView(session: $0) }`.
    `.onDelete` on the merged list maps back to the underlying `ServeSession`/`GoalSession` for
    `modelContext.delete(_:)`.
47. New `MyServeCoach/MyServeCoach/App/Views/GoalSessionHistoryRowView.swift`: mirrors
    `SessionHistoryRowView`'s shape (date, a "Set Goal" badge analogous to the existing "Pro 2D"
    badge, subtitle `"\(passCount)/\(attempts.count) passed"`) — no thumbnail (no phase-frame
    imagery persisted for Set Goal per requirements.md).
48. New `MyServeCoach/MyServeCoach/App/Views/GoalSessionHistoryDetailView.swift`: minimal read-only
    replay — header (`session.goalDisplayName`, formatted `session.date`), then a `List` of
    `session.attempts` (sorted by `segmentIndex`), one row per attempt showing "Serve N" +
    pass/fail + `spokenCue`. No aggregate stats section, no skeleton overlay — matches Assessment's
    minimal-first precedent (`AssessmentHistoryDetailView` degrades gracefully for pre-P6c
    sessions) but intentionally simpler since Set Goal never had phase-frame imagery to show.
49. New `MyServeCoach/MyServeCoachTests/SessionHistoryViewTests.swift` cases (or extend an existing
    suite if one already covers `SessionHistoryView`): a merged `ServeSession` + `GoalSession` list
    sorts by date across both types; deleting a `GoalSession` row removes only that entry.
50. Run `scripts/verify.sh ios` — confirm green.

## Group 8 — Cross-Cutting Verification (surface: `backend`, `ios`)

51. `git diff --name-only develop...HEAD` — confirm `PhaseReviewView.swift`, the Lite
    pipeline/segmentation service files, and `ContentView.swift` do not appear.
52. Confirm every `GoalCatalog.all` `ruleId` (Group 3) matches a `backend/rules.json` id exactly —
    manual cross-check (`python3 -c "import json; print(sorted(json.load(open('backend/rules.json'))['rules'][i]['id'] for i in range(9)))"` vs. the Swift catalog) since nothing wires
    the two together automatically (that's the point of the runtime 400-on-mismatch check, not a
    build-time sync).
53. Run `scripts/verify.sh backend` and `scripts/verify.sh ios` — both green as the final check.
54. Manual real-device check (per the Chunk-rotation note above): record a real multi-serve Set
    Goal session on a physical device, confirm chunks upload, cues are spoken audibly between
    serves, the running tally updates, and the saved `GoalSession` replays correctly from History.
    As part of this same recording, measure and record **wall-clock latency**: for each serve, the
    seconds from contact to its spoken cue (stopwatch or a timestamped console log at contact-time
    and at `speak()` call time) — bar: median ≤5s, max ≤8s, matching the ~2.4–4.4s budget in
    `latency-findings.md`'s "Resulting latency budget" table (that table assumes `fused/mps`;
    record which device/pipeline config was used alongside the numbers). Record all outcomes in
    `validation.md` run notes.
55. Update `specs/roadmap.md`'s P7 entry status marker only as part of `/merge` (not this phase) —
    noted for the implementer so it isn't done early.
