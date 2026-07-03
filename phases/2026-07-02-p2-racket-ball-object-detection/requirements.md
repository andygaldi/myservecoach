# Phase P2 — Racket & Ball Object Detection — Requirements

## Scope

Stand up an off-device object detector on the Mac backend for racket and ball, mirroring Phase P1's pattern of a lazily-loaded model service behind a dedicated FastAPI endpoint. Vision never supported racket detection — this is net-new capability that Phase P4 will later combine with P1's pose keypoints to detect the six Kovacs key frames automatically. This is a backend-only phase; no iOS surface.

The product has **three permanent, user-selectable modes** — Lite (on-device only), Pro 2D, and Pro 3D (both off-device). Everything built in this phase (`ObjectDetectionModel`, `POST /v1/detect`) is **additive and stays at the service layer** — it has no caller in the app yet, and is never wired into the Lite `PhaseReviewView`/comparison flow. In-app consumption happens indirectly via Phase P4's segmentation logic and, later, Pro-mode screens.

## In Scope

- **Backend: `ObjectDetectionModel` service** (`backend/app/services/object_detection.py`) wrapping `ultralytics.YOLO` with off-the-shelf COCO-pretrained weights (`yolo11n.pt`) — no fine-tuning. Loaded once, lazily, on first `infer()` call; exposed via a FastAPI dependency so tests can override it with a stub.
- **Backend: `POST /v1/detect` endpoint** (`backend/app/routers/detect.py`) — accepts the same `multipart/form-data` contract as `/v1/pose` (`frames[]`: JPEG bytes, `timestamps[]`: floats, optional `session_id`), decodes each frame with OpenCV (reusing `decode_image` from `pose_model.py`), runs it through `ObjectDetectionModel`, and returns `DetectResponse { frames: [DetectionFrame] }` using new Pydantic models in `backend/app/models.py`.
- **Backend: COCO class filtering** — YOLO's stock COCO weights already include `sports ball` (class 32) and `tennis racket` (class 38) as native classes. Detections are filtered to only these two classes, relabeled to the backend's `ball`/`racket` label strings; all other 78 COCO classes (including `person`) are dropped from the response.
- **Backend: coordinate convention** — bounding boxes normalized to 0–1 and y-flipped to match the existing `Keypoint` schema's Vision-derived convention (bottom-left origin, y increasing upward), the same convention `map_coco17_to_backend_schema` established in P1. This keeps pose and detection outputs on a consistent axis so P4 can combine them without a coordinate mismatch.
- **Backend: dependency** — add `ultralytics` (confirmed installable, current version `8.4.86`) to `backend/requirements.txt`.
- **Backend: test strategy split** — the default `pytest` run (what `scripts/verify.sh backend` executes) mocks `ObjectDetectionModel` via dependency override, so it stays fast/deterministic with no model-weight download. A separate test marked to skip unless `RUN_MODEL_INTEGRATION_TESTS=1` is set loads the real `ultralytics.YOLO` model and runs inference against a synthetic image, as a runnable (but non-blocking) real-model check — mirroring P1's `RUN_MODEL_INTEGRATION_TESTS` gate for `RTMPoseModel`.

## Out of Scope

- **Fine-tuning YOLO on tennis-specific footage** (TTNet/SportsMOT datasets + self-collected court footage, per `specs/offdevice-pipeline.md`). No labeled tennis dataset exists in this repo yet; off-the-shelf COCO weights already cover the two needed classes (`sports ball`, `tennis racket`) well enough to unblock P4's segmentation work. Revisit fine-tuning once real-world detection quality is assessed (a natural extension of Phase P3's benchmark tooling) and a labeled dataset exists.
- **iOS capture/POST path to `/v1/detect`.** On-device Vision continues to drive frame capture, serve segmentation, and the Phase 7 manual review flow through P2 — nothing in the app yet needs backend-computed detections as an input.
- **Combining pose + racket/ball signals into segmentation logic** (Phase P4) — this phase only produces the raw detection signal; consuming it to detect the six Kovacs key frames is P4's job.
- **Any change to `backend/app/engine/phases.py` or `rules.json`.**
- **Any UI** — no results screen, no overlay, nothing user-facing.
- **Multi-object tracking across frames** (e.g., a persistent racket/ball ID or trajectory). Each frame's detections are independent; no cross-frame association.
- **Ball/racket detection accuracy tuning or benchmarking against real footage** — that's Phase P3's job (CV Model Performance Baseline), which explicitly benchmarks both P1's pose model and P2's object detector together.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Object detector model | `ultralytics` YOLO11n, off-the-shelf COCO-pretrained weights (`yolo11n.pt`) — no fine-tuning this phase | Confirmed installable (`pip index versions ultralytics` → `8.4.86`) and class-inspected (`coco.yaml`: class 32 = `sports ball`, class 38 = `tennis racket`). COCO already covers both classes P2 needs, avoiding the substantial separate effort of assembling and labeling a tennis-specific dataset. Mirrors P1's "use an existing, off-the-shelf model" precedent (`rtmlib`'s pretrained RTMPose). |
| YOLO variant | YOLO11n over YOLOv8n | Newer Ultralytics-native nano model with a better accuracy/speed tradeoff; both are offered as options in `specs/offdevice-pipeline.md`. |
| Endpoint design | New `POST /v1/detect` endpoint, not folded into `/v1/pose` | Mirrors P1's dedicated-service-plus-dedicated-router pattern; keeps the pose and detection models independently testable, cacheable, and evolvable (e.g. either could later be swapped or fine-tuned without touching the other's contract). |
| Class filtering | Only `sports ball`→`ball` and `tennis racket`→`racket` are kept; the other 78 COCO classes are dropped from the response | Roadmap explicitly scopes P2 to racket and ball only. |
| Coordinate convention | Bounding boxes normalized 0–1, y-flipped to match Vision's bottom-left-origin/y-up convention (same fix P1's deep review applied to `map_coco17_to_backend_schema`) | Keeps detection output on the same axis convention as pose keypoints so P4 can combine both signals without a silent coordinate mismatch. |
| Confidence threshold | Default `conf=0.25` (ultralytics' own default), configurable via constructor param | Standard first-pass threshold; avoids over-filtering real-but-lower-confidence racket detections before any real-footage tuning (deferred to P3). |
| Test strategy | Mock `ObjectDetectionModel` via FastAPI dependency override for the default `pytest`/`scripts/verify.sh backend` run; gate a real-model integration test behind `RUN_MODEL_INTEGRATION_TESTS=1` | Mirrors P1's `RTMPoseModel` test-split exactly — `/phase`'s self-verify loop needs deterministic, network-independent results; a first-run model download (YOLO11n weights, tens of MB) shouldn't gate every verify iteration. |
| In-app wiring | None — service + endpoint only, no iOS caller, no consumer anywhere in the app | Nothing needs racket/ball detections as an input yet; P4 is the first consumer (combining pose + detection signals into six-frame segmentation). Mirrors P1's dormant-service pattern exactly. |
| Off-device code must stay additive and mode-gated | All P2 work is new backend code with no modification to any Lite-path file or any iOS file at all | Encodes the product's three-permanent-modes architecture (see `specs/mission.md` "Capture Modes"): Pro-only phases must never entangle themselves with the Lite flow. |

## Context

- Phase P1 built the first off-device model service (`RTMPoseModel`) behind `POST /v1/pose`, establishing the pattern this phase reuses verbatim: a lazily-loaded model wrapped in a class, exposed via an `lru_cache`d FastAPI dependency, behind a router accepting the same `multipart/form-data` `frames[]`/`timestamps[]`/`session_id` contract, with a mocked default test suite and an opt-in `RUN_MODEL_INTEGRATION_TESTS=1`-gated real-model check.
- `specs/roadmap.md` describes P2 as "YOLO-class object detector on the Mac for the racket (and ball) ... Returns bounding-box positions per frame alongside keypoints, giving the segmentation and phase-detection engines the racket-position signal they need" — the segmentation consumer is Phase P4, not this phase.
- `specs/offdevice-pipeline.md`'s Object Detection section lists YOLOv8n/YOLOv11n fine-tuned on tennis footage as the target end-state; this phase deliberately ships the off-the-shelf-weights subset of that (both classes needed already exist in COCO), deferring the fine-tuning investment until real-footage benchmarking (P3) shows it's needed.
- Pre-Pro Cleanup and P1 both established `scripts/verify.sh backend`/`scripts/verify.sh ios` as clean, trustworthy self-verify oracles going into this phase.
- **Three-mode product architecture:** the app has three permanent, user-selectable modes — Lite (on-device Vision, manual frame correction), Pro 2D (off-device pose + racket/ball detection, automatic segmentation, rule-based coaching), and Pro 3D (adds stereo triangulation). Lite is not superseded by Pro — all three coexist. This phase is purely backend infrastructure for the Pro 2D/3D pipeline and touches no Lite-path or iOS file at all.
