# Off-Device Pose Pipeline

Architecture reference for the off-device pipeline that underpins the Pro Version (roadmap phases P1–P15). The final phase (P16) migrates the pipeline to the Jetson Orin Nano for court portability.

---

## Development Host vs. Deployment Target

The pipeline is **host-agnostic** — the same model weights, the same `backend/` FastAPI code, and the same OpenCV calibration/triangulation logic run identically on both hosts. Only the model-serving runtime and camera I/O differ.

| | Development host | Deployment target |
|---|---|---|
| **Host** | Mac M3 Max (macOS) | NVIDIA Jetson Orin Nano (JetPack 6) |
| **Model runtime** | PyTorch-MPS / CoreML / ONNX Runtime | TensorRT |
| **Stereo cameras** | 2× USB webcams | 2× MIPI CSI-2 cameras |
| **Camera sync** | Software timestamp (USB) | Hardware sync via CSI / V4L2 |
| **Network** | Home/local Wi-Fi (iPhone → Mac LAN IP) | Court Wi-Fi or Jetson-broadcast hotspot |
| **Phase** | P1–P15 (no hardware purchase required) | P16 (when portability is needed) |

The Mac is already the backend dev server for the Lite MVP (`BackendConfig.swift` hardcodes a Mac LAN IP), so **P1 starts immediately with no new hardware**. The Jetson is purchased and configured only when you want untethered on-court use (P16 — deferrable to any point).

---

## Capture Tiers — Single-Camera 2D vs. Two-Camera 3D

The Pro Version supports two user-selectable capture tiers chosen at session setup:

| | Single-camera (2D) | Two-camera (3D) |
|---|---|---|
| **Camera setup** | iPhone only | iPhone (controller/display) + 2× USB webcams on Mac (or CSI cameras on Jetson) |
| **Pose angles** | 2D joint angles (projection-limited) | True 3D biomechanical angles via triangulation |
| **Rule thresholds** | 2D-calibrated (`rules.json`, P4) | 3D-calibrated (`rules.json` precision-tier variant, P9) |
| **Roadmap phases** | Foundation P1–P3; coaching P4–P6 | Foundation P7–P8; coaching P9–P11 |
| **First available** | P6 | P11 |

The single-camera 2D path ships first. The two-camera 3D path extends it — both tiers persist in the product. `backend/app/engine/angles.py` retains the 2D `compute_angle` **and** adds `compute_angle_3d` (see P8); rules select the angle source per the active tier.

---

## Hardware

### Development host — Mac M3 Max

| Attribute | Detail |
|---|---|
| CPU | Apple M3 Max (16-core ARM) |
| GPU / ANE | 40-core GPU + 16-core Neural Engine; Metal/MPS |
| RAM | Unified memory (ideal for large pose models) |
| ML runtime | PyTorch-MPS, CoreML (`.mlpackage`), ONNX Runtime with CoreML EP |
| Stereo input | 2× USB webcams (any 1080p30 UVC-compliant) |

### Deployment target — NVIDIA Jetson Orin Nano Dev Kit

| Attribute | Detail |
|---|---|
| GPU | 1024-core NVIDIA Ampere; CUDA 11.4+ |
| AI performance | 40 TOPS (8 GB model) |
| RAM | 8 GB LPDDR5 |
| Storage | NVMe SSD (model weights + video buffer) |
| Power | 7–15 W; battery-powerable via USB-C PD bank |
| Portability | ~140 g module; mounts on a small tripod at courtside |
| Camera ports | 2× MIPI CSI-2 (stereo rig); USB 3.2 for additional cameras |
| Software | JetPack 6 (Ubuntu 22.04 + CUDA/TensorRT/cuDNN) |

**Why Jetson over Raspberry Pi 5 + AI HAT+:** The Jetson has a real CUDA GPU — PyTorch and TensorRT models run natively without format conversion. The custom 3D triangulation math and biomechanics angle computation run on the same device without the bottleneck that a Pi + Hailo NPU creates (Hailo requires custom HEF model compilation; all non-Hailo code still runs on the Pi's weak CPU). The Jetson is more expensive (~$249) but meaningfully more flexible for the research-grade work needed here.

---

## Network Topology

### Development (iPhone → Mac, P1–P15)

```
iPhone (capture + display)
        │
        │  local Wi-Fi (iPhone and Mac on same network)
        ▼
Mac M3 Max
  ├── FastAPI backend (already the Lite MVP dev server)
  ├── 2D pose model (ONNX Runtime / PyTorch-MPS)
  ├── YOLO object detector (ONNX Runtime / PyTorch-MPS)
  └── 2× USB webcams (stereo rig, P7+)
```

- `BackendConfig.swift` already hardcodes the Mac's LAN IP — no change needed for P1.
- A future enhancement can add mDNS / Bonjour discovery so the IP doesn't need to be updated manually.

### Deployment (iPhone → Jetson, P16)

```
iPhone (controller + display)
        │
        │  court Wi-Fi or Jetson hotspot
        ▼
Jetson Orin Nano (courtside tripod)
  ├── FastAPI backend (same code, TensorRT runtime)
  ├── 2D pose model (TensorRT)
  ├── YOLO object detector (TensorRT)
  └── 2× CSI cameras (stereo rig)
```

- Only `BackendConfig.swift` needs updating: Mac LAN IP → Jetson address (P16).
- No backend logic, model weights, or iOS app changes.

---

## Model Choices

### 2D Pose Estimation

| Option | Mac runtime | Jetson runtime | Notes |
|---|---|---|---|
| **RTMPose** (MMPose) | ONNX Runtime / PyTorch-MPS | TensorRT (ONNX export) | Best accuracy on single-person sports; **top recommendation** |
| YOLO11-Pose | ONNX Runtime / PyTorch-MPS | TensorRT | Single-model detect+pose; simpler deployment; slightly lower accuracy on partial occlusion |
| OpenPose | PyTorch-MPS | TensorRT | Older, heavier; not recommended for new work |

Target: **≥20 FPS** on 720p input. RTMPose-m achieves this on both the M3 Max and the Jetson Orin Nano.

Keypoint output: 17 COCO body keypoints. See the joint-name mapping table below.

### Object Detection (Racket & Ball)

YOLOv8n or YOLOv11n fine-tuned on tennis footage (racket + ball classes). Fine-tuning dataset: public tennis action datasets (TTNet, SportsMOT tennis subset) + self-collected court footage. ONNX export on Mac; TensorRT export for Jetson — same training, same weights.

### Background Robustness

No dedicated background-removal model needed initially — off-device pose models trained on diverse sports data are already substantially more robust than on-device Vision under varied court conditions. If court lines or fence posts prove problematic after real-world testing, add a lightweight segmentation step (SAM2 or MediaPipe Selfie Segmentation) as optional preprocessing.

---

## Data Contract

### Current state (Lite MVP)

The only live iOS→backend call is `GET /reference-frames`. The coaching POST path is stubbed:
- `App/Services/Coaching/CoachingService.swift` `LiveCoachingService.analyze()` is `// TODO`
- Points at `/analysis/serve` (doesn't exist; backend uses `/v1/analyze`)
- `CoachingResult { cues: [String], keyframeTimestamps: [String: TimeInterval] }` does not match backend `AnalyzeResponse`

### Phase P1 target contract

**New endpoint `POST /v1/pose` (backend; iPhone POSTs raw frames)**

```
POST /v1/pose
Content-Type: multipart/form-data

frames[]: <JPEG bytes>    # sampled at PoseConstants.strideFrameCount (every 3rd frame)
timestamps[]: <Float64>   # CMTime seconds for each frame
session_id: <UUID string> # optional
```

Backend runs pose model → returns keypoints in the existing backend schema:

```json
{
  "frames": [
    {
      "timestamp": 1.234,
      "keypoints": {
        "right_wrist":   { "x": 0.51, "y": 0.32, "confidence": 0.94 },
        "left_shoulder": { "x": 0.48, "y": 0.41, "confidence": 0.89 }
      }
    }
  ]
}
```

**Then `POST /v1/analyze`** (existing endpoint, no changes; receives keypoints and returns cues):

```json
{
  "frames": [ { "timestamp": 1.234, "keypoints": { ... } } ],
  "session_id": "optional"
}
```

Response (existing `AnalyzeResponse` in `backend/app/models.py` — no schema change):

```json
{
  "cues": [
    { "rule_id": "trophy_toss_arm_height", "phase": "trophy_pose", "message": "...", "severity": "major" }
  ],
  "summary": "No major issues detected — good serve!"
}
```

iOS `CoachingResult` must be updated to match `AnalyzeResponse` (list of structured `Cue` objects, not `[String]`).

### Joint name mapping — Vision → backend

`VNHumanBodyPoseObservation.JointName.rawValue` (the key stored in iOS `PoseFrame.joints`) maps to the backend's keypoint names as follows. This translation must be implemented before `POST /v1/analyze` can be wired up (P1). The translation belongs in a new `App/Services/Pose/VisionJointMapper.swift` utility called before any network POST. When the backend's own pose model generates keypoints (P1+), those are already in the backend schema — no translation needed server-side.

| Vision raw name | Backend keypoint name |
|---|---|
| `right_wrist_joint` | `right_wrist` |
| `left_wrist_joint` | `left_wrist` |
| `right_elbow_joint` | `right_elbow` |
| `left_elbow_joint` | `left_elbow` |
| `right_shoulder_1_joint` | `right_shoulder` |
| `left_shoulder_1_joint` | `left_shoulder` |
| `right_hip_joint` | `right_hip` |
| `left_hip_joint` | `left_hip` |
| `right_knee_joint` | `right_knee` |
| `left_knee_joint` | `left_knee` |
| `right_ankle_joint` | `right_ankle` |
| `left_ankle_joint` | `left_ankle` |
| `neck_joint` | `neck` |
| `root_joint` | `pelvis` |

---

## 3D Pose Subsystem (P7–P8)

The stereo geometry and triangulation math are identical on Mac and Jetson — only camera hardware differs.

### Stereo rig setup

**Mac (P4):** Two USB webcams placed at fixed positions — one at the open side (current Lite MVP angle: perpendicular to the serve, player's hitting arm visible), one at approximately 45° or the behind-server angle. Known baseline distance; fixed relative positions per session.

**Jetson (P16):** Same physical arrangement, cameras on the Jetson's CSI ports instead of USB.

### Calibration procedure (run once per setup)

1. Print a checkerboard calibration target.
2. Capture 20–30 stereo image pairs with the target at varied positions using `cv2.calibrateCamera` per camera (intrinsics), then `cv2.stereoCalibrate` (extrinsics: rotation R, translation T).
3. Compute rectification maps (`cv2.stereoRectify`, `cv2.initUndistortRectifyMap`).
4. Save calibration matrices to `stereoCalibration.json`; load at backend startup.

Script: `backend/tools/stereo_calibrate.py` (new in P7).

### Synchronization

**Mac:** Software timestamp — align nearest frames within a 10 ms window (USB cameras have no hardware sync).

**Jetson (P16):** Hardware sync via V4L2 / `libcamera` on CSI ports; software timestamp fallback.

### Triangulation

For each joint visible in both views above confidence threshold:
1. Undistort and rectify both 2D keypoints using saved calibration maps.
2. Compute 3D coordinates via `cv2.triangulatePoints`.
3. Output `(x, y, z)` in real-world cm units (origin at camera baseline midpoint).

Joint confidence in 3D is the minimum of the two 2D confidence scores. Joints visible in only one view fall back to 2D + estimated depth.

### 3D angle computation

Add `compute_angle_3d` to `backend/app/engine/angles.py` *alongside* the existing 2D `compute_angle` — both functions are retained so both tiers can coexist (P8). Rules consume whichever angle source matches the active capture tier:

```python
def compute_angle_3d(a: tuple, b: tuple, c: tuple) -> float:
    """Angle at joint b in degrees, in 3D space."""
    ba = np.array(a) - np.array(b)
    bc = np.array(c) - np.array(b)
    cos_angle = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-9)
    return float(np.degrees(np.arccos(np.clip(cos_angle, -1.0, 1.0))))
```

`rules.json` grows per-tier threshold variants: 2D-calibrated thresholds (P4) and 3D-calibrated thresholds (P9), alongside the per-serve-type variants introduced in P13.

---

## Migration Notes

### Reused as-is (no changes needed initially)

| Component | File | Notes |
|---|---|---|
| Serve phase detection | `backend/app/engine/phases.py` | Extended in P3 from 3 → 6 detected frames |
| Rule engine | `backend/app/engine/rules.py` + `rules.json` | 2D-calibrated in P4; 3D-calibrated in P9; per-serve-type variants in P13 |
| Angle utilities | `backend/app/engine/angles.py` | 2D `compute_angle` retained; `compute_angle_3d` added alongside in P8 |
| Analyze endpoint | `backend/app/routers/analyze.py` | Fully implemented; dormant in Lite MVP; activated in P5 |
| Calibration tool | `backend/tools/calibration_report.py` | Re-used in P3 re-validation |

### Newly introduced (P1–P5 work)

- `/v1/pose` endpoint (backend receives raw frames, runs 2D pose model, returns keypoints)
- ONNX Runtime / PyTorch-MPS model serving on Mac; TensorRT export for P16 Jetson
- YOLO object detection model + fine-tuning pipeline
- `App/Services/Pose/VisionJointMapper.swift` (iOS joint-name translation layer)
- Updated `LiveCoachingService.analyze()` and `CoachingResult` type matching `AnalyzeResponse`
- `backend/tools/stereo_calibrate.py` (P7)
- `stereoCalibration.json` (generated at calibration time, loaded at backend startup)
- `compute_angle_3d` in `engine/angles.py` (P8; added alongside `compute_angle`, not replacing it)

### Mac → Jetson migration (P16)

Pure portability step — no algorithm changes:
1. Export RTMPose and YOLO ONNX models to TensorRT on the Jetson.
2. Replace USB webcam capture code with CSI camera capture (V4L2 / `libcamera`).
3. Deploy `backend/` to the Jetson (same FastAPI app, same Python code).
4. Update `App/Services/BackendConfig.swift` from Mac LAN IP to Jetson address.
5. Test `GET /reference-frames` and `POST /v1/analyze` end-to-end on the Jetson.
