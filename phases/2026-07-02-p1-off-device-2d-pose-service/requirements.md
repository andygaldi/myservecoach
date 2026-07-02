# Phase P1 — Off-Device 2D Pose Service — Requirements

## Scope

Stand up a real off-device 2D pose model on the Mac backend, and wire the existing (dormant since Phase 4) coaching rule engine into the iOS app for the first time via a correctly-typed `/v1/analyze` call. This is the first Pro Version phase — it does not change anything the Lite MVP user sees; it activates plumbing behind the existing manual-review flow.

## In Scope

- **Backend: `RTMPoseModel` service** (`backend/app/services/pose_model.py`) wrapping `rtmlib.Body` (RTMPose ONNX weights via ONNX Runtime, `device="mps"` on the Mac M3 Max with `CoreMLExecutionProvider`, falling back to `cpu`). Loaded once at process startup, exposed via a FastAPI dependency so tests can override it with a stub.
- **Backend: `POST /v1/pose` endpoint** (`backend/app/routers/pose.py`) — accepts `multipart/form-data` (`frames[]`: JPEG bytes, `timestamps[]`: floats, optional `session_id`), decodes each frame with OpenCV, runs it through `RTMPoseModel`, and returns `PoseResponse { frames: [Frame] }` using the *existing* `Frame`/`Keypoint` models in `backend/app/models.py` — no new wire schema.
- **Backend: COCO-17 → backend keypoint-name mapping**, including deriving `neck` (midpoint of `left_shoulder`/`right_shoulder`) and `pelvis` (midpoint of `left_hip`/`right_hip`) since RTMPose's body model doesn't output them natively but `phases.py`/`angles.py`/`rules.json` expect them. Face keypoints (`nose`, `*_eye`, `*_ear`) are computed by the model but dropped — not part of the backend keypoint schema.
- **Backend: dependency** — add `rtmlib` (confirmed installable, current version `0.0.15`) to `backend/requirements.txt`.
- **Backend: test strategy split** — the default `pytest` run (what `scripts/verify.sh backend` executes) mocks `RTMPoseModel` via dependency override, so it stays fast/deterministic with no model-weight download. A separate test marked to skip unless `RUN_MODEL_INTEGRATION_TESTS=1` is set loads the real `rtmlib.Body` and runs inference against a fixture image, as a runnable (but non-blocking) real-model check.
- **iOS: `VisionJointMapper.swift`** (`App/Services/Pose/`) — translates a Vision-derived `PoseFrame.joints` dictionary (raw `*_joint` key names) into the backend's `right_wrist`/`left_shoulder`/etc. key names, per the mapping table in `specs/offdevice-pipeline.md`. Unmapped/unrecognized Vision joints are dropped.
- **iOS: reconcile `CoachingResult`** in `CoachingService.swift` to mirror the backend's `AnalyzeResponse` — a `Cue` struct (`ruleId`, `phase`, `message`, `severity`) and `summary: String?`, replacing the current placeholder `{ cues: [String]; keyframeTimestamps }`.
- **iOS: implement `LiveCoachingService.analyze()`** — takes translated keypoints for the three confirmed phases, POSTs a JSON body matching the backend's `AnalyzeRequest` (`frames`, optional `session_id`) to `BackendConfig.baseURL`-relative `/v1/analyze`, decodes `AnalyzeResponse`-shaped `CoachingResult`.
- **iOS: re-derive keypoints for confirmed phase frames** — after the user confirms a phase frame in the Phase 7 review flow, re-run `PoseEstimationService.detectPose` at the exact confirmed `CMTime` (the confirmed timestamp may not match any originally-sampled frame, since the user can scrub freely), producing the `PoseFrame` to translate and send.
- **iOS: wire into the existing app flow** — new `CoachingViewModel`, constructed and `.task`-fired alongside the existing `ReferenceFrameViewModel` at the same phase-confirmation point in `PhaseReviewView.swift`. On completion, logs the returned cues/summary to console (mirrors the Phase 8 `ReferenceFrameViewModel.fetch()` console-logging precedent). No new UI screen.
- **iOS: unit tests** for `VisionJointMapper`, `CoachingResult`/`AnalyzeResponse` decoding, and `LiveCoachingService.analyze()` request construction (using a mocked `URLProtocol` or similar, consistent with existing test patterns).

## Out of Scope

- iOS capture and POST of raw JPEG frames to the new `/v1/pose` endpoint. On-device Vision continues to drive frame capture, serve segmentation, and the Phase 7 manual review flow through P1 — nothing in the app yet needs backend-computed keypoints as an input. This wiring happens when P2/P3 actually consume it.
- A coaching-results UI screen displaying cues to the user (Phase P5).
- Rule threshold calibration against real 2D angles (Phase P4) — `rules.json` thresholds are unchanged. Cues returned by `/v1/analyze` in this phase may be noisy or uncalibrated; that's expected and acceptable since nothing user-facing displays them yet.
- Racket/ball object detection (Phase P2).
- Automatic multi-stage serve segmentation replacing the manual Phase 7 review step (Phase P3).
- Persisting cues to SwiftData (extends Phase 10's models; not needed until a UI consumes cues in P5).
- Two-camera/3D pipeline work (Phase P7+).
- Jetson deployment (Phase P16).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Pose model library | `rtmlib` (`Body` class) wrapping RTMPose ONNX weights via ONNX Runtime | Confirmed installable (`pip index versions rtmlib` → `0.0.15`) and API-inspected: `Body(backend="onnxruntime", device="mps")` auto-downloads OpenMMLab RTMPose weights and returns `(keypoints, scores)`. Concrete, low-risk path to a *real* RTMPose model matching the roadmap's named choice, without hand-sourcing MMPose configs. |
| Default verify-loop tests vs. real model | Mock `RTMPoseModel` via FastAPI dependency override for the default `pytest`/`scripts/verify.sh backend` run; gate a real-model integration test behind `RUN_MODEL_INTEGRATION_TESTS=1` | `/phase`'s self-verify loop has a 3-retry budget and needs deterministic, network-independent results. A first-run model download (weights are tens of MB, fetched from OpenMMLab) shouldn't be a dependency of every verify iteration, but a real-model check should still exist and be runnable on demand. |
| COCO-17 → backend keypoint schema | Derive `neck` and `pelvis` as shoulder/hip midpoints; drop face keypoints (`nose`, `*_eye`, `*_ear`) | RTMPose's body model outputs COCO-17, which lacks `neck`/`pelvis`. The existing `phases.py`/`angles.py`/`rules.json` (built against the Vision-derived schema, which does supply `neck_joint`/`root_joint`) expect those two keys to be present. |
| Where the coaching-analyze call fires | New `CoachingViewModel`, fired alongside `ReferenceFrameViewModel` at the same point in `PhaseReviewView.swift` | Keeps the Phase 8 reference-frame fetch and the P1 coaching analyze as two independent, single-responsibility view models instead of overloading `ReferenceFrameViewModel` with an unrelated concern. |
| Keypoints for confirmed frames | Re-run `PoseEstimationService.detectPose` at each confirmed `CMTime`, not a lookup into the original segmented `[PoseFrame]` list | The user can scrub to any frame during manual review (Phase 7); the confirmed timestamp may not equal any originally-sampled frame's timestamp, so keypoints must be computed fresh at the exact confirmed time. |
| `/v1/pose` iOS wiring | Deferred to a later phase | Nothing in the app yet needs backend-computed keypoints — on-device Vision still drives capture/segmentation/manual-review through P1. Building the capture/POST path now would have no consumer. |
| `/v1/analyze` request shape | Reuse existing `AnalyzeRequest`/`Frame`/`Keypoint` Pydantic models as-is | No backend schema changes needed — Phase 4 already built and unit-tested this contract; P1 only needed a correctly-typed iOS caller. |

## Context

- Phase 4 built the coaching rule engine (`rules.json`, `phases.py`, `rules.py`) and the `/v1/analyze` endpoint, unit-tested standalone with pytest, but never called from the iOS app — `LiveCoachingService.analyze()` has been a `// TODO` pointing at a non-existent `/analysis/serve` endpoint with a mismatched `CoachingResult` type since then.
- Phase 7 established manual phase-frame confirmation as the canonical result of a session; Phase 8 established the pattern this phase's coaching-analyze wiring follows (fire a network call at phase-confirmation time, log the result to console, no UI yet).
- `specs/offdevice-pipeline.md` is the authoritative architecture reference for the joint-mapping table and the `/v1/pose` request/response contract shape used here.
- Pre-Pro Cleanup (prior phase) fixed `scripts/verify.sh ios` so it's a clean, trustworthy self-verify oracle going into this phase.
