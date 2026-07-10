# Phase P6 — Validation

## Definition of Done

Phase P6 is complete when all of the following pass.

## Backend — `POST /v1/segment` (Group 1)

| Check | How to verify |
|---|---|
| `slice_detections_by_segments` is promoted into `app/engine/phases.py` and `segmentation_report.py` imports it instead of redefining it | `pytest backend/tests/test_segmentation_report.py -v` — zero failures, confirms the tool's own tests still pass after the relocation. |
| `/v1/segment` splits a single continuous serve into one segment | `pytest backend/tests/test_segment_endpoint.py -v -k test_single_continuous_serve_returns_one_segment` |
| `/v1/segment` splits a two-serve sequence into two segments with correctly boundary-sliced detections | `pytest backend/tests/test_segment_endpoint.py -v -k test_two_serve_sequence_returns_two_segments_with_sliced_detections` |
| Empty `frames` is rejected | `pytest backend/tests/test_segment_endpoint.py -v -k test_empty_frames_returns_422` |
| Omitted `detections` yields `null` per segment, not an error | `pytest backend/tests/test_segment_endpoint.py -v -k test_detections_omitted_yields_none_per_segment` |
| Router registered and reachable | `pytest backend/tests/test_segment_endpoint.py -v` — zero failures (a 404 on any test would indicate a missing `app.include_router` registration). |
| Full backend suite green | `pytest backend/` — zero failures. |

## iOS — Detection Types, `CoachingService`, Multipart Encoder (Group 2)

| Check | How to verify |
|---|---|
| `MultipartFormEncoder` produces the exact wire format the backend expects (repeated `frames` file parts, repeated `timestamps` text parts, optional `session_id`) | `xcodebuild test -only-testing:MyServeCoachTests/MultipartFormEncoderTests` (or `scripts/verify.sh ios` scoped via `-only-testing`) — all cases pass. |
| `LiveCoachingService`/`CoachingServiceProtocol` accept and correctly encode a `detections` field, including the `nil` → JSON `null` case | `xcodebuild test -only-testing:MyServeCoachTests/CoachingServiceRequestEncodingTests` |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — Pro Upload Services (Group 3)

| Check | How to verify |
|---|---|
| `LivePoseUploadService`, `LiveObjectDetectionUploadService`, `LiveServeSegmentationUploadService` each decode a successful stubbed response correctly | `scripts/verify.sh ios` — run the new service test files, all success-path cases pass. |
| Each service throws on a non-2xx stubbed response | Same test run — all `*_nonSuccessStatus` / equivalent cases pass. |
| Each service propagates a decoding error on malformed JSON rather than swallowing it | Same test run — all malformed-JSON cases pass. |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — `ProServeAnalysisPipeline` Orchestration (Group 4)

| Check | How to verify |
|---|---|
| Pipeline samples at stride 2, not Lite's stride 3 | `ProPoseConstants.kStride == 2` is asserted directly in a pipeline test, or exercised indirectly via `FrameSamplerServiceTests`' new stride-parameter case. |
| Results are ordered by `serveIndex`, matching segment order | `-k test_ordersResultsBySegmentIndex` |
| Zero segments returned raises a distinct error, not an empty success | `-k test_throwsNoSegmentsDetectedWhenSegmentationReturnsEmpty` |
| Failures from any of the four network dependencies (pose/detect/segment/analyze) propagate rather than being swallowed | `-k "test_propagatesPoseUploadFailure or test_propagatesDetectionUploadFailure or test_propagatesSegmentationFailure or test_propagatesAnalyzeFailure"` |
| Detections are aligned to frames by timestamp before being sent to segmentation, not by array position | `-k test_passesDetectionsAlignedByTimestampToSegmentation` |
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
| Lite-isolation: no protected file touched | `git diff --name-only develop...HEAD` contains none of `PhaseReviewView.swift`, `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`, `PhaseGuesser.swift`, `ContentView.swift`. |
| **Manual end-to-end smoke test (hard merge gate)** | Recorded in run notes below — see Merge Criteria. |

**Manual smoke test procedure** (hard gate, mirrors P5's calibration-run precedent):

1. Start the Mac-hosted FastAPI backend (`cd backend && uvicorn app.main:app --host 0.0.0.0 --port 8000`
   or the project's existing dev-run command) with real `RTMPoseModel`/`ObjectDetectionModel`
   dependencies (not the test stubs).
2. On a real device (or the Simulator, for the parts that don't require the camera — library
   import works in Simulator; live recording does not), open the app, select **Pro 2D** mode, and
   import one of the user's existing multi-serve clips via **Choose from Library** (the user has
   multi-serve footage ready — no new recording needed for this check).
3. Confirm the clip is correctly split into multiple serves (`/v1/segment` result count matches
   the visually obvious number of serves in the clip), each serve produces an `AnalyzeResponse`,
   and the Assessment results screen displays one section per serve with plausible cues (or a
   clean "no major issues" summary).
4. Confirm the session appears in **History** with the Pro badge and correct serve/cue counts, and
   tapping it reopens the same content via `AssessmentHistoryDetailView`.
5. Record the outcome — clip used, serve count detected vs. expected, any cues that fired and
   whether they're plausible, and any bugs found and fixed — in the run notes below.

**Run notes:** *(filled in during `/phase` once the manual smoke test above is performed)*

## Merge Criteria

- `pytest backend/` passes (full suite, zero failures) — includes the new `/v1/segment` endpoint
  and promoted-helper tests.
- `scripts/verify.sh ios` passes (full suite, zero failures) — includes all Group 2–8 additions.
- **Lite-isolation confirmed**: `git diff --name-only develop...HEAD` contains none of
  `PhaseReviewView.swift`, `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`,
  `ServeSegmentationService.swift`, `PhaseGuesser.swift`, `ContentView.swift`; every pre-existing
  Lite-path test case in `VideoSourceSelectionViewModelTests.swift` still passes with unchanged
  assertions.
- **Manual end-to-end smoke test completed and recorded (hard merge gate)** — a real multi-serve
  clip, run through the real Mac-hosted backend and a real device/simulator in Pro 2D mode,
  produces a segmented, per-serve cue result on the Assessment results screen, and that session is
  correctly browsable from History afterward. Per the user's confirmation, existing multi-serve
  clips are available for this check — no new recording is required to close this gate.
- No change to `rules.json` thresholds, `detect_phases`/`segment_serves` heuristics, or
  `RTMPoseModel`/`ObjectDetectionModel` inference logic — this phase wires already-calibrated
  logic into the app, it does not re-tune it.

## Not Required for Merge

- Set Goal session mode, goal library, audible cues — P7.
- Pro 3D mode / the 3-way mode selector — P8.
- A manual QA/correction step for Pro-detected phase frames — explicitly optional per the P4
  roadmap note; not built this phase.
- Any cross-serve cue ranking beyond per-serve severity/phase sorting.
- Skeleton overlay, live confidence check — P13.
- Serve-type awareness, multi-angle support, LLM coaching cues — P14/P15/P16.
- Jetson / on-court deployment — P17.
