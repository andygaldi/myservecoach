# Phase P6b — Validation

## Definition of Done

Phase P6b is complete when all of the following pass.

## Backend — Empty-Clip Detection (Group 1)

| Check | How to verify |
|---|---|
| `segment_serves` returns `[]` for an all-idle frame sequence | `pytest backend/tests/test_segment_serves.py -v -k test_all_idle_frames_returns_empty_list` |
| All pre-existing `test_segment_serves.py` cases still pass unmodified, including real-motion single/leading/trailing-idle tests | `pytest backend/tests/test_segment_serves.py -v` — zero failures. |

## Backend — False-Split Synthetic Calibration (Group 2, hard merge gate)

| Check | How to verify |
|---|---|
| A synthetic mid-routine-pause fixture that previously false-split (2 segments) now resolves to exactly 1 segment | `pytest backend/tests/test_segment_serves.py -v -k` (the new false-split test name(s) from Group 2) |
| No real calibration video's expected serve count regressed | `cd backend && python tools/segmentation_report.py` — every video's detected count matches `backend/tools/segmentation_ground_truth.json`'s expected count (7 videos). **Hard merge gate.** |
| Ground-truth regression test still passes against real models/footage | `cd backend && RUN_MODEL_INTEGRATION_TESTS=1 .venv/bin/pytest tests/test_segmentation_ground_truth.py -v` |
| Full backend suite green after Groups 1–2 | `pytest backend/` — zero failures. |
| If no fix could be found after retuning constants and attempting a structural heuristic | Implementer stopped and asked the user for direction rather than merging with the gap open or silently downgrading to best-effort — recorded in run notes below. |

## iOS — Video Re-encode Service (Group 3)

| Check | How to verify |
|---|---|
| Re-encoding a non-conforming source produces output matching the target size/frame rate | `xcodebuild test ... -only-testing:MyServeCoachTests/VideoReencoderTests/reencode_producesOutputMatchingTargetSizeAndFrameRate` (or `scripts/verify.sh ios` running the full suite) |
| Duration is preserved within tolerance | `-only-testing:MyServeCoachTests/VideoReencoderTests/reencode_preservesDuration` |
| An invalid/corrupt source throws `VideoReencoder.ReencodeError` | `-only-testing:MyServeCoachTests/VideoReencoderTests/reencode_throwsOnInvalidSource` |
| Full iOS suite green | `scripts/verify.sh ios` — zero failures. |

## iOS — Wiring Into `runProPipeline` (Group 4)

| Check | How to verify |
|---|---|
| An imported Pro 2D clip is re-encoded before analysis | `-only-testing:MyServeCoachTests/VideoSourceSelectionViewModelTests/test_proMode_importedClip_reencodesBeforeAnalyzing` |
| A recorded Pro 2D clip skips re-encoding entirely | `-only-testing:MyServeCoachTests/VideoSourceSelectionViewModelTests/test_proMode_recordedClip_skipsReencoding` |
| A re-encode failure surfaces a clear error and resets processing state | `-only-testing:MyServeCoachTests/VideoSourceSelectionViewModelTests/test_proMode_reencodeFailure_setsErrorMessage` |
| Pre-existing Lite-path and Pro-path tests (zero-segments, success, failure, permission branches) still pass with unmodified assertions | `scripts/verify.sh ios` — full suite green, no assertion content changed from before this phase (only new mock-reencoder default wiring). |

## Cross-Cutting Verification (Group 5)

| Check | How to verify |
|---|---|
| Both suites green together | `scripts/verify.sh backend` and `scripts/verify.sh ios` |
| No Lite-isolation files touched | `git diff --name-only develop...HEAD` — none of `PhaseReviewView.swift`, `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`, `PhaseGuesser.swift`, `ContentView.swift` appear; `LibraryVideoExporter.swift` does not appear at all. |
| Manual real-footage/real-device smoke test performed if available | Import a real non-720×1280@30fps video in Pro 2D mode; confirm it re-encodes and segments/analyzes correctly against the real Mac-hosted backend. **Best-effort** — if a real device/backend pairing isn't available at implementation time, record that explicitly in run notes rather than silently skipping it. |

**Run notes:**

- **Group 1 (empty-clip detection):** `segment_serves` now returns `[]` when `has_seen_active`
  never becomes `True` (added right before segment-building, after the main loop). New test
  `test_all_idle_frames_returns_empty_list` passes. This also exposed that
  `test_segment_video_endpoint.py`'s `StubPoseModel` returned an identical static keypoint on
  every call — meaning its synthetic clips had zero velocity throughout and were only producing a
  segment by exploiting the exact bug being fixed. Updated `StubPoseModel` to move its keypoint a
  small amount per call (simulating genuine motion) so those 3 tests
  (`test_video_returns_segmentresponse_with_expected_frame_count`, `test_stride_param_respected`,
  `test_detections_sliced_parallel_to_frames`) correctly exercise a real (non-empty) segment again.
- **Group 2 (false-split fix), constants: no change to `MIN_REST_SECONDS` (0.3) or
  `LOW_MOTION_VELOCITY_THRESHOLD` (0.03).** Structural fix instead: new `MIN_ACTIVE_RUN_SECONDS =
  0.15` — a rest gap only counts as a serve boundary if the active run immediately preceding it
  lasted at least this long. Chosen because simple `MIN_REST_SECONDS` retuning could not have
  worked here: the tightest existing test
  (`test_two_serves_separated_by_rest_gap_returns_two_segments`) requires a boundary to still fire
  on a ~0.433s rest gap, capping any `MIN_REST_SECONDS` increase below that — but a realistic
  mid-routine pause (a held ball-bounce, a grip adjustment) can plausibly run *longer* than 0.433s,
  so no `MIN_REST_SECONDS` value could reject it without also breaking that real gap detection.
  `MIN_ACTIVE_RUN_SECONDS` sidesteps this entirely by keying off the *preceding active run's*
  duration instead of the rest's — a brief pre-serve fidget (bounce) never accumulates enough
  active time to arm a boundary, while a genuine completed swing (real calibration footage:
  ~1.9s release→finish on `ag_three_serves.MOV` serve 1) comfortably clears it. Bounded at 0.15s,
  safely under the existing test's ~0.167s active-run floor.
  - New synthetic fixtures in `test_segment_serves.py`:
    `test_mid_routine_pause_does_not_false_split` (a bounce + 0.5s pause + real swing + trailing
    rest — 0.5s is deliberately *longer* than any `MIN_REST_SECONDS` value that could survive the
    existing test suite, proving threshold retuning alone couldn't fix this) asserts exactly 1
    segment; `test_mid_routine_pause_still_allows_correct_split_before_next_serve` extends that
    same pattern with a second real serve after a genuine ~1.0s rest, asserting the boundary lands
    after the real swing (not the bounce) and still correctly produces 2 segments. Both pass.
  - **Real-video re-validation (hard gate) — `python tools/segmentation_report.py`:** all 7 videos
    tracked in `segmentation_ground_truth.json` match their expected serve counts exactly:

    | Video | Expected | Detected |
    |---|---|---|
    | `serve_1.MOV` | 1 | 1 |
    | `serve_2.mov` | 1 | 1 |
    | `serve_3.mov` | 1 | 1 |
    | `serve_4.mov` | 1 | 1 |
    | `ag_three_serves.MOV` | 3 | 3 |
    | `vesa_slow_mo.mov` | 1 | 1 |
    | `alcaraz_serve_1.mov` | 1 | 1 |

    (4 additional local-only videos not tracked in the ground truth —
    `new_3_serve_clip.MOV`/`test_2_serve_clip_a/b/c.MOV` — showed 1/1/1/3 detected respectively
    before the post-review fix below, 1/1/1/2 after. These are the exact clips from P6's
    camera-resolution/fps investigation, already documented there as under-segmenting at
    non-locked resolutions/frame rates — a Group 3/4 import-normalization concern, not a
    `segment_serves` logic issue. `test_2_serve_clip_c.MOV` going from 3→2 (matching its own
    filename's implied expectation) is a nice real-footage corroboration that the post-review fix
    below is a genuine improvement, not just a synthetic-fixture fix — though since it isn't part
    of the formal ground truth, it's not a pass/fail check on its own.)
  - **Ground-truth regression test
    (`RUN_MODEL_INTEGRATION_TESTS=1 pytest tests/test_segmentation_ground_truth.py`) — does NOT
    pass, but this is a pre-existing failure, confirmed unrelated to this phase.** The test failed
    identically with 6 mismatches both with and without this phase's `phases.py` changes applied
    (verified directly: `git stash` the phases.py edit, re-run, get byte-for-byte the same 6
    failure lines; `git stash pop`, re-run, same 6 lines again). All 6 failures are per-phase
    *timestamp* mismatches from `detect_phases` (a function this phase's Out of Scope list
    explicitly excludes) — none are serve-*count* mismatches, so `segment_serves` itself is
    unaffected. Two (`serve_2.mov` `trophy_pose`, `vesa_slow_mo.mov` `contact`) are the exact
    known, deliberately-deferred P4b gaps, whose ground-truth values were re-added to the JSON
    during P5 *for rule-calibration purposes* (P5 reads raw hand-labeled timestamps directly, not
    auto-detected ones) without being re-omitted from this auto-detection regression check — so
    this test has silently been failing since P5, not since this phase. The other four
    (`alcaraz_serve_1.mov` `start`/`release`/`racket_drop`/`finish`) exactly match P4b's own
    disclosed "Out-of-sample validation" finding for that held-out video ("2/6 phases within
    tolerance... trophy_pose was an exact match... contact passed... finish and start missed...
    release and racket_drop missed moderately... No further tuning was applied based on this
    result, per the purpose of a held-out check") — `alcaraz_serve_1.mov`'s full phase timestamps
    were included in the ground-truth JSON by P5 (same rule-calibration rationale), again without
    reconciling this test. **This is a genuine, disclosed gap in `test_segmentation_ground_truth.py`
    /`segmentation_ground_truth.json`'s authoring (conflating "ground truth for rule calibration"
    with "ground truth for auto-detection regression testing") dating to P5 — out of scope to fix
    here** (it's `detect_phases`/rule-calibration-ground-truth territory, not `segment_serves`,
    and fixing it properly means deciding whether to re-omit these known-gap values from the
    regression check or retune `detect_phases` itself, either of which belongs to a future phase).
    Flagging this explicitly for the user rather than silently marking this checklist item
    satisfied.
- **Group 3 (iOS re-encode service):** `App/Services/Video/VideoReencoder.swift` — `AVAssetExportSession`
  + `AVMutableVideoComposition` (`renderSize = 720x1280`, `frameDuration = 1/30`), a single
  layer instruction applying the source track's `preferredTransform` (raw sensor pixels → display
  orientation) then an aspect-fit scale+center transform into the target canvas (no cropping).
  Exports via the completion-handler `exportAsynchronously` API (iOS 17 minimum deployment target;
  the async `export(to:as:)` API requires iOS 18+), wrapped in `withCheckedThrowingContinuation`.
  All 3 `VideoReencoderTests` pass against a synthetic 1920x1080@60fps fixture (adapted from
  `FrameSamplerServiceTests.makeTestVideo`): output size/frame rate match target, duration is
  preserved, an invalid source throws. **Disclosed test-coverage limitation**: the synthetic
  `AVAssetWriter` fixture has an identity `preferredTransform` (no rotation), so the
  orientation-correcting transform math (the part that matters for a real portrait-recorded or
  landscape-recorded Photos-library import) is exercised by the composition code but not verified
  against a real rotated asset by any automated test — only the Group 5 real-device check below
  would exercise that, and it wasn't available this session (see below).
- **Group 4 (wiring):** `VideoSourceSelectionViewModel.runProPipeline` re-encodes only when
  `inputType == "imported"`, using the existing `inputType` parameter already threaded from
  `runPipeline` — no new plumbing needed. All 3 new tests pass
  (`proModeImportedClipReencodesBeforeAnalyzing`, `proModeRecordedClipSkipsReencoding`,
  `proModeReencodeFailureSetsErrorMessage`); pre-existing Pro-mode tests
  (`proModeRoutesToProPipelineNotLiteCoordinator`, `proModeNoSegmentsSetsDistinctErrorMessage`,
  `proModeSuccessSetsAssessmentResultsAndNavigates`) pass unmodified in assertion content — they
  call `runPipeline` with the default `inputType: "imported"`, so they now also implicitly
  exercise the (non-throwing, mocked) re-encode step, which doesn't affect any of their assertions
  since none check exact URL identity.
- **Group 5 (cross-cutting):** both suites green (`scripts/verify.sh backend`: 181 passed, 3
  skipped; `scripts/verify.sh ios`: full suite green). `git status --short` confirms no protected
  Lite-isolation file was touched (`PhaseReviewView.swift`, the Lite pipeline/segmentation
  services, `ContentView.swift`, `LibraryVideoExporter.swift` — none appear in the changed-file
  list; note `git diff --name-only develop...HEAD` alone under-reports since this phase's code
  changes are uncommitted — `git status --short` was used instead to include them).
  **Manual real-device/real-footage smoke test: not performed — no real device or booted
  Simulator was available in this automated session** (`xcrun simctl list devices` showed all
  simulators `Shutdown`, and no physical device was attached). Disclosed explicitly per the phase's
  best-effort instruction rather than silently skipped. Recommend the user run this manually before
  merge: import a real non-720×1280@30fps video from the Photos library in Pro 2D mode on a real
  device or a manually-booted Simulator with a sample video, and confirm it re-encodes and
  segments/analyzes correctly against the real Mac-hosted backend.

## Post-Review Fixes

After all 5 groups were green, a three-perspective deep review (correctness / design / spec
compliance) surfaced two real correctness bugs and one design cleanup, all fixed before merge:

1. **Correctness — false-split gate only worked for the first serve in a clip.** The original
   Group 2 implementation measured `active_duration` from `segment_start` (a variable set to
   `boundary + 1`, i.e. the *midpoint* of the just-accepted rest gap) rather than the true start
   of the new active run. Since `MIN_REST_SECONDS` (0.3s) is exactly double
   `MIN_ACTIVE_RUN_SECONDS` (0.15s), roughly half of any prior rest gap was silently credited as
   "active" time toward the next candidate boundary — meaning the mid-routine-pause fix worked for
   serve 1 but silently stopped protecting serve 2 onward. The reviewer reproduced this by placing
   the bounce/pause/swing pattern on the second serve of a two-serve clip and got a false 3-segment
   split. **Fix:** replaced `segment_start` with `active_run_start`, reset on every rest→active
   transition (whether or not that transition's rest was accepted as a boundary) rather than only
   on accepted boundaries — this measures exactly "the current unbroken active run's duration,"
   matching the docstring's stated intent. Added a regression test,
   `test_mid_routine_pause_on_second_serve_does_not_false_split`, reproducing the reviewer's exact
   scenario (now passes). Re-ran the full synthetic suite (12/12 pass), the full backend suite (182
   passed, 3 skipped), and the real-footage hard gate (`segmentation_report.py`) — all 7
   ground-truth videos still match exactly, and `test_2_serve_clip_c.MOV` (a local-only clip not in
   the formal ground truth) improved from 3→2 detected serves, matching its own filename's implied
   expectation — a real-footage corroboration that the fix is a genuine improvement, not just a
   synthetic-fixture patch.
2. **Correctness — `VideoReencoder` leaked the partial output file on export failure.**
   `AVAssetExportSession` can write a partial file at `outputURL` before failing or being
   cancelled; neither `VideoReencoder` nor its caller cleaned it up, so a failed re-encode (of,
   e.g., a malformed or unsupported imported video) would leak one temp file per attempt. **Fix:**
   wrapped the export call in `reencode()` in a `do/catch` that removes `outputURL` before
   rethrowing. Not independently unit-tested (forcing `AVAssetExportSession` to fail *after*
   `outputURL` is assigned isn't practical to construct reliably in a fast unit test) — the fix
   itself is a small, low-risk standard try/cleanup/rethrow pattern; disclosed rather than silently
   left uncovered.
3. **Design — duplicated `AVAssetWriter` test-fixture builder.** `VideoReencoderTests`'s
   `makeTestVideo` was a near-verbatim copy of `FrameSamplerServiceTests`'s. Extracted both into a
   shared `MyServeCoachTests/Support/TestVideoFixture.swift` (matching the existing
   `Support/StubURLProtocol.swift` precedent); both test files now call the shared helper.

All fixes re-verified: `scripts/verify.sh backend` (182 passed, 3 skipped) and
`scripts/verify.sh ios` (full suite green, including both `VideoReencoderTests` and all 3 new
`VideoSourceSelectionViewModelTests` re-encode-gating tests) both pass after every fix above.

## Merge Criteria

- `scripts/verify.sh backend` and `scripts/verify.sh ios` both pass (zero failures), including all
  new tests from Groups 1–4.
- **Group 2's false-split fix is a hard merge gate**: the synthetic mid-routine-pause fixture no
  longer false-splits (including on the second serve, per the post-review fix above), and every
  real calibration video's expected serve count from `segmentation_ground_truth.json` still
  matches exactly. **Satisfied.** The `RUN_MODEL_INTEGRATION_TESTS=1` ground-truth regression test
  does *not* pass — but this is a pre-existing, disclosed failure proven unrelated to this phase
  (identical failure list with and without this phase's `phases.py` changes, verified via
  `git stash`; see Group 2 run notes above for the full explanation and root cause). Per the
  phase's own escalation instruction, this is flagged explicitly for the user rather than silently
  claimed as passing or silently re-scoped.
- **No Lite-isolation files touched** — `git diff --name-only develop...HEAD` contains no changes
  to `PhaseReviewView.swift`, the Lite pipeline/segmentation services, `ContentView.swift`, or
  `LibraryVideoExporter.swift`.
- Re-encoding is confirmed gated correctly: recorded Pro 2D clips never invoke the reencoder;
  imported Pro 2D clips always do. Lite's import path is unaffected.
- The Group 5 manual real-footage/real-device check was attempted and its outcome (pass, fail, or
  "unavailable at implementation time") is recorded in run notes — not silently skipped.
- No changes to `rules.json`, rule calibration, `detect_phases`'s phase-detection heuristics (only
  `segment_serves`), the mode-selector, or any P7 Set-Goal-mode work — all explicitly out of scope
  per `requirements.md`.

## Not Required for Merge

- Real hand-labeled elaborate-pre-serve-routine footage collection or validation against it — not
  available this phase; Group 2's fix is validated against synthetic fixtures and existing real
  calibration videos only.
- Re-encoding recorded (non-imported) Pro 2D clips — already correctly locked at capture.
- Any P7 Set Goal mode functionality — this phase only removes blockers P7 would otherwise
  inherit.
