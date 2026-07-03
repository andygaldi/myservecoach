# Phase P2 — Plan

> **Lite-isolation note:** everything in this phase is backend-only. No task group touches any file under `App/` — there is no iOS surface for P2. `ObjectDetectionModel` and `POST /v1/detect` are dormant Pro-mode services with no caller; consumption happens starting in Phase P4.

## Group 1 — Backend: Object Detection Model Service (surface: `backend`)

1. Add `ultralytics` to `backend/requirements.txt` (verified installable, current `8.4.86`, pin `>=8.4,<8.5`); `pip install -r backend/requirements.txt` in `backend/.venv`.
2. Create `backend/app/services/object_detection.py`:
   - `DETECTION_CLASS_MAP: dict[int, str] = {32: "ball", 38: "racket"}` — COCO class id → backend label string, per `coco.yaml` (`32: sports ball`, `38: tennis racket`).
   - `def map_yolo_results_to_detections(boxes, width: int, height: int, confidence_threshold: float) -> list[Detection]:` — a standalone, pure function (no `ultralytics.YOLO` dependency at call time) that iterates `boxes.cls`, `boxes.conf`, `boxes.xyxy` (ultralytics `Boxes` interface — each is an array-like of length N); for each detection: skip if `int(cls)` not in `DETECTION_CLASS_MAP`; skip if `float(conf) < confidence_threshold`; normalize `x_min, y_min, x_max, y_max` by dividing by `width`/`height`; y-flip each y-coordinate (`1.0 - y/height`) to match `map_coco17_to_backend_schema`'s Vision-derived convention (bottom-left origin, y-up), then re-sort so `y_min < y_max` still holds post-flip (the flip inverts which raw value is smaller); build `Detection(label=DETECTION_CLASS_MAP[int(cls)], confidence=float(conf), bbox=BoundingBox(x_min=..., y_min=..., x_max=..., y_max=...))`. Returns `[]` if `boxes` is empty (no qualifying detections).
   - `class ObjectDetectionModel:` — `__init__(self, device: str | None = None, weights: str = "yolo11n.pt", confidence_threshold: float = 0.25)`; `device` defaults to the `DETECTION_MODEL_DEVICE` env var, itself defaulting to `"cpu"` (mirrors `RTMPoseModel`'s `POSE_MODEL_DEVICE` pattern; set `DETECTION_MODEL_DEVICE=mps` locally on the Mac for GPU acceleration). Lazily constructs `self._model = YOLO(self.weights)` on first `infer()` call, not in `__init__` — avoids paying model-load/download cost when the class is merely imported (e.g. by tests that override the dependency).
     ```python
     def infer(self, image: np.ndarray) -> list[Detection]:
         if self._model is None:
             self._model = YOLO(self.weights)
         results = self._model.predict(image, device=self.device, conf=self.confidence_threshold, verbose=False)
         h, w = image.shape[:2]
         return map_yolo_results_to_detections(results[0].boxes, w, h, self.confidence_threshold)
     ```
   - `def get_object_detection_model() -> ObjectDetectionModel:` — `@lru_cache(maxsize=1)`-wrapped FastAPI dependency (module-level singleton, constructed lazily on first request).
3. Write `backend/tests/test_object_detection.py`: unit tests for `map_yolo_results_to_detections` using a hand-built stub object exposing `.cls`, `.conf`, `.xyxy` as numpy arrays (no `ultralytics.YOLO` involved) — assert a `tennis racket` (class 38) detection maps to `label="racket"` with correctly normalized+y-flipped bbox and `y_min < y_max`; assert a `sports ball` (class 32) detection maps to `label="ball"`; assert a `person` (class 0) or other non-racket/ball class is dropped from the result; assert a detection below `confidence_threshold` is dropped; assert an empty `boxes` input produces `[]` without raising.
4. Run `pytest backend/tests/test_object_detection.py -v` — confirm green. Confirm via `grep`/manual check that this test path never constructs a real `YOLO(...)` model (no network/weight-download dependency in the default suite).

## Group 2 — Backend: `POST /v1/detect` Endpoint (surface: `backend`)

5. Add to `backend/app/models.py`, next to the existing `PoseResponse`:
   ```python
   class BoundingBox(BaseModel):
       x_min: float
       y_min: float
       x_max: float
       y_max: float


   class Detection(BaseModel):
       label: str
       confidence: float
       bbox: BoundingBox


   class DetectionFrame(BaseModel):
       timestamp: float
       detections: list[Detection]


   class DetectResponse(BaseModel):
       frames: list[DetectionFrame]
   ```
6. Create `backend/app/routers/detect.py`, mirroring `pose.py`'s structure and error handling exactly:
   ```python
   from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

   from app.models import DetectionFrame, DetectResponse
   from app.services.object_detection import ObjectDetectionModel, get_object_detection_model
   from app.services.pose_model import decode_image

   router = APIRouter()


   @router.post("/detect", response_model=DetectResponse)
   async def detect(
       frames: list[UploadFile] = File(...),
       timestamps: list[float] = Form(...),
       session_id: str | None = Form(None),
       detection_model: ObjectDetectionModel = Depends(get_object_detection_model),
   ) -> DetectResponse:
   ```
   - Raise `HTTPException(400, "frames and timestamps must be the same length")` if lengths mismatch.
   - For each `UploadFile`: `raw = await f.read()`; `image = decode_image(raw)`; raise `HTTPException(400, "invalid image data")` if `image is None`.
   - `detections = detection_model.infer(image)`; append `DetectionFrame(timestamp=t, detections=detections)`.
   - Return `DetectResponse(frames=[...])`.
7. Register in `backend/app/main.py`: add `detect` to `from app.routers import analyze, detect, pose, reference_frames` and `app.include_router(detect.router, prefix="/v1")`.
8. Write `backend/tests/test_detect_endpoint.py` (httpx `AsyncClient` + `ASGITransport` against `app.main.app`, following `test_pose_endpoint.py`'s style):
   - Override `get_object_detection_model` via `app.dependency_overrides[get_object_detection_model] = lambda: StubDetectionModel()` where `StubDetectionModel.infer` returns a fixed one-detection list (`[Detection(label="racket", confidence=0.9, bbox=BoundingBox(x_min=0.1, y_min=0.1, x_max=0.3, y_max=0.3))]`) — no real model load.
   - Generate synthetic JPEG bytes via `cv2.imencode(".jpg", np.zeros((64, 64, 3), dtype=np.uint8))`, matching `test_pose_endpoint.py`'s approach.
   - Assert `POST /v1/detect` with 2 synthetic frames + 2 timestamps returns HTTP 200, `len(frames) == 2`, timestamps round-trip correctly, and each frame's `detections` matches the stub output.
   - Assert HTTP 400 when `timestamps` has a different length than `frames`.
   - Assert HTTP 400 when a frame's bytes aren't a valid image.
9. Run `pytest backend/` — confirm all tests (including pre-existing ones) still pass, with no real model load anywhere in the default run.

## Group 3 — Backend: Opt-In Real-Model Integration Check (surface: `backend`)

10. Write `backend/tests/test_object_detection_integration.py`:
    ```python
    @pytest.mark.skipif(
        not os.environ.get("RUN_MODEL_INTEGRATION_TESTS"),
        reason="opt-in: downloads real YOLO11n COCO weights on first run",
    )
    def test_real_yolo_inference_runs():
        model = ObjectDetectionModel()
        image = np.zeros((480, 640, 3), dtype=np.uint8)
        result = model.infer(image)
        assert isinstance(result, list)
        # No racket/ball in a blank synthetic image, so an empty list is an
        # acceptable (and expected) result here — the assertion is that
        # inference ran without raising, not that anything was detected.
    ```
11. Manually run once and record the outcome in `validation.md` notes: `cd backend && RUN_MODEL_INTEGRATION_TESTS=1 pytest tests/test_object_detection_integration.py -v` — confirm weights download successfully and inference completes without error. Note approximate first-run download time/size (mirrors P1's recorded note for `rtmlib`'s weights).

## Group 4 — Integration Smoke Test (manual, backend-only)

12. Start the backend locally: `cd backend && uvicorn app.main:app --reload --host 0.0.0.0` (optionally `DETECTION_MODEL_DEVICE=mps` for GPU acceleration on the Mac M3 Max).
13. `curl -F "frames=@sample.jpg" -F "timestamps=0.5" http://localhost:8000/v1/detect` with any local JPEG (ideally containing a racket or ball) — confirm HTTP 200 with a well-formed `frames` array (detections may be empty if no racket/ball is in the sample image; the check is a valid response shape, not detection accuracy). Note first-call latency (model weight download) vs. subsequent calls.
14. Run `scripts/verify.sh backend` — confirm the full pytest suite (including the new `test_object_detection.py`/`test_detect_endpoint.py`) passes with zero failures.
15. Confirm no iOS files were touched at all this phase: `git diff --name-only develop...HEAD` contains no changes under `App/`.
