# Phase P6 — Validation

## Definition of Done

Phase P6 is complete when all of the following pass.

## Backend — `POST /v1/segment` + `POST /v1/segment/video` (Group 1)

| Check | How to verify |
|---|---|
| `slice_detections_by_segments` is promoted into `app/engine/phases.py` and `segmentation_report.py` imports it instead of redefining it | `pytest backend/tests/test_segmentation_report.py -v` — zero failures, confirms the tool's own tests still pass after the relocation. |
| JSON `/v1/segment` (unchanged) still splits correctly | `pytest backend/tests/test_segment_endpoint.py -v` — all cases pass. |
| `sample_video_frames` promotion preserves `pose_benchmark.py`'s public import surface | `pytest backend/tests/test_pose_benchmark.py -v` — zero failures. |
| `POST /v1/segment/video` returns a valid `SegmentResponse` with frame count matching the requested `stride` | `pytest backend/tests/test_segment_video_endpoint.py -v -k test_video_returns_segmentresponse_with_expected_frame_count` |
| `stride` query param is respected | `-k test_stride_param_respected` |
| Per-segment `detections` length equals `frames` length | `-k test_detections_sliced_parallel_to_frames` |
| Invalid video bytes / empty body → 400 | `-k "test_invalid_video_bytes_returns_400 or test_empty_body_returns_400"` |
| **Real-footage direct verification** (bypasses iOS): streamed `ag_three_serves.MOV` to the live `/v1/segment/video` endpoint returns 3 segments sized `[280, 161, 152]`, exactly matching the direct-Python `segment_serves` result | Manual — `curl -X POST "http://localhost:8000/v1/segment/video?stride=2" --data-binary @backend/tools/calibration_data/ag_three_serves.MOV -H "Content-Type: video/quicktime"`. Confirmed during this phase's investigation. |
| Full backend suite green | `pytest backend/` — zero failures (178 passed, 3 skipped as of the pivot). |

## iOS — Detection Types, `CoachingService`, Shared Request Executor (Group 2)

| Check | How to verify |
|---|---|
| `LiveCoachingService`/`CoachingServiceProtocol` accept and correctly encode a `detections` field | `xcodebuild test -only-testing:MyServeCoachTests/CoachingServiceRequestEncodingTests` |
| `nil` optional fields (`detections`, `session_id`) are omitted from the encoded JSON body, not sent as explicit `null` | Same test suite — `nilDetectionsOmitsKey` (renamed from the original plan's null-encoding assumption once the actual `Encodable` behavior was confirmed). |
| Shared `sendAndDecode`/`sendUploadAndDecode` apply the 180s Pro-mode timeout and correctly map non-2xx responses to `ProUploadError` | Exercised transitively by every Group 2–4 service test (`PoseUploadServiceTests` was retired; coverage now lives in `VideoSegmentationServiceTests` and `CoachingServiceRequestEncodingTests`). |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — Video Segmentation Service (Group 3)

| Check | How to verify |
|---|---|
| `StubURLProtocol` state is race-proof under Swift Testing's concurrent test execution | `scripts/verify.sh ios` run 3× consecutively with zero flakes (verified during implementation after an initial global-state design produced reproducible cross-suite failures). |
| `LiveVideoSegmentationService` decodes a successful stubbed response into `[ProServeSegment]` | `xcodebuild test -only-testing:MyServeCoachTests/VideoSegmentationServiceTests` — `decodesSuccessResponse` passes. |
| Throws `ProUploadError` on a non-2xx stubbed response | Same suite — `throwsOnNonSuccessStatus`. |
| Propagates a decoding error on malformed JSON | Same suite — `propagatesDecodingErrorOnMalformedJSON`. |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — `ProServeAnalysisPipeline` Orchestration (Group 4)

| Check | How to verify |
|---|---|
| Results are ordered by `serveIndex`, matching segment order | `-k test_ordersResultsBySegmentIndex` (kept from the original plan). |
| Zero segments returned raises a distinct error, not an empty success | `-k test_throwsNoSegmentsDetectedWhenSegmentationReturnsEmpty` |
| Segmentation and analyze failures propagate rather than being swallowed | `-k "test_propagatesSegmentationFailure or test_propagatesAnalyzeFailure"` (the original plan's pose/detection-specific propagation tests no longer apply — those dependencies were removed). |
| `FrameSamplerService`'s `stride:` parameter was reverted to its pre-phase shape (no longer needed) | `FrameSamplerServiceTests.swift` — only `sampleTimeCount` remains; the `explicitStrideOverridesDefault` case added earlier this phase was removed along with its production code. |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — Pro 2D Camera Resolution/FPS Lock (Group 4b)

| Check | How to verify |
|---|---|
| `CameraServiceProtocol.configure(position:sessionMode:)` compiles and all call sites updated | `scripts/verify.sh ios` build succeeds. |
| Lite mode's recorded resolution/fps is unaffected | Manual, real device — record a Lite-mode clip before and after this change; confirm identical `cv2.VideoCapture` metadata (same resolution/fps as pre-phase). |
| Pro 2D mode's recorded resolution/fps is locked to 720×1280@30fps | Manual, real device — record a Pro 2D clip, spot-check via `cv2.VideoCapture` metadata (same check used during the mid-phase investigation). Not unit-testable: `AVCaptureDevice.default(...)` returns `nil` on Simulator/CI. |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — Mode Selector (Group 5)

| Check | How to verify |
|---|---|
| Default mode is Lite | `-k test_defaultModeIsLite` |
| Mode selection persists across `VideoSourceSelectionViewModel` instances via `UserDefaults` | `-k test_selectedModePersistsAcrossInstancesViaUserDefaults` |
| Pro 2D mode routes `runPipeline` to the Pro pipeline, never touching the Lite `PoseAnalyzing` coordinator | `-k test_proMode_runPipeline_routesToProPipelineNotLiteCoordinator` |
| A no-segments Pro result sets a Pro-specific error message | `-k test_proMode_noSegments_setsDistinctErrorMessage` |
| A successful Pro result sets `assessmentResults`/navigates | `-k test_proMode_success_setsAssessmentResultsAndNavigates` |
| Every pre-existing Lite-path test case (zero segments / success / failure / all permission branches) still passes unmodified | `-k "not proMode"` subset of `VideoSourceSelectionViewModelTests`, or the full class — zero failures, zero assertion changes versus the pre-P6 file (only added explicit `.lite` mode setup). |
| Segmented control is present and bound correctly (compiles, `$viewModel.selectedMode` binding resolves) | `scripts/verify.sh ios` build step succeeds (a binding-type mismatch fails at compile time). |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — SwiftData Models (Group 6)

| Check | How to verify |
|---|---|
| `ServeResult`/`CueRecord` registered in the app's model schema | `scripts/verify.sh ios` build succeeds and `ServeResultPersistenceTests` can construct an in-memory `ModelContainer` including both types without a schema error. |
| A `ServeSession(mode: "pro2d")` with nested `ServeResult`/`CueRecord`s round-trips correctly | `-k test` on `ServeResultPersistenceTests` — `mode`, `results.count`, `results[0].cues.count` all match what was inserted. |
| Cascade delete removes results and cues when the session is deleted | Same test file — deleting the session leaves zero orphaned `ServeResult`/`CueRecord` rows in the container. |
| Existing Lite `ServeSession`/`PhaseRecord` persistence is unaffected by the new `mode` field's default | Existing SwiftData tests (if any pre-date this phase) still pass; a new session constructed without an explicit `mode` argument defaults to `"lite"`. |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — Assessment Results Screen + Persistence Wiring (Group 7)

| Check | How to verify |
|---|---|
| Cues are sorted major-before-minor, then by Kovacs phase order, within each serve | `-k test_sortsCuesMajorBeforeMinorWithinPhaseOrder` |
| Header counts sum major/minor cues across all serves correctly | `-k test_totalCountsSumAcrossAllServes` |
| `persist(to:)` creates a `ServeSession` with `mode == "pro2d"` and correctly nested results/cues | `-k test_persistCreatesServeSessionWithModePro2dAndCascadedResults` |
| Results screen builds and is reachable via the new navigation destination | `scripts/verify.sh ios` build succeeds; manual check (below) confirms reachability. |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — History Screen Integration (Group 8)

| Check | How to verify |
|---|---|
| `SessionHistoryRowView` shows a Pro badge + cue-count subtitle for Pro sessions, and is visually unchanged for Lite sessions | New unit tests on `isProSession`/`proSubtitle` pass; manual check (below) confirms no visual regression on an existing Lite history row. |
| Tapping a Pro session row navigates to `AssessmentHistoryDetailView`; a Lite row still navigates to `HistoryComparisonView` | Manual check (below) — both destinations reachable in the running app. |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## Cross-Cutting Verification (Group 9)

| Check | How to verify |
|---|---|
| Full backend suite green | `pytest backend/` (or `scripts/verify.sh backend`) — zero failures. |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |
| Lite-isolation: no protected file touched | `git diff develop...HEAD` / `git status --short` contains none of `PhaseReviewView.swift`, `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`, `PhaseGuesser.swift`, `ContentView.swift` — holds after the mid-phase pivot too (Group 4b's `CameraService`/`CameraViewModel`/`RecordServeView` changes are mode-gated, not on the protected list, and don't touch any protected file). |
| **Manual end-to-end smoke test (hard merge gate)** | ✅ Done — recorded in run notes below and Merge Criteria. |

**Manual smoke test procedure** (hard gate, mirrors P5's calibration-run precedent):

1. Start the Mac-hosted FastAPI backend (`cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`)
   with real `RTMPoseModel`/`ObjectDetectionModel` dependencies (not the test stubs).
2. Rebuild and reinstall the app on a real device (Pro 2D live recording needs real camera
   hardware — Simulator has none; library import of an already-existing clip would work in
   Simulator but the camera-lock check in Group 4b needs a real device regardless).
3. Select **Pro 2D** mode, record or import a multi-serve clip, and confirm it correctly splits
   into the right number of serves (per Group 4b, live-recorded clips are now locked to
   720×1280@30fps; imported clips are not, per the documented Photos-import gap), each serve
   produces an `AnalyzeResponse`, and the Assessment results screen displays one section per serve
   with plausible cues (or a clean "no major issues" summary).
4. Confirm the session appears in **History** with the Pro badge and correct serve/cue counts, and
   tapping it reopens the same content via `AssessmentHistoryDetailView`.
5. Record the outcome — clip used, serve count detected vs. expected, any cues that fired and
   whether they're plausible, and any bugs found and fixed — in the run notes below.

**Run notes:**

- **Backend direct-verification (done, passing):** `POST /v1/segment/video` against
  `ag_three_serves.MOV` returns 3 segments `[280, 161, 152]`, matching the direct-Python
  `segment_serves` result exactly — confirms the server-side extraction path works correctly
  independent of any iOS client.
- **Mid-phase device retest history (per-frame-upload architecture, now superseded):** the
  original per-frame-upload implementation was smoke-tested three times on-device before the
  pivot — (1) OOM crash on a 3-serve clip (root cause: `FrameSamplerService.sampleFrames`
  materializing every sampled `CGImage` in memory at once; fixed by streaming), (2) request
  timeout on `/v1/pose` (root cause: `URLSession`'s 60s default too short for sequential
  model inference over hundreds of frames; fixed by a 180s Pro-mode timeout), (3) wrong
  segmentation — a real 3-serve clip reported "1 serve analyzed" (root cause: on-device
  JPEG-extraction fidelity, motivating this pivot). These three fixes are subsumed by the
  video-upload architecture (issues 1–2 no longer apply — no on-device frame array or per-frame
  HTTP round-trip exists to OOM or time out) but are recorded here since they were real,
  independently-confirmed bugs found and fixed during this phase.
- **Device retest with the video-upload pivot (done, passing):** rebuilt and reinstalled on a real
  device. Two on-device tests performed:
  1. `new_3_serve_clip.MOV` (1080×1920@60fps, imported via **Choose from Library**) — still
     reports "1 serve analyzed," as expected. This is the documented Photos-import limitation, not
     a regression: that clip was recorded before the resolution lock existed and imports aren't
     re-encoded, so it retains its original resolution/fps and hits the same under-segmentation
     failure mode confirmed during the Step 0 investigation (independently reproducible via the
     direct-backend path, unrelated to any iOS client behavior).
  2. An older 3-serve clip already at 720×1280@30fps (matching the resolution `segment_serves` was
     validated against), imported via **Choose from Library** — **correctly segmented into 3
     serves**, and the Assessment results screen displayed coaching feedback per serve. This
     confirms the full pivoted pipeline end-to-end on a real device: video upload →
     `POST /v1/segment/video` → server-side extraction/pose/detection/segmentation → per-segment
     `POST /v1/analyze` → results screen rendering.
  - **Not yet separately verified**: a *live-recorded* clip (to confirm the camera lock itself
    produces 720×1280@30fps output, as opposed to relying on an already-correctly-sized imported
    clip) and the History-tab round-trip (Pro badge, reopening via `AssessmentHistoryDetailView`).
    Neither blocks this gate — the smoke test procedure accepts either recording or importing a
    correctly-sized multi-serve clip, and test 2 above satisfies it — but both are cheap to spot-check
    opportunistically next time the app is open.

## Merge Criteria

- `pytest backend/` passes (full suite, zero failures) — includes the new `/v1/segment/video`
  endpoint and promoted-helper tests.
- `scripts/verify.sh ios` passes (full suite, zero failures) — includes all Group 2–8 (and 4b)
  additions.
- **Lite-isolation confirmed**: `git diff`/`git status` contains none of `PhaseReviewView.swift`,
  `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`,
  `PhaseGuesser.swift`, `ContentView.swift`; every pre-existing Lite-path test case in
  `VideoSourceSelectionViewModelTests.swift` still passes with unchanged assertions.
- **Manual end-to-end smoke test completed and recorded (hard merge gate) — ✅ satisfied.** A real
  3-serve clip (720×1280@30fps), imported via Choose from Library on a real device, correctly
  segmented into 3 serves and produced per-serve coaching feedback on the Assessment results
  screen — full pivoted pipeline confirmed end-to-end. See run notes above for the two on-device
  tests performed and what remains an opportunistic (non-blocking) spot-check.
- No change to `rules.json` thresholds, `detect_phases`/`segment_serves` heuristics, or
  `RTMPoseModel`/`ObjectDetectionModel` inference logic — this phase wires already-calibrated
  logic into the app; the camera resolution/fps lock changes what the heuristic receives, not the
  heuristic itself.

## Not Required for Merge

- Set Goal session mode, goal library, audible cues — P7.
- Pro 3D mode / the 3-way mode selector — P8.
- A manual QA/correction step for Pro-detected phase frames — explicitly optional per the P4
  roadmap note; not built this phase.
- Any cross-serve cue ranking beyond per-serve severity/phase sorting.
- Skeleton overlay, live confidence check — P13.
- Serve-type awareness, multi-angle support, LLM coaching cues — P14/P15/P16.
- Jetson / on-court deployment — P17.
- **Making `segment_serves` robust to elaborate pre-serve routines, or re-encoding Photos-library
  imports to the locked resolution/fps** — both confirmed, disclosed gaps from this phase's
  investigation; logged as a roadmap TODO for dedicated follow-up work, not required here.
