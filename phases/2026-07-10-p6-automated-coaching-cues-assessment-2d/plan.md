# Phase P6 — Plan

> **Lite-isolation note:** no group modifies `PhaseReviewView`, the Lite pipeline/segmentation
> services (`PoseAnalysisPipeline`, `PoseEstimationService`, `ServeSegmentationService`,
> `PhaseGuesser`), or `ContentView`. The mode selector lives inside `VideoSourceSelectionView`
> itself; selecting Lite leaves every existing call in that view's Lite branch unchanged.

> **Shared naming note:** all new Swift networking/model types use a `Backend`/`Pro` prefix
> where a name would otherwise collide with an existing Lite type — e.g. `BackendDetection` (vs.
> the backend's `Detection`), `ProServeAnalysisPipeline` (vs. Lite's `PoseAnalysisPipeline`). The
> six-frame backend phase keys (`start`/`release`/`trophy_pose`/`racket_drop`/`contact`/`finish`)
> are consumed as raw `String`s throughout iOS — they are unrelated to Lite's 3-case `ServePhase`
> enum in `App/Models/ServePhase.swift`, which is not touched.

## Groups 1–4 — REVISED mid-phase (see requirements.md "Mid-phase architecture revision")

The groups below (originally: JSON `/v1/segment` + multipart per-frame upload services +
frame-sampling pipeline orchestration) were **superseded** after real-device testing found the
on-device frame extraction/JPEG-encoding approach wasn't reliable enough to match
`segment_serves`'s tuning (full investigation in requirements.md Context). The original,
fully-working implementation of Groups 1–4 as originally written was preserved via a checkpoint
commit (`checkpoint: per-frame upload pipeline before video-upload pivot`) before being replaced.
What actually shipped:

## Group 1 — Backend: `POST /v1/segment` + `POST /v1/segment/video` (surface: `backend`)

1. `slice_detections_by_segments` promoted into `backend/app/engine/phases.py`;
   `backend/tools/segmentation_report.py` imports it instead of defining its own copy. (Unchanged
   from the original plan.)
2. `backend/app/models.py` gains `SegmentRequest`/`ServeSegment`/`SegmentResponse`. (Unchanged.)
3. `backend/app/routers/segment.py` keeps the original JSON `POST /v1/segment` (frames/detections
   already extracted client-side) exactly as originally planned — kept as a dormant-but-tested
   primitive, not this phase's iOS caller.
4. **New**: `sample_video_frames` promoted from `backend/tools/pose_benchmark.py` (dev-tool-only)
   into `backend/app/services/video_sampler.py` (verbatim body — reads a video file via
   `cv2.VideoCapture`, returns `list[tuple[float, np.ndarray]]` of `(timestamp, BGR frame)` at a
   given stride). `pose_benchmark.py` re-imports and re-exports the name so
   `segmentation_report.py` and `test_pose_benchmark.py` need no further changes.
5. **New**: `POST /v1/segment/video` added to `backend/app/routers/segment.py`:
   ```python
   @router.post("/segment/video", response_model=SegmentResponse)
   async def segment_video(
       request: Request,
       stride: int = DEFAULT_STRIDE,               # 2
       session_id: str | None = None,
       pose_model: RTMPoseModel = Depends(get_pose_model),
       detection_model: ObjectDetectionModel = Depends(get_object_detection_model),
   ) -> SegmentResponse:
       with tempfile.NamedTemporaryFile(suffix=".mov", delete=False) as tmp:
           tmp_path = Path(tmp.name)
           async for chunk in request.stream():
               tmp.write(chunk)
       try:
           try:
               sampled = sample_video_frames(tmp_path, stride)
           except ValueError:
               raise HTTPException(400, "could not open video")
           if not sampled:
               raise HTTPException(400, "video contains no frames")
           frames = [Frame(timestamp=ts, keypoints=pose_model.infer(img)) for ts, img in sampled]
           detections = [detection_model.infer(img) for _, img in sampled]
           serve_frames = segment_serves(frames)
           serve_detections = slice_detections_by_segments(detections, serve_frames)
           segments = [ServeSegment(frames=f, detections=d) for f, d in zip(serve_frames, serve_detections)]
           return SegmentResponse(segments=segments)
       finally:
           tmp_path.unlink(missing_ok=True)
   ```
   Raw-body streaming (`request.stream()`, no multipart envelope) — the client is uploading one
   file, not many. Same `SegmentResponse`/`ServeSegment` response shape as the JSON endpoint, so
   downstream `/v1/analyze` consumption is unaffected.
6. `backend/app/main.py` registers the `segment` router (unchanged registration — both routes live
   under it).
7. `backend/tests/test_segment_endpoint.py` (JSON endpoint, unchanged from original plan) +
   **new** `backend/tests/test_segment_video_endpoint.py`: synthetic clip via `cv2.VideoWriter`
   (mirrors `test_pose_benchmark.py`'s `_make_video` fixture), stub pose/detection models via
   `app.dependency_overrides` (mirrors `test_pose_endpoint.py`/`test_detect_endpoint.py`). Cases:
   valid video → `SegmentResponse` with frame count matching stride; `stride` query param
   respected; per-segment `detections` length equals `frames` length; invalid bytes / empty body →
   400.
8. Run `pytest backend/` (full suite) — confirm zero regressions. Also manually verified against
   real footage: `POST /v1/segment/video` against `ag_three_serves.MOV` returns 3 segments sized
   `[280, 161, 152]`, exactly matching the direct-Python `segment_serves` result.

## Group 2 — iOS: Detection Types, `CoachingService` Extension, Shared Request Executor (surface: `ios`)

9. `App/Models/BackendDetection.swift` — `BackendBoundingBox`/`BackendDetection`, both also
   `Equatable` (needed for pipeline-orchestration test assertions). Unchanged from original plan.
10. `App/Services/Coaching/CoachingService.swift` — `CoachingServiceProtocol`/`LiveCoachingService`
    gain `detections: [[BackendDetection]]?`, plus an injectable `session: URLSession = .shared`
    init parameter. Unchanged from original plan **except**: `nil` optional fields
    (`detections`/`session_id`) are **omitted** from the encoded JSON body, not encoded as
    explicit `null` — Swift's compiler-synthesized `Encodable` for `Optional` properties calls
    `encodeIfPresent`, not `encode`. (The original plan assumed the opposite; corrected via a
    failing test during implementation. Functionally equivalent either way — Pydantic's
    `Optional[...] = None` fields treat a missing key and an explicit `null` identically.)
11. **New, replaces the planned `MultipartFormEncoder`**: `App/Services/Networking/BackendRequestExecutor.swift`
    — a shared `sendAndDecode<T: Decodable>(_:session:)` (JSON/status-check/decode, used by
    `LiveCoachingService` and the JSON-segment client) and `sendUploadAndDecode<T: Decodable>(_:fromFile:session:)`
    (same contract, but via `URLSession.upload(for:fromFile:)` — streams a file from disk without
    buffering it into memory, used by the video-upload client). Both set a 180s request timeout:
    `/v1/pose`/`/v1/detect`/`/v1/segment/video` run real model inference sequentially over
    potentially hundreds of frames in one request/response cycle, plus a one-time backend
    cold-start model-load cost — comfortably exceeds `URLSession`'s 60s default even on success (a
    real device smoke test observed exactly this: a 200 OK arrived after the client had already
    timed out at 60s).
12. `MyServeCoachTests/CoachingServiceRequestEncodingTests.swift` — request-encoding tests via a
    new `MyServeCoachTests/Support/StubURLProtocol.swift` helper (see Group 3 — built here since
    it's needed by both). Locks in the omitted-vs-null behavior from step 10.
13. Run `scripts/verify.sh ios` — confirm green.

## Group 3 — iOS: Video Segmentation Service (surface: `ios`)

14. `MyServeCoachTests/Support/StubURLProtocol.swift` — intercepts requests on a
    `URLSessionConfiguration.ephemeral`-backed session, returns a canned response/data/error.
    **Keyed by request host, not a single global "last request"** — Swift Testing runs test
    functions concurrently by default, and an earlier global-state design caused genuine,
    reproducible cross-suite flakiness (one test's `reset()` racing another's in-flight assertion).
    `StubURLProtocol.uniqueBaseURL()` gives each test a private host; state for different tests
    never collides regardless of execution order. Same fix pattern reused in
    `VideoSourceSelectionViewModelTests`'s `makeIsolatedDefaults()` (a fresh `UserDefaults` suite
    per test, same race class with `UserDefaults.standard`).
15. `App/Services/Pose/VideoSegmentationService.swift` (**replaces** the originally-planned
    `PoseUploadService.swift` + `ObjectDetectionUploadService.swift` + `ServeSegmentationUploadService.swift`):
    ```swift
    struct ProServeSegment: Decodable, Sendable {
        let frames: [BackendFrame]
        let detections: [[BackendDetection]]?
    }

    protocol VideoSegmentationServiceProtocol {
        func segmentVideo(at url: URL, sessionId: String?) async throws -> [ProServeSegment]
    }

    final class LiveVideoSegmentationService: VideoSegmentationServiceProtocol {
        private struct SegmentResponseBody: Decodable { let segments: [ProServeSegment] }
        private let baseURL: URL
        private let session: URLSession

        init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
            self.baseURL = baseURL
            self.session = session
        }

        func segmentVideo(at url: URL, sessionId: String?) async throws -> [ProServeSegment] {
            var components = URLComponents(url: baseURL.appendingPathComponent("v1/segment/video"), resolvingAgainstBaseURL: false)!
            if let sessionId { components.queryItems = [URLQueryItem(name: "session_id", value: sessionId)] }
            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
            let body: SegmentResponseBody = try await sendUploadAndDecode(request, fromFile: url, session: session)
            return body.segments
        }
    }
    ```
16. `MyServeCoachTests/VideoSegmentationServiceTests.swift`: decode/status/malformed-JSON cases via
    `StubURLProtocol`, using a dummy on-disk file for `upload(for:fromFile:)` (content is
    irrelevant — the network layer is fully mocked). Notably does **not** assert on the uploaded
    file's bytes: `upload(for:fromFile:)` doesn't expose its body through `URLRequest` the way
    `data(for:)` does, so body-content assertions from the original per-frame-upload tests don't
    carry over — only response-side behavior is tested here.
17. Run `scripts/verify.sh ios` — confirm green.

## Group 4 — iOS: `ProServeAnalysisPipeline` Orchestration (surface: `ios`)

18. `App/Services/Pose/ProServeAnalysisPipeline.swift` — **far simpler than originally planned**:
    2 dependencies instead of 5, no frame sampling, no JPEG encoding, no timestamp-alignment logic
    (the whole class of alignment bugs the original design needed a dedicated test for no longer
    exists, since frames and detections are now produced together, in order, server-side):
    ```swift
    struct AssessmentServeResult: Sendable {
        let serveIndex: Int
        let coaching: CoachingResult
    }

    protocol ProServeAnalyzing: Sendable {
        func analyze(videoURL: URL) async throws -> [AssessmentServeResult]
    }

    enum ProServeAnalysisError: Error, Equatable {
        case noSegmentsDetected
    }

    actor ProServeAnalysisPipeline: ProServeAnalyzing {
        private let videoSegmentationService: any VideoSegmentationServiceProtocol
        private let coachingService: any CoachingServiceProtocol

        init(
            videoSegmentationService: any VideoSegmentationServiceProtocol = LiveVideoSegmentationService(),
            coachingService: any CoachingServiceProtocol = LiveCoachingService()
        ) {
            self.videoSegmentationService = videoSegmentationService
            self.coachingService = coachingService
        }

        func analyze(videoURL: URL) async throws -> [AssessmentServeResult] {
            let segments = try await videoSegmentationService.segmentVideo(at: videoURL, sessionId: nil)
            guard !segments.isEmpty else { throw ProServeAnalysisError.noSegmentsDetected }
            var results: [AssessmentServeResult] = []
            for (index, segment) in segments.enumerated() {
                let coaching = try await coachingService.analyze(
                    frames: segment.frames, detections: segment.detections, sessionId: nil
                )
                results.append(AssessmentServeResult(serveIndex: index, coaching: coaching))
            }
            return results
        }
    }
    ```
    `FrameSamplerService.makeSampler`/`sampleFrames`'s `stride:` parameter (added earlier this
    phase for the now-deleted on-device sampling path) was **reverted** to its pre-phase shape
    (reads `PoseConstants.kPoseSampleStride` directly) — its only consumer was deleted, so keeping
    it would be dead surface area on a file Lite also depends on.
19. `MyServeCoachTests/ProServeAnalysisPipelineTests.swift`: `MockVideoSegmentationService`
    replaces the three original per-service mocks. Kept: `ordersResultsBySegmentIndex`,
    `throwsNoSegmentsDetectedWhenSegmentationReturnsEmpty`, `propagatesSegmentationFailure`,
    `propagatesAnalyzeFailure`. **Dropped**: `test_passesDetectionsAlignedByTimestampToSegmentation`
    — the timestamp-alignment logic it tested no longer exists.
20. Run `scripts/verify.sh ios` — confirm green.

## Group 4b — iOS: Pro 2D Camera Resolution/FPS Lock (surface: `ios`)

*(New group, added mid-phase — see requirements.md's "Pro 2D camera resolution/fps lock" Key
Decision for the investigation that motivated it.)*

21. `App/Services/Video/CameraService.swift`: `CameraServiceProtocol.configure(position:sessionMode:)`
    gains a required `sessionMode: SessionMode` parameter. `_configure(position:sessionMode:)`
    branches: `sessionMode == .pro2D` → `session.sessionPreset = .hd1280x720` plus a new
    `_lockFrameRate(on:to:)` helper (`device.lockForConfiguration()`;
    `activeVideoMinFrameDuration`/`activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)`;
    `unlockForConfiguration()`). `sessionMode == .lite` → unchanged `.high` preset, no frame-rate
    lock — byte-for-byte current behavior. `CameraService` is shared by both modes and isn't on
    the protected Lite-isolation file list, but the branch keeps Lite's path untouched regardless,
    since changing Lite's actual recorded resolution/fps is an unquantified risk to Lite's own,
    separately-calibrated on-device segmentation.
22. Thread `sessionMode` through the call chain: `App/ViewModels/CameraViewModel.swift` gains a
    `sessionMode: SessionMode = .lite` init parameter, passed to `cameraService.configure(position:sessionMode:)`.
    `App/Views/RecordServeView.swift` gains a `sessionMode: SessionMode = .lite` parameter (custom
    `init` constructs `CameraViewModel(sessionMode:)`). `App/Views/VideoSourceSelectionView.swift`
    passes `viewModel.selectedMode` into `RecordServeView(onClipSelected:sessionMode:)`.
23. `MyServeCoachTests/CameraViewModelTests.swift`'s `MockCameraService.configure` signature
    updated to match. **Not further unit-testable**: `AVCaptureDevice.default(...)` returns `nil`
    on Simulator/CI — manual device verification only (spot-check recorded clip metadata via the
    same `cv2.VideoCapture` check used during the mid-phase investigation).
24. Run `scripts/verify.sh ios` — confirm green.

## Group 5 — iOS: Mode Selector (surface: `ios`)

25. Create `App/Models/SessionMode.swift`:
    ```swift
    enum SessionMode: String, CaseIterable, Identifiable {
        case lite = "Lite"
        case pro2D = "Pro 2D"
        var id: String { rawValue }
    }
    ```
26. In `App/ViewModels/VideoSourceSelectionViewModel.swift`:
    - Add a persisted mode property (not `@AppStorage` directly — `@Observable` classes don't mix
      cleanly with that property wrapper — backed by `UserDefaults.standard` instead):
      ```swift
      private static let modeDefaultsKey = "com.myservecoach.sessionMode"

      var selectedMode: SessionMode {
          get { SessionMode(rawValue: UserDefaults.standard.string(forKey: Self.modeDefaultsKey) ?? "") ?? .lite }
          set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeDefaultsKey) }
      }
      ```
    - Add a `proPipeline: any ProServeAnalyzing` dependency, injectable in `init` (default
      `ProServeAnalysisPipeline()`), alongside the existing `coordinator`.
    - Add Pro-specific published state: `var navigateToAssessmentResults = false` and
      `var assessmentResults: [AssessmentServeResult]?` (or a small wrapper view model — see
      Group 7; keep this group's addition minimal, just enough to branch and navigate).
    - Branch `runPipeline(on:inputType:)` at its top:
      ```swift
      func runPipeline(on url: URL, inputType: String = "imported") async {
          switch selectedMode {
          case .lite:
              await runLitePipeline(on: url, inputType: inputType)  // existing body, renamed
          case .pro2D:
              await runProPipeline(on: url, inputType: inputType)
          }
      }
      ```
      Rename the existing method body to `runLitePipeline` verbatim (no logic changes — this
      satisfies "Lite path unchanged" since the code itself doesn't change, only its name/call
      site). Add `runProPipeline`:
      ```swift
      @MainActor
      func runProPipeline(on url: URL, inputType: String = "imported") async {
          errorMessage = nil
          if let old = pendingVideoURL {
              try? FileManager.default.removeItem(at: old)
              pendingVideoURL = nil
          }
          do {
              let results = try await proPipeline.analyze(videoURL: url)
              pendingVideoURL = url
              assessmentResults = results
              navigateToAssessmentResults = true
          } catch ProServeAnalysisError.noSegmentsDetected {
              errorMessage = "No serves detected in this clip. Try a different clip."
              try? FileManager.default.removeItem(at: url)
          } catch {
              errorMessage = "Could not analyze video. Try again."
              try? FileManager.default.removeItem(at: url)
              print("[VideoSourceSelection] Pro pipeline error: \(error)")
          }
          isProcessing = false
      }
      ```
27. In `App/Views/VideoSourceSelectionView.swift`, add a segmented `Picker` bound to
    `viewModel.selectedMode`, placed between the title `VStack` and the source-buttons `VStack`:
    ```swift
    Picker("Mode", selection: $viewModel.selectedMode) {
        ForEach(SessionMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
        }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal)
    ```
    Note: `VideoSourceSelectionViewModel` uses `@Observable`, not `@Bindable`-incompatible state —
    confirm `$viewModel.selectedMode` works given the view already declares `@Bindable var
    viewModel: VideoSourceSelectionViewModel` at the top (it does, per the existing file).
    Add a `navigationDestination(isPresented: $viewModel.navigateToAssessmentResults)` pointing at
    the Group 7 results view (stub acceptable in this group if Group 7 hasn't landed yet in the
    same PR — since groups run sequentially in one phase, wire the real view once Group 7 exists).
28. Update `MyServeCoachTests/VideoSourceSelectionViewModelTests.swift`:
    - Add a `MockProServeAnalyzing` conforming to `ProServeAnalyzing`.
    - `test_defaultModeIsLite`.
    - `test_selectedModePersistsAcrossInstancesViaUserDefaults` (set on one VM instance, read on a
      new instance backed by the same `UserDefaults.standard` — clear the key in a `defer` so the
      test doesn't leak state into other tests).
    - `test_proMode_runPipeline_routesToProPipelineNotLiteCoordinator`: set `selectedMode = .pro2D`,
      call `runPipeline`, assert the mock Lite `PoseAnalyzing` pipeline was never invoked and the
      mock Pro pipeline was.
    - `test_proMode_noSegments_setsDistinctErrorMessage`.
    - `test_proMode_success_setsAssessmentResultsAndNavigates`.
    - `test_liteMode_runPipeline_behaviorUnchanged`: re-run the existing Lite-path assertions
      (zero segments / success / failure) with `selectedMode` explicitly `.lite` to lock in
      no-regression.
29. Run `scripts/verify.sh ios` — confirm green.

## Group 6 — iOS: SwiftData Models (surface: `ios`)

30. In `App/Models/SwiftData/ServeSession.swift`, add a `mode` field:
    ```swift
    var mode: String = "lite"
    ```
    Update the `init` to accept it with a default:
    ```swift
    init(inputType: String, videoURL: URL?, mode: String = "lite") {
        self.inputType = inputType
        self.videoURL = videoURL
        self.mode = mode
    }
    ```
    Add the inverse relationship:
    ```swift
    @Relationship(deleteRule: .cascade) var results: [ServeResult] = []
    ```
31. Create `App/Models/SwiftData/ServeResult.swift`:
    ```swift
    import Foundation
    import SwiftData

    @Model
    final class ServeResult {
        var id: UUID = UUID()
        var serveIndex: Int = 0
        var summary: String?
        @Relationship(deleteRule: .cascade) var cues: [CueRecord] = []
        var session: ServeSession?

        init(serveIndex: Int, summary: String?) {
            self.serveIndex = serveIndex
            self.summary = summary
        }
    }
    ```
32. Create `App/Models/SwiftData/CueRecord.swift`:
    ```swift
    import Foundation
    import SwiftData

    @Model
    final class CueRecord {
        var id: UUID = UUID()
        var ruleId: String = ""
        var phase: String = ""
        var message: String = ""
        var severity: String = ""
        var result: ServeResult?

        init(ruleId: String, phase: String, message: String, severity: String) {
            self.ruleId = ruleId
            self.phase = phase
            self.message = message
            self.severity = severity
        }
    }
    ```
33. Confirm `ServeResult` and `CueRecord` are added to the app's SwiftData `ModelContainer` schema
    list (find wherever `ServeSession.self`/`PhaseRecord.self` are currently registered — likely
    the app entry point's `.modelContainer(for:)` or an explicit `Schema([...])` — add both new
    types alongside them).
34. Create `MyServeCoachTests/ServeResultPersistenceTests.swift` (in-memory `ModelContainer`,
    matching however `PhaseRecord`/`ServeSession` are already tested if such a test exists —
    otherwise a fresh in-memory container): round-trip a `ServeSession(mode: "pro2d")` with 2
    `ServeResult`s each holding cues; fetch it back; assert `mode`, `results.count`,
    `results[0].cues.count`, and cascade-delete (deleting the session deletes its results and
    their cues).
35. Run `scripts/verify.sh ios` — confirm green.

## Group 7 — iOS: Assessment Results Screen + Persistence Wiring (surface: `ios`)

36. Create `App/ViewModels/AssessmentResultViewModel.swift`:
    ```swift
    import Foundation
    import Observation
    import SwiftData

    struct AssessmentServeDisplay: Identifiable {
        let id = UUID()
        let serveIndex: Int
        let summary: String?
        let cues: [Cue]  // pre-sorted: major before minor, then Kovacs phase order
    }

    @MainActor
    @Observable
    final class AssessmentResultViewModel {
        let serves: [AssessmentServeDisplay]
        let inputType: String
        private let videoURL: URL?

        var totalMajorCount: Int { serves.flatMap(\.cues).filter { $0.severity == "major" }.count }
        var totalMinorCount: Int { serves.flatMap(\.cues).filter { $0.severity == "minor" }.count }

        init(results: [AssessmentServeResult], inputType: String, videoURL: URL?) {
            self.inputType = inputType
            self.videoURL = videoURL
            let phaseOrder = ["start", "release", "trophy_pose", "racket_drop", "contact", "finish"]
            self.serves = results.map { result in
                let sorted = result.coaching.cues.sorted { a, b in
                    if a.severity != b.severity { return a.severity == "major" }
                    let ai = phaseOrder.firstIndex(of: a.phase) ?? phaseOrder.count
                    let bi = phaseOrder.firstIndex(of: b.phase) ?? phaseOrder.count
                    return ai < bi
                }
                return AssessmentServeDisplay(serveIndex: result.serveIndex, summary: result.coaching.summary, cues: sorted)
            }
        }

        func persist(to context: ModelContext) {
            let session = ServeSession(inputType: inputType, videoURL: videoURL, mode: "pro2d")
            for serve in serves {
                let result = ServeResult(serveIndex: serve.serveIndex, summary: serve.summary)
                result.cues = serve.cues.map {
                    CueRecord(ruleId: $0.ruleId, phase: $0.phase, message: $0.message, severity: $0.severity)
                }
                session.results.append(result)
            }
            context.insert(session)
        }
    }
    ```
37. Create `App/Views/AssessmentResultView.swift`:
    - Header: `"\(viewModel.serves.count) serve(s) analyzed"`, `"\(totalMajorCount) major ·
      \(totalMinorCount) minor"`.
    - One section per `AssessmentServeDisplay` (`"Serve \(serveIndex + 1)"`), listing each cue's
      `message` with a severity-colored indicator (red for major, orange for minor — matching the
      existing `errorBanner`/`photoPermissionDeniedBanner` red/orange convention in
      `VideoSourceSelectionView`) and its `summary` if non-nil.
    - Empty-cues-across-all-serves case: show a positive "No major issues detected" state per
      serve (reuse each serve's own `summary`, which the backend already sets to that string when
      clean).
    - `.onAppear` (or `.task`, once): call `viewModel.persist(to: modelContext)` via
      `@Environment(\.modelContext)`.
    - A "Done" toolbar button dismissing back to `VideoSourceSelectionView` (mirrors
      `PhaseReviewView`'s cancellation-action pattern).
38. Wire navigation in `VideoSourceSelectionView.swift`:
    ```swift
    .navigationDestination(isPresented: $viewModel.navigateToAssessmentResults) {
        if let results = viewModel.assessmentResults {
            AssessmentResultView(
                viewModel: AssessmentResultViewModel(
                    results: results, inputType: viewModel.pendingInputType, videoURL: viewModel.pendingVideoURL
                ),
                onDone: { viewModel.dismissAssessmentResults() }
            )
        }
    }
    ```
    (Requires exposing `pendingInputType`/`pendingVideoURL` as `private(set)` rather than fully
    private on the view model, or constructing the `AssessmentResultViewModel` inside
    `runProPipeline` itself and storing *that* rather than the raw `[AssessmentServeResult]` —
    prefer the latter: store `assessmentResultViewModel: AssessmentResultViewModel?` instead of
    raw results, mirroring how `phaseReviewViewModel` is already stored for the Lite path.)
    Add `dismissAssessmentResults()` mirroring `dismissPhaseReview()`.
39. Create `MyServeCoachTests/AssessmentResultViewModelTests.swift`:
    - `test_sortsCuesMajorBeforeMinorWithinPhaseOrder`.
    - `test_totalCountsSumAcrossAllServes`.
    - `test_persistCreatesServeSessionWithModePro2dAndCascadedResults` (in-memory `ModelContext`,
      assert `session.mode == "pro2d"`, `session.results.count`, cue field round-trip).
40. Run `scripts/verify.sh ios` — confirm green.

## Group 8 — iOS: History Screen Integration (surface: `ios`)

41. In `App/Views/SessionHistoryRowView.swift`, branch on `session.mode`:
    ```swift
    private var isProSession: Bool { session.mode != "lite" }

    private var proSubtitle: String {
        let cueCount = session.results.flatMap(\.cues).count
        return "\(session.results.count) serve(s) · \(cueCount) cue(s)"
    }
    ```
    In `body`, when `isProSession`: render a "Pro 2D" `Text` badge (small, capsule background,
    matching the app's existing badge-less style — a simple `.font(.caption2.weight(.semibold))`
    capsule is sufficient, no new design system needed) in place of the phase thumbnail, and
    `proSubtitle` in place of `inputTypeBadge`. Lite rows (`session.mode == "lite"`) render exactly
    as today — no visual change.
42. In `App/Views/SessionHistoryView.swift`, branch the single `navigationDestination(for:
    ServeSession.self)` closure on `session.mode`:
    ```swift
    .navigationDestination(for: ServeSession.self) { session in
        if session.mode == "lite" {
            HistoryComparisonView(session: session)
        } else {
            AssessmentHistoryDetailView(session: session)
        }
    }
    ```
43. Create `App/Views/AssessmentHistoryDetailView.swift` — read-only, reuses
    `AssessmentResultViewModel`'s display types but is constructed directly from a `ServeSession`'s
    persisted `results`/`cues` (not from a fresh `[AssessmentServeResult]`, which no longer exists
    at this point):
    ```swift
    struct AssessmentHistoryDetailView: View {
        let session: ServeSession
        // Maps session.results (sorted by serveIndex) -> the same per-serve section layout as
        // AssessmentResultView, reading ServeResult/CueRecord directly instead of AssessmentServeResult.
        // No persist() call — this is a read-only replay of already-saved data.
    }
    ```
    (Implementer's choice whether to factor the shared section-rendering into a small reusable
    view used by both `AssessmentResultView` and this view — reasonable either way given the
    input types differ; avoid over-abstracting for a two-caller reuse if the mapping is trivial.)
44. Create `MyServeCoachTests/SessionHistoryRowViewModeTests.swift` or extend an existing
    view-level test file if one exists for `SessionHistoryRowView` — if the codebase has no
    existing SwiftUI-view-level tests for this file (thumbnail logic is a computed property, so a
    plain `Testing` unit test can exercise `proSubtitle`/`isProSession` without ViewInspector),
    write plain unit tests against those computed properties for a mock/in-memory `ServeSession`.
45. Run `scripts/verify.sh ios` — confirm green.

## Group 9 — Cross-Cutting Verification (surface: `both`)

46. Run `scripts/verify.sh backend` and `scripts/verify.sh ios` — both green.
47. Run `git status --short` / `git diff develop...HEAD` and confirm none of `PhaseReviewView.swift`,
    `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`,
    `PhaseGuesser.swift`, `ContentView.swift` appear in the changed-file list — holds after the
    mid-phase pivot too (`CameraService.swift`/`CameraViewModel.swift`/`RecordServeView.swift` are
    shared-but-not-protected files touched by Group 4b, mode-gated to leave Lite's behavior
    unchanged; none of the six protected files themselves were touched).
48. Confirm `VideoSourceSelectionViewModelTests.swift`'s pre-existing Lite-path test cases
    (zero-segments / success / failure / permission branches) still pass unmodified in assertion
    content — only the `selectedMode: .lite` explicitness from step 28 was added, no existing
    assertion changed.
49. **Direct-backend verification** (bypassing iOS): streamed POST of real reference footage to
    `POST /v1/segment/video` — confirms the server-side extraction path independent of any iOS
    client behavior. Performed against 5 real clips during the mid-phase investigation (see
    requirements.md Context); `ag_three_serves.MOV` returns 3 segments matching the direct-Python
    `segment_serves` result exactly.
50. Record in `validation.md` run notes: confirmation that a real Mac-hosted backend run (manual,
    outside pytest/xcodebuild) was smoke-tested end-to-end on-device through Pro 2D mode,
    including the specific 3-serve clip that originally failed. If a real device/backend pairing
    isn't available at implementation time, record that explicitly as a known gap rather than
    silently skipping it.
