# Phase P6b — Plan

> **Lite-isolation note:** no group modifies `PhaseReviewView`, the Lite pipeline/segmentation
> services, `LibraryVideoExporter.copyToTemp`'s existing behavior, or `ContentView`. Group 4's
> re-encode step is gated inside `runProPipeline` (Pro-only) on `inputType == "imported"`;
> `runLitePipeline` is untouched.

## Group 1 — Backend: Empty-Clip Detection (surface: `backend`)

1. In `backend/app/engine/phases.py`, modify `segment_serves`: after the main loop (right before
   building `segments`), add:
   ```python
   if not has_seen_active:
       return []
   ```
   Everything else in the function is unchanged — this only closes the case where velocity never
   crosses `LOW_MOTION_VELOCITY_THRESHOLD` anywhere in the clip.
2. In `backend/tests/test_segment_serves.py`, add `test_all_idle_frames_returns_empty_list`: build
   a frame sequence (reusing the file's existing frame-builder helpers) whose keypoints stay
   effectively stationary for the whole sequence (velocity always below
   `LOW_MOTION_VELOCITY_THRESHOLD`), assert `segment_serves(frames) == []`.
3. Run `pytest backend/tests/test_segment_serves.py -v` — confirm the new test and all existing
   tests in the file pass (in particular `test_single_serve_no_rest_gap_returns_one_segment` and
   the leading/trailing-idle tests, which include real motion and must be unaffected).

## Group 2 — Backend: False-Split Synthetic Calibration (surface: `backend`), hard merge gate

4. In `backend/tests/test_segment_serves.py`, add a synthetic fixture builder reproducing the
   false-split failure mode — one continuous serve interrupted by a mid-routine pause (e.g. a
   ball-bounce or grip adjustment) whose rest duration is at or above `MIN_REST_SECONDS`, followed
   by more of the *same* serve's motion, followed by a real trailing rest gap ending the clip.
   Document in a comment that at the pre-fix constants this incorrectly produces 2 segments instead
   of 1 — this is the bug being closed.
5. Investigate a fix that eliminates the false split on the Group 4 fixture(s) without regressing
   any real calibration video's expected serve count or any pre-existing test in
   `test_segment_serves.py`/`test_segmentation_ground_truth.py`. Not limited to retuning
   `MIN_REST_SECONDS`/`LOW_MOTION_VELOCITY_THRESHOLD` — if simple threshold retuning can't satisfy
   both constraints, broaden to a structural heuristic (e.g. requiring the active run immediately
   before a candidate rest gap to exceed some minimum duration before that gap counts as a
   boundary, so a brief mid-routine pause can't split a serve the way a genuine between-serves rest
   does). **If genuinely stuck after trying constant retuning plus at least one structural
   alternative, stop and ask the user for direction — do not merge with the gap unresolved or
   silently downgrade this to best-effort.**
6. Update the Group 4 synthetic fixture test(s) to assert the fixed behavior (exactly 1 segment,
   not 2).
7. Re-run `cd backend && python tools/segmentation_report.py` against every video in
   `calibration_data/`; confirm each video's detected serve count still matches its expected count
   in `backend/tools/segmentation_ground_truth.json` (7 videos). **Hard merge gate** — any mismatch
   must be resolved (retune further) before proceeding, same pattern as P4b's Group 4 gate.
8. Re-run `RUN_MODEL_INTEGRATION_TESTS=1 pytest backend/tests/test_segmentation_ground_truth.py -v`
   — confirm it still passes against real models and real footage.
9. Record in `validation.md` run notes: what fix was applied (retuned constants and/or a structural
   heuristic change, with before/after values), the synthetic-fixture pass/fail outcome, and
   confirmation the real-video serve counts from step 7 are unchanged.
10. Run `pytest backend/` (full suite) — confirm zero regressions across all groups so far.

## Group 3 — iOS: Video Re-encode Service (surface: `ios`)

11. Create `App/Services/Video/VideoReencoder.swift`:
    ```swift
    import AVFoundation

    protocol VideoReencoding: Sendable {
        func reencode(sourceURL: URL) async throws -> URL
    }

    struct VideoReencoder: VideoReencoding {
        // Target matches CameraService's existing Pro 2D live-capture lock (portrait
        // 720x1280@30fps) — confirm exact pixel dimensions against a real captured/exported
        // asset's track naturalSize during implementation rather than assuming; adjust these
        // constants if the actual portrait dimensions differ from 720x1280.
        static let targetSize = CGSize(width: 720, height: 1280)
        static let targetFPS: Int32 = 30

        enum ReencodeError: LocalizedError {
            case exportFailed(String)
            var errorDescription: String? { ... }
        }

        func reencode(sourceURL: URL) async throws -> URL {
            // AVAsset -> AVMutableVideoComposition (renderSize = Self.targetSize,
            // frameDuration = CMTime(value: 1, timescale: Self.targetFPS)), single instruction
            // spanning the full duration with a layer instruction that scales+centers the
            // source track into targetSize using aspect-fit (no cropping — must not cut off
            // part of the serve motion the way aspect-fill would).
            // AVAssetExportSession(asset:presetName: AVAssetExportPresetHighestQuality),
            // .videoComposition set, .outputFileType = .mov, .outputURL = a new temp .mov path.
            // Export via the completion-handler `exportAsynchronously(completionHandler:)` API
            // (iOS 17 minimum deployment target — the async `export(to:as:)` API requires
            // iOS 18+), wrapped in `withCheckedThrowingContinuation` to expose this async throws
            // signature. Throw .exportFailed on .failed/.cancelled export status.
        }
    }
    ```
    Implementer fills in the composition/export body per the comments above; the protocol/type
    signature and target constants are fixed.
12. Create `MyServeCoachTests/VideoReencoderTests.swift`: adapt
    `FrameSamplerServiceTests.makeTestVideo(frameCount:frameRate:)`'s `AVAssetWriter` fixture
    pattern, extended to accept a custom input pixel size (e.g. build a 1920×1080@60fps source
    fixture). Cases:
    - `reencode_producesOutputMatchingTargetSizeAndFrameRate` — output video track's `naturalSize`
      equals `VideoReencoder.targetSize`, `nominalFrameRate` is 30 (within floating-point
      tolerance).
    - `reencode_preservesDuration` — output duration matches input duration within a small
      tolerance.
    - `reencode_throwsOnInvalidSource` — a non-video/corrupt source URL throws
      `VideoReencoder.ReencodeError`.
    Clean up all temp files via `defer`.
13. Run `scripts/verify.sh ios` — confirm green.

## Group 4 — iOS: Wire Re-encode Into `runProPipeline` (surface: `ios`)

14. In `App/ViewModels/VideoSourceSelectionViewModel.swift`, add an injectable dependency to
    `init`: `reencoder: any VideoReencoding = VideoReencoder()`, stored alongside the existing
    `proPipeline`/`coordinator` dependencies.
15. Modify `runProPipeline(on:inputType:)`: immediately after the existing `url` is available and
    before `try await proPipeline.analyze(videoURL: url)`, insert:
    ```swift
    var analysisURL = url
    if inputType == "imported" {
        do {
            let reencoded = try await reencoder.reencode(sourceURL: url)
            try? FileManager.default.removeItem(at: url)
            analysisURL = reencoded
        } catch {
            errorMessage = "Could not process imported video. Try again."
            try? FileManager.default.removeItem(at: url)
            isProcessing = false
            print("[VideoSourceSelection] Re-encode error: \(error)")
            return
        }
    }
    ```
    Replace the subsequent `proPipeline.analyze(videoURL: url)` call and the `pendingVideoURL = url`
    assignment with `analysisURL` throughout the rest of the function. Recorded clips
    (`inputType == "recorded"`) skip the `if` block entirely and behave exactly as today —
    `analysisURL` is just `url` unchanged in that case.
16. Update `MyServeCoachTests/VideoSourceSelectionViewModelTests.swift`:
    - Add `MockVideoReencoding` (records call count/received URL; returns a canned URL or throws a
      canned error, configurable per test).
    - Update the shared `makeVM(...)` test helper to accept and default-inject a non-throwing
      `MockVideoReencoding`, so all pre-existing tests are unaffected by the new dependency.
    - `test_proMode_importedClip_reencodesBeforeAnalyzing`: `inputType: "imported"`, assert the
      mock reencoder was called with the import URL and `proPipeline.analyze` received the
      *reencoded* URL, not the original.
    - `test_proMode_recordedClip_skipsReencoding`: `inputType: "recorded"`, assert the mock
      reencoder was never invoked.
    - `test_proMode_reencodeFailure_setsErrorMessage`: mock throws, assert
      `errorMessage == "Could not process imported video. Try again."` and `isProcessing == false`.
17. Run `scripts/verify.sh ios` — confirm green.

## Group 5 — Cross-Cutting Verification (surface: `both`)

18. Run `scripts/verify.sh backend` and `scripts/verify.sh ios` — both green.
19. Run `git diff --name-only develop...HEAD` — confirm none of `PhaseReviewView.swift`,
    `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`,
    `PhaseGuesser.swift`, `ContentView.swift` appear in the changed-file list; confirm
    `LibraryVideoExporter.swift` does not appear at all (its `copyToTemp` behavior is untouched by
    this phase).
20. Confirm pre-existing `VideoSourceSelectionViewModelTests.swift` Lite-path and Pro-path test
    cases (zero-segments / success / failure / permission branches) pass with unmodified assertion
    content — only the new mock-reencoder default wiring was added.
21. Manual/best-effort verification: import a real non-720×1280@30fps video from the Photos
    library in Pro 2D mode, confirm it re-encodes and successfully segments/analyzes via the real
    Mac-hosted backend. Record the outcome in `validation.md` run notes; if a real device/backend
    pairing isn't available at implementation time, record that explicitly as a known gap rather
    than silently skipping it (mirrors P6's Group 9 precedent).
