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

*(Filled in during `/phase` implementation — final tuned constants or structural heuristic change
from Group 2, the synthetic false-split fixture outcome, the real-video serve-count re-validation
table, and the Group 5 manual smoke-test result or its explicit absence.)*

## Merge Criteria

- `scripts/verify.sh backend` and `scripts/verify.sh ios` both pass (zero failures), including all
  new tests from Groups 1–4.
- **Group 2's false-split fix is a hard merge gate**: the synthetic mid-routine-pause fixture no
  longer false-splits, every real calibration video's expected serve count from
  `segmentation_ground_truth.json` still matches, and the `RUN_MODEL_INTEGRATION_TESTS=1`
  ground-truth regression test still passes. If no fix was found after a genuine attempt (constant
  retuning plus at least one structural alternative), this phase stops and asks the user rather
  than merging with the gap unresolved.
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
