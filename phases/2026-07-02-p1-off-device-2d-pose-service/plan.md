# Phase P1 — Plan

> **Lite-isolation note:** `LiveCoachingService` is implemented and unit-tested in this phase but has **no in-app caller**. It is a dormant Pro-mode service — wiring it into a Pro-gated coaching screen happens in Phase P5, behind mode selection. It must never be called from the Lite flow (`PhaseReviewView.swift` or anything reachable from it). No task group in this plan modifies `PhaseReviewView.swift` or any other Lite-path file.

## Group 1 — Backend: RTMPose Model Service (surface: `backend`)

1. Add `rtmlib` to `backend/requirements.txt` (verified installable, current `0.0.15`); `pip install -r backend/requirements.txt` in `backend/.venv`.
2. Create `backend/app/services/__init__.py` (empty) and `backend/app/services/pose_model.py`:
   - `COCO17_KEYPOINT_NAMES: list[str]` — the 17 COCO joint names in index order (`nose, left_eye, right_eye, left_ear, right_ear, left_shoulder, right_shoulder, left_elbow, right_elbow, left_wrist, right_wrist, left_hip, right_hip, left_knee, right_knee, left_ankle, right_ankle`).
   - `def map_coco17_to_backend_schema(keypoints: np.ndarray, scores: np.ndarray, width: int, height: int) -> dict[str, Keypoint]:` — a standalone, pure function (no `rtmlib` dependency at call time) that: normalizes each `(x, y)` pixel pair by dividing by `width`/`height` (matching the existing 0–1 normalized convention `angles.py`'s `joint_xy`/`keypoint_y` docstrings assume); builds `right_wrist`, `left_shoulder`, etc. from the COCO-17 indices; derives `neck` = midpoint of `left_shoulder`/`right_shoulder` (confidence = `min` of the two); derives `pelvis` = midpoint of `left_hip`/`right_hip` (confidence = `min` of the two); drops `nose`/`left_eye`/`right_eye`/`left_ear`/`right_ear`. Returns `{}` if `keypoints` is empty (no person detected).
   - `class RTMPoseModel:` — `__init__(self, device: str | None = None, backend: str = "onnxruntime")`; `device` defaults to the `POSE_MODEL_DEVICE` env var, itself defaulting to `"cpu"` (safe everywhere; set `POSE_MODEL_DEVICE=mps` locally on the Mac for `CoreMLExecutionProvider` acceleration). Lazily constructs `self._body = rtmlib.Body(backend=backend, device=self.device)` on first `infer()` call, not in `__init__` — avoids paying model-load/download cost when the class is merely imported (e.g. by tests that override the dependency).
     ```python
     def infer(self, image: np.ndarray) -> dict[str, Keypoint]:
         if self._body is None:
             self._body = Body(backend=self.backend, device=self.device)
         keypoints, scores = self._body(image)
         if len(keypoints) == 0:
             return {}
         h, w = image.shape[:2]
         return map_coco17_to_backend_schema(keypoints[0], scores[0], w, h)
     ```
   - `def get_pose_model() -> RTMPoseModel:` — `@lru_cache(maxsize=1)`-wrapped FastAPI dependency (module-level singleton, constructed lazily on first request).
3. Write `backend/tests/test_pose_model.py`: unit tests for `map_coco17_to_backend_schema` using hand-built numpy `keypoints`/`scores` arrays (no `rtmlib.Body` involved) — assert all 12 direct-mapped joint names appear with correct `x`/`y`/`confidence`; assert `neck` and `pelvis` are correctly derived midpoints with `min`-confidence; assert face keypoints are absent from the result; assert an all-zero-confidence input still produces well-formed (if useless) output rather than raising.
4. Run `pytest backend/tests/test_pose_model.py -v` — confirm green. Confirm via `grep`/manual check that this test path never constructs `rtmlib.Body` (no network/model-download dependency in the default suite).

## Group 2 — Backend: `POST /v1/pose` Endpoint (surface: `backend`)

5. Add `class PoseResponse(BaseModel): frames: list[Frame]` to `backend/app/models.py`, next to the existing `AnalyzeResponse`.
6. Create `backend/app/routers/pose.py`:
   ```python
   @router.post("/pose", response_model=PoseResponse)
   async def pose(
       frames: list[UploadFile] = File(...),
       timestamps: list[float] = Form(...),
       session_id: str | None = Form(None),
       pose_model: RTMPoseModel = Depends(get_pose_model),
   ) -> PoseResponse:
   ```
   - Raise `HTTPException(400, "frames and timestamps must be the same length")` if lengths mismatch.
   - For each `UploadFile`: `raw = await f.read()`; `image = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)`; raise `HTTPException(400, "invalid image data")` if `image is None`.
   - `keypoints = pose_model.infer(image)`; append `Frame(timestamp=t, keypoints=keypoints)`.
   - Return `PoseResponse(frames=[...])`.
7. Register in `backend/app/main.py`: `from app.routers import analyze, pose, reference_frames` and `app.include_router(pose.router, prefix="/v1")`.
8. Write `backend/tests/test_pose_endpoint.py` (httpx `AsyncClient` + `ASGITransport` against `app.main.app`, following `test_reference_frames.py`'s style):
   - Override `get_pose_model` via `app.dependency_overrides[get_pose_model] = lambda: StubPoseModel()` where `StubPoseModel.infer` returns a fixed one-joint `{"right_wrist": Keypoint(x=0.5, y=0.5, confidence=0.9)}` dict — no real model load.
   - Generate synthetic JPEG bytes via `cv2.imencode(".jpg", np.zeros((64, 64, 3), dtype=np.uint8))` (same synthetic-asset approach as `test_calibration_report.py`).
   - Assert `POST /v1/pose` with 2 synthetic frames + 2 timestamps returns HTTP 200, `len(frames) == 2`, and timestamps round-trip correctly.
   - Assert HTTP 400 when `timestamps` has a different length than `frames`.
   - Assert HTTP 400 when a frame's bytes aren't a valid image.
9. Run `pytest backend/` — confirm all tests (including pre-existing ones) still pass, with no real model load anywhere in the default run.

## Group 3 — Backend: Opt-In Real-Model Integration Check (surface: `backend`)

10. Write `backend/tests/test_pose_model_integration.py`:
    ```python
    @pytest.mark.skipif(
        not os.environ.get("RUN_MODEL_INTEGRATION_TESTS"),
        reason="opt-in: downloads real RTMPose ONNX weights on first run",
    )
    def test_real_rtmpose_inference_runs():
        model = RTMPoseModel()
        image = np.zeros((480, 640, 3), dtype=np.uint8)
        result = model.infer(image)
        assert isinstance(result, dict)
        # No person in a blank synthetic image, so an empty dict is an acceptable
        # (and expected) result here — the assertion is that inference ran without
        # raising, not that keypoints were found.
    ```
11. Manually run once and record the outcome in `validation.md` notes: `cd backend && RUN_MODEL_INTEGRATION_TESTS=1 pytest tests/test_pose_model_integration.py -v` — confirm weights download successfully and inference completes without error. Note approximate first-run download time/size.

## Group 4 — iOS: VisionJointMapper & Backend-Schema Types (surface: `ios`)

12. Create `App/Models/BackendFrame.swift`:
    ```swift
    struct BackendKeypoint: Codable, Sendable {
        let x: Float
        let y: Float
        let confidence: Float
    }

    struct BackendFrame: Codable, Sendable {
        let timestamp: Double
        let keypoints: [String: BackendKeypoint]
    }
    ```
13. Create `App/Services/Pose/VisionJointMapper.swift`:
    ```swift
    enum VisionJointMapper {
        static let jointNameMap: [String: String] = [
            "right_wrist_joint": "right_wrist",
            "left_wrist_joint": "left_wrist",
            "right_elbow_joint": "right_elbow",
            "left_elbow_joint": "left_elbow",
            "right_shoulder_1_joint": "right_shoulder",
            "left_shoulder_1_joint": "left_shoulder",
            "right_hip_joint": "right_hip",
            "left_hip_joint": "left_hip",
            "right_knee_joint": "right_knee",
            "left_knee_joint": "left_knee",
            "right_ankle_joint": "right_ankle",
            "left_ankle_joint": "left_ankle",
            "neck_joint": "neck",
            "root_joint": "pelvis",
        ]

        static func translate(_ frame: PoseFrame) -> BackendFrame {
            var keypoints: [String: BackendKeypoint] = [:]
            for (visionKey, point) in frame.joints {
                guard let backendKey = jointNameMap[visionKey] else { continue }
                keypoints[backendKey] = BackendKeypoint(x: point.x, y: point.y, confidence: point.confidence)
            }
            return BackendFrame(timestamp: frame.timestamp, keypoints: keypoints)
        }
    }
    ```
14. In `App/Services/Coaching/CoachingService.swift`, replace the placeholder `CoachingResult` with:
    ```swift
    struct Cue: Codable, Sendable {
        let ruleId: String
        let phase: String
        let message: String
        let severity: String

        enum CodingKeys: String, CodingKey {
            case ruleId = "rule_id"
            case phase, message, severity
        }
    }

    struct CoachingResult: Codable, Sendable {
        let cues: [Cue]
        let summary: String?
    }
    ```
15. Write `MyServeCoachTests/VisionJointMapperTests.swift`: construct a `PoseFrame` with all 14 mapped keys plus one unmapped key (e.g. `"top_head_joint"`); assert `translate` produces exactly the 14 expected backend keys (unmapped key dropped) with `x`/`y`/`confidence` passed through unchanged. Write `MyServeCoachTests/CoachingResultDecodingTests.swift`: decode a fixture JSON string shaped like the backend's actual `AnalyzeResponse` (`rule_id`/`phase`/`message`/`severity`/`summary`) into `CoachingResult` and assert field values match.

## Group 5 — iOS: `LiveCoachingService.analyze()` (surface: `ios`)

16. Update `CoachingServiceProtocol` in `CoachingService.swift`:
    ```swift
    protocol CoachingServiceProtocol {
        func analyze(frames: [BackendFrame], sessionId: String?) async throws -> CoachingResult
    }
    ```
17. Rewrite `LiveCoachingService`:
    - `init(baseURL: URL = BackendConfig.baseURL)` — matches `ReferenceFrameService`'s constructor pattern (no more hardcoded `localhost:8000/analysis/serve`).
    - `analyze(frames:sessionId:)`: builds a `URLRequest` to `baseURL.appendingPathComponent("v1/analyze")`, `httpMethod = "POST"`, `Content-Type: application/json`; encodes a request body struct `{ frames: [BackendFrame], session_id: String? }` (explicit `CodingKeys` for `session_id`, consistent with the rest of the codebase's explicit-mapping style rather than a blanket `keyEncodingStrategy`); performs the request via `URLSession.shared.data(for:)`; decodes the response body as `CoachingResult`.
    - On a non-2xx HTTP status, throw `CoachingServiceError.networkError("HTTP \(status)")`. On decode failure, throw `CoachingServiceError.decodingFailed`.
18. There is no existing URLSession-mocking test pattern in this codebase (`ReferenceFrameService`'s live fetch is likewise untested at the network layer — only its Codable types are, in `ReferenceFrameCodableTests.swift`). Follow that same precedent rather than introducing a new mocking harness: `CoachingResultDecodingTests.swift` (Group 4, task 15) covers response decoding; `LiveCoachingService`'s actual network behavior is validated by the Group 7 manual integration smoke test against the real running backend. No `CoachingServiceTests.swift` network-mock file is needed.

## Group 6 — Integration Smoke Test (manual, both surfaces)

19. Start the backend locally: `cd backend && uvicorn app.main:app --reload --host 0.0.0.0` (optionally `POSE_MODEL_DEVICE=mps` for CoreML acceleration on the Mac M3 Max).
20. `curl -F "frames=@sample.jpg" -F "timestamps=0.5" http://localhost:8000/v1/pose` with any local JPEG — confirm HTTP 200 with a well-formed `frames` array (keypoints may be empty if no person is in the sample image; the check is a valid response shape, not detection accuracy). Note first-call latency (model weight download) vs. subsequent calls.
21. Run `scripts/verify.sh backend` — confirm the full pytest suite (including the new `test_pose_model.py`/`test_pose_endpoint.py`) passes with zero failures.
22. Run `scripts/verify.sh ios` — confirm the full `xcodebuild test` suite (including the new `VisionJointMapperTests`/`CoachingResultDecodingTests`) passes with zero failures.
23. Confirm no Lite-path files were touched: `git diff --name-only develop...HEAD` contains no changes under `App/Views/PhaseReviewView.swift`, `App/Views/VideoSourceSelectionView.swift`, `App/Views/ContentView.swift`, or the Lite pipeline/segmentation services.
