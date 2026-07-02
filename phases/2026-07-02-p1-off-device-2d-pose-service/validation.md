# Phase P1 — Validation

## Definition of Done

Phase P1 is complete when all of the following pass.

## Backend — Pose Model Mapping (Group 1)

| Check | How to verify |
|---|---|
| COCO-17 keypoints map to the correct backend names | `pytest backend/tests/test_pose_model.py -v` — all 12 direct-mapped joints (`right_wrist`, `left_shoulder`, etc.) present with correct `x`/`y`/`confidence`. |
| `neck` derived as shoulder midpoint | Same test file — `neck.x`/`neck.y` equal the mean of `left_shoulder`/`right_shoulder`; `neck.confidence` equals `min` of the two source confidences. |
| `pelvis` derived as hip midpoint | Same test file — analogous assertion for `left_hip`/`right_hip`. |
| Face keypoints dropped | Same test file — result dict has no `nose`/`*_eye`/`*_ear` keys. |
| No real model load in default suite | Manual check: `grep -rn "Body(" backend/tests/test_pose_model.py` returns nothing; `pytest backend/tests/test_pose_model.py` completes in well under a second with no network activity. |

## Backend — `POST /v1/pose` Endpoint (Group 2)

| Check | How to verify |
|---|---|
| Valid request returns HTTP 200 with correct frame count/timestamps | `pytest backend/tests/test_pose_endpoint.py -v` |
| Mismatched `frames`/`timestamps` lengths returns HTTP 400 | Same test file |
| Corrupt image bytes returns HTTP 400 | Same test file |
| Endpoint registered under `/v1` prefix | `grep "pose.router" backend/app/main.py` shows `prefix="/v1"` |
| Full backend suite green | `pytest backend/` (equivalently `scripts/verify.sh backend`) — zero failures, including all pre-existing tests |

## Backend — Opt-In Real-Model Check (Group 3, informational — see Merge Criteria)

| Check | How to verify |
|---|---|
| Real `rtmlib.Body` loads and runs inference without error | `cd backend && RUN_MODEL_INTEGRATION_TESTS=1 pytest tests/test_pose_model_integration.py -v` — record pass/fail and first-run weight-download time/size in this file's notes once run. |

**Run notes:** _(fill in after Group 3's manual step 11 is executed)_

## iOS — VisionJointMapper & Types (Group 4)

| Check | How to verify |
|---|---|
| All 14 mapping-table entries translate correctly | `VisionJointMapperTests` — each Vision key maps to its documented backend key with `x`/`y`/`confidence` unchanged |
| Unmapped Vision keys are dropped, not passed through | Same suite — a frame containing an unrecognized key produces a result without that key |
| `CoachingResult`/`Cue` decode the backend's actual `AnalyzeResponse` shape | `CoachingResultDecodingTests` — fixture JSON using real backend field names (`rule_id`, `phase`, `message`, `severity`, `summary`) decodes into matching Swift values |

## iOS — `LiveCoachingService` (Group 5)

| Check | How to verify |
|---|---|
| Service targets `BackendConfig.baseURL` + `/v1/analyze`, not the old `/analysis/serve` stub | Code review of `LiveCoachingService.init`/`analyze` — no hardcoded `localhost` |
| Response decoding correctness | Covered by `CoachingResultDecodingTests` (Group 4) — no separate network-mock suite, consistent with the existing codebase precedent that `ReferenceFrameService`'s live fetch is likewise unit-untested at the network layer |

## iOS — App Flow Wiring (Group 6)

| Check | How to verify |
|---|---|
| `CoachingViewModel.analyze()` re-derives keypoints at each confirmed timestamp and calls the coaching service with translated frames | `CoachingViewModelTests` with a mock `CoachingServiceProtocol` |
| A thrown service error sets `fetchError` without crashing | Same suite |
| Full iOS test suite green | `scripts/verify.sh ios` (`xcodebuild test` on iPhone 17 Pro / iOS 26.4 Simulator) — zero failures, including all pre-existing tests |

## Integration (Group 7, manual — real device or Simulator + local backend)

| Check | How to verify |
|---|---|
| `/v1/pose` responds to a real multipart request | `curl -F "frames=@sample.jpg" -F "timestamps=0.5" http://localhost:8000/v1/pose` → HTTP 200, well-formed `frames` array |
| Full app flow completes end-to-end | Record or import → pose estimation → manual phase review → confirm all three phases |
| Coaching analyze fires alongside reference-frame fetch | Xcode console shows both `[CoachingAnalyze] cues: N, summary: ...` and the existing `[ReferenceFrameFetch]` logs after phase confirmation |
| Backend-down case degrades gracefully | Stop the backend, repeat the flow — `[CoachingAnalyze] failed: ...` logged, no crash, and the Phase 8/11 reference-frame error/retry flow still works independently |
| No regression to Phase 7/8 manual review or reference-frame flow | Existing behavior (phase scrubbing, confirm, reference-frame fetch/error/retry) unchanged |

## Merge Criteria

- `scripts/verify.sh backend` passes (full `pytest backend/` suite, zero failures) — the opt-in `RUN_MODEL_INTEGRATION_TESTS=1` real-model test is **not** part of this run and is **not** a merge gate; it's a one-time manual check whose outcome is recorded above for documentation purposes.
- `scripts/verify.sh ios` passes (full `xcodebuild test` suite, zero failures).
- The Group 7 manual integration smoke test has been run at least once (console logs confirmed) — camera-dependent steps validated on Simulator or device per the project's usual manual-test allowance.
- No changes to `rules.json` thresholds, no new UI screen, no `/v1/pose` iOS capture path — all explicitly out of scope per `requirements.md`.

## Not Required for Merge

- Rule threshold calibration or coaching-cue accuracy (Phase P4) — cues from `/v1/analyze` may be noisy given uncalibrated 2D thresholds; that's expected.
- A coaching-results UI screen (Phase P5).
- iOS capture/POST of raw frames to `/v1/pose` (deferred; backend-only this phase).
- Persisting cues to SwiftData.
