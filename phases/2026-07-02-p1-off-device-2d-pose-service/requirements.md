# Phase P1 — Off-Device 2D Pose Service — Requirements

## Scope

Stand up a real off-device 2D pose model on the Mac backend, and implement a correctly-typed `LiveCoachingService.analyze()` against the existing (dormant since Phase 4) coaching rule engine's `/v1/analyze` endpoint. This is the first Pro Version phase.

The product has **three permanent, user-selectable modes** — Lite (on-device only), Pro 2D, and Pro 3D (both off-device) — not a Lite MVP that Pro supersedes. Lite mode's only backend dependency is `GET /reference-frames`; it must never invoke off-device pose or coaching compute. Everything built in this phase (`RTMPoseModel`, `POST /v1/pose`, `LiveCoachingService.analyze()`) is **additive and stays at the service layer** — it has no caller in the app yet, and in particular is never wired into the Lite `PhaseReviewView`/comparison flow. In-app wiring lands in a later, mode-gated Pro phase (P5).

## In Scope

- **Backend: `RTMPoseModel` service** (`backend/app/services/pose_model.py`) wrapping `rtmlib.Body` (RTMPose ONNX weights via ONNX Runtime, `device="mps"` on the Mac M3 Max with `CoreMLExecutionProvider`, falling back to `cpu`). Loaded once at process startup, exposed via a FastAPI dependency so tests can override it with a stub.
- **Backend: `POST /v1/pose` endpoint** (`backend/app/routers/pose.py`) — accepts `multipart/form-data` (`frames[]`: JPEG bytes, `timestamps[]`: floats, optional `session_id`), decodes each frame with OpenCV, runs it through `RTMPoseModel`, and returns `PoseResponse { frames: [Frame] }` using the *existing* `Frame`/`Keypoint` models in `backend/app/models.py` — no new wire schema.
- **Backend: COCO-17 → backend keypoint-name mapping**, including deriving `neck` (midpoint of `left_shoulder`/`right_shoulder`) and `pelvis` (midpoint of `left_hip`/`right_hip`) since RTMPose's body model doesn't output them natively but `phases.py`/`angles.py`/`rules.json` expect them. Face keypoints (`nose`, `*_eye`, `*_ear`) are computed by the model but dropped — not part of the backend keypoint schema.
- **Backend: dependency** — add `rtmlib` (confirmed installable, current version `0.0.15`) to `backend/requirements.txt`.
- **Backend: test strategy split** — the default `pytest` run (what `scripts/verify.sh backend` executes) mocks `RTMPoseModel` via dependency override, so it stays fast/deterministic with no model-weight download. A separate test marked to skip unless `RUN_MODEL_INTEGRATION_TESTS=1` is set loads the real `rtmlib.Body` and runs inference against a fixture image, as a runnable (but non-blocking) real-model check.
- **iOS: `VisionJointMapper.swift`** (`App/Services/Pose/`) — translates a Vision-derived `PoseFrame.joints` dictionary (raw `*_joint` key names) into the backend's `right_wrist`/`left_shoulder`/etc. key names, per the mapping table in `specs/offdevice-pipeline.md`. Unmapped/unrecognized Vision joints are dropped.
- **iOS: reconcile `CoachingResult`** in `CoachingService.swift` to mirror the backend's `AnalyzeResponse` — a `Cue` struct (`ruleId`, `phase`, `message`, `severity`) and `summary: String?`, replacing the current placeholder `{ cues: [String]; keyframeTimestamps }`.
- **iOS: implement `LiveCoachingService.analyze()`** — takes translated keypoints for the three confirmed phases, POSTs a JSON body matching the backend's `AnalyzeRequest` (`frames`, optional `session_id`) to `BackendConfig.baseURL`-relative `/v1/analyze`, decodes `AnalyzeResponse`-shaped `CoachingResult`. Service-layer only — no in-app caller this phase.
- **iOS: unit tests** for `VisionJointMapper` and `CoachingResult`/`AnalyzeResponse` decoding. Following the codebase's existing precedent (network fetches, e.g. `ReferenceFrameService`, are validated by Codable-decoding tests, not a URLSession-mocking harness — there is no existing mock pattern to reuse), `LiveCoachingService`'s actual network behavior is validated by the manual integration smoke test against the real backend, not a unit-level mock.

## Out of Scope

- iOS capture and POST of raw JPEG frames to the new `/v1/pose` endpoint. On-device Vision continues to drive frame capture, serve segmentation, and the Phase 7 manual review flow through P1 — nothing in the app yet needs backend-computed keypoints as an input. This wiring happens when P2/P3 actually consume it.
- **iOS: re-deriving keypoints for confirmed phase frames and wiring `LiveCoachingService.analyze()` into the app flow** (e.g. a `CoachingViewModel` fired from `PhaseReviewView.swift`). Deferred to Phase P5 (Pro 2D coaching), where it lands on a mode-gated Pro screen — never on the Lite `PhaseReviewView`/comparison flow. P1 delivers `LiveCoachingService.analyze()` as a dormant, unit-tested service with no caller.
- A coaching-results UI screen displaying cues to the user (Phase P5).
- Rule threshold calibration against real 2D angles (Phase P4) — `rules.json` thresholds are unchanged. Cues returned by `/v1/analyze` in this phase may be noisy or uncalibrated; that's expected and acceptable since nothing user-facing displays them yet.
- Racket/ball object detection (Phase P2).
- Automatic multi-stage serve segmentation replacing the manual Phase 7 review step (Phase P3).
- Persisting cues to SwiftData (extends Phase 10's models; not needed until a UI consumes cues in P5).
- Two-camera/3D pipeline work (Phase P7+).
- Jetson deployment (Phase P16).
- Any mode-selection UI (Lite / Pro 2D / Pro 3D) — not needed until a phase actually has divergent per-mode behavior to gate.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Pose model library | `rtmlib` (`Body` class) wrapping RTMPose ONNX weights via ONNX Runtime | Confirmed installable (`pip index versions rtmlib` → `0.0.15`) and API-inspected: `Body(backend="onnxruntime", device="mps")` auto-downloads OpenMMLab RTMPose weights and returns `(keypoints, scores)`. Concrete, low-risk path to a *real* RTMPose model matching the roadmap's named choice, without hand-sourcing MMPose configs. |
| Default verify-loop tests vs. real model | Mock `RTMPoseModel` via FastAPI dependency override for the default `pytest`/`scripts/verify.sh backend` run; gate a real-model integration test behind `RUN_MODEL_INTEGRATION_TESTS=1` | `/phase`'s self-verify loop has a 3-retry budget and needs deterministic, network-independent results. A first-run model download (weights are tens of MB, fetched from OpenMMLab) shouldn't be a dependency of every verify iteration, but a real-model check should still exist and be runnable on demand. |
| COCO-17 → backend keypoint schema | Derive `neck` and `pelvis` as shoulder/hip midpoints; drop face keypoints (`nose`, `*_eye`, `*_ear`) | RTMPose's body model outputs COCO-17, which lacks `neck`/`pelvis`. The existing `phases.py`/`angles.py`/`rules.json` (built against the Vision-derived schema, which does supply `neck_joint`/`root_joint`) expect those two keys to be present. |
| Where the coaching-analyze call fires | Nowhere yet — `LiveCoachingService` stays at the service layer, unit-tested but uncalled | Preserves Lite-mode isolation: the app has exactly one flow today (`ContentView` → `VideoSourceSelectionView` → pipeline → `PhaseReviewView`), and it *is* the Lite flow. Firing an off-device coaching call from it would inject Pro processing into Lite. In-app wiring is deferred to P5, onto a mode-gated Pro screen. |
| Keypoints for confirmed frames | Deferred to P5 | Re-deriving keypoints at confirmed timestamps only matters once there's a Pro-mode caller to feed; doing it in P1 with no consumer is premature. |
| `/v1/pose` iOS wiring | Deferred to a later phase | Nothing in the app yet needs backend-computed keypoints — on-device Vision still drives capture/segmentation/manual-review through P1. Building the capture/POST path now would have no consumer. |
| `/v1/analyze` request shape | Reuse existing `AnalyzeRequest`/`Frame`/`Keypoint` Pydantic models as-is | No backend schema changes needed — Phase 4 already built and unit-tested this contract; P1 only needed a correctly-typed iOS caller. |
| Off-device code must stay additive and mode-gated | All P1 backend/service work is new code with no modification to any Lite-path file (`PhaseReviewView.swift`, `VideoSourceSelectionView.swift`, `ContentView.swift`, the Lite pipeline/segmentation services) | Encodes the product's three-permanent-modes architecture (see `specs/mission.md` "Capture Modes"): Lite, Pro 2D, and Pro 3D coexist; Pro phases must never overwrite or entangle themselves with the Lite flow. |

## Context

- Phase 4 built the coaching rule engine (`rules.json`, `phases.py`, `rules.py`) and the `/v1/analyze` endpoint, unit-tested standalone with pytest, but never called from the iOS app — `LiveCoachingService.analyze()` has been a `// TODO` pointing at a non-existent `/analysis/serve` endpoint with a mismatched `CoachingResult` type since then.
- Phase 7 established manual phase-frame confirmation as the canonical result of a session; Phase 8 established the pattern a later phase's coaching-analyze wiring will follow (fire a network call at phase-confirmation time, log the result to console, no UI yet) — but on a Pro-gated screen, not on the Lite `PhaseReviewView` itself.
- `specs/offdevice-pipeline.md` is the authoritative architecture reference for the joint-mapping table and the `/v1/pose` request/response contract shape used here.
- Pre-Pro Cleanup (prior phase) fixed `scripts/verify.sh ios` so it's a clean, trustworthy self-verify oracle going into this phase.
- **Three-mode product architecture:** the app has three permanent, user-selectable modes — Lite (on-device Vision, manual frame correction, phone + tripod only), Pro 2D (off-device pose + racket/ball detection, automatic segmentation, rule-based coaching, Jetson-hosted), and Pro 3D (same as Pro 2D plus stereo triangulation for 3D angles). Lite is not superseded by Pro — all three coexist. See the "Capture Modes" section of `specs/mission.md` and the isolation rule in `specs/offdevice-pipeline.md` for the full framing this phase must respect.
