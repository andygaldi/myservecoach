# Tech Stack

## iOS App

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift 6 | Strict concurrency |
| UI | SwiftUI | MVVM architecture; views stay thin |
| Persistence | SwiftData | Local session history; no iCloud sync |
| Video capture | AVFoundation | `AVCaptureSession` for recording; portrait lock; Lite mode requires open-side camera placement (perpendicular to serve direction) |
| Video import | PhotosUI | `PhotosPicker` (iOS 16+); user selects existing video from Photos library; requests video asset only, avoiding full library permission |
| Pose estimation | Apple Vision | `VNDetectHumanBodyPoseRequest`; on-device, no API cost; runs on recorded frames to produce an initial phase-frame guess (trophy pose, racket drop, contact point); user corrects the guess in the manual frame selection UI before comparison |
| Serve segmentation | Apple Vision + manual | On-device Vision produces a heuristic phase-frame guess; the user reviews and corrects each frame in the Phase 7 UI; confirmed frames are the canonical result |
| Networking | URLSession | `async/await`; fetches reference frame library from backend; network required — no offline fallback |
| Min deployment | iOS 17 | Required for SwiftData + latest Vision APIs |

## Backend

| Concern | Choice | Notes |
|---|---|---|
| Language | Python 3.12 | |
| Framework | FastAPI | `GET /reference-frames` returns curated phase frames from high-quality serves |
| Reference frame library | Static assets | Curated images stored in the backend, organized by phase key (trophy_pose, racket_drop, contact); served as URLs or base64. Lite mode's only backend dependency — Lite never calls `/v1/pose` or `/v1/analyze`. |
| Calibration tooling | Python + OpenCV | `backend/tools/` developer utilities; take keypoint JSON (exported from iOS app) + video file and produce an HTML visual report (sampled frame thumbnails + highlighted phase frames); a separate script prints joint angles at detected phase frames for Pro-mode threshold calibration |
| Coaching engine | Dormant until Pro 2D/3D mode | Rule-based engine and `rules.json` exist from Phase 4 but are not used by Lite mode; activated by Pro 2D/3D phases (P5–P7, P10–P12) |
| LLM coaching | Claude API (Pro modes) | Natural-language cues in a later phase; Pro 2D/3D only |
| Hosting | Mac dev host → Jetson Orin Nano (Pro modes) | Local dev server for Lite mode (`GET /reference-frames` only); Pro 2D/3D development (P1–P16, plus the deferred P18 rigor upgrade) runs on the same Mac dev host — no new hardware needed to start. The on-court deployment phase (P17) migrates the Pro pipeline to a Jetson Orin Nano for untethered on-court portability. See `specs/offdevice-pipeline.md`. |

## Testing

| Layer | Tool |
|---|---|
| iOS unit tests | XCTest |
| SwiftUI snapshot tests | ViewInspector |
| Backend unit tests | pytest |
| Manual | Real device; serve recording on court |

## Repository Structure

iOS app and FastAPI backend live in the same repository (monorepo). Backend code goes in `backend/`; iOS app code stays at the repo root under `App/`. Developer calibration scripts live in `backend/tools/` and are checked in as permanent utilities. This keeps the iOS ↔ backend contract (reference frame schema) in a single commit history and eliminates cross-repo coordination overhead for a solo project.

## Key Architectural Decisions

- **Three permanent modes, mode-gated architecture**: Lite, Pro 2D, and Pro 3D are three coequal, user-selectable modes (see `specs/mission.md` "Capture Modes") — Lite is on-device-only; Pro 2D/3D are off-device. A mode-selection step at session setup gates which capture and analysis pipeline runs. Off-device code (pose model, object detection, coaching) is strictly additive: it is never called from, and never modifies, the Lite path (`PhaseReviewView`, the Lite pipeline/segmentation services, `ContentView`). The only Lite-mode network dependency, in any phase, is `GET /reference-frames`. This rule constrains every future phase, not just the ones that introduce it.
- **On-device pose estimation for initial guess only (Lite mode)**: Vision runs on the phone to produce a heuristic phase-frame guess (trophy pose, racket drop, contact point) from keypoint velocity analysis. This guess is treated as a starting point, not a final answer — the user reviews and corrects it in the manual frame selection UI. Vision's limitations under real court conditions (varied backgrounds, no racket detection) are acknowledged; fully automated segmentation is a Pro-mode capability, not a Lite-mode goal — Lite keeps manual correction permanently as its defining flow.
- **Manual frame confirmation as ground truth (Lite mode)**: The user's confirmed phase frames are the canonical result for a Lite session. All downstream steps (reference frame fetch, comparison display, persistence) use these confirmed frames, not raw Vision output.
- **Backend as reference frame library (Lite mode)**: The FastAPI backend's role for Lite mode is to serve a curated library of phase frames from high-quality serves — nothing more. The coaching rule engine (Phase 4) and the off-device pose service (P1+) remain in the codebase but are only invoked by Pro 2D/3D modes.
- **Network required, no offline fallback**: The comparison screen depends on fetching reference frames from the backend. If the backend is unreachable, the app shows a clear error. No local caching of reference frames.
- **Rule-based engine dormant until Pro modes activate it**: `rules.json` and `phases.py` from Phases 4–6 are kept in the backend for Pro 2D/3D use. They are not called from the Lite iOS flow.
- **Local persistence only**: SwiftData stores session history on-device. No user account or cloud sync.
- **No authentication**: The app is local-first; no login required until cloud sync or social features are introduced.
- **Single recording angle (Lite mode)**: Phase-frame heuristics are calibrated for the open-side view only (phone perpendicular to the serve direction, player's hitting side visible). Behind-server and closed-side angles are a Pro-mode capability (P15).
- **Pro 2D and Pro 3D pose estimation, Mac dev host first, Jetson Orin Nano for on-court portability**: The off-device pipeline is developed and fully validated on the Mac M3 Max (the same machine that hosts the Lite backend) — no hardware purchase needed to start. **Pro 2D mode** (iPhone only; ships first, P5–P7) and **Pro 3D mode** (iPhone + two USB webcams; adds stereo triangulation, P10–P12) are explicit, user-selectable modes, not internal "tiers" of a single Pro product — selecting Pro 2D vs. Pro 3D at session setup is the same kind of choice as selecting Lite. Strong 2D pose models (RTMPose or YOLO-Pose via ONNX Runtime / PyTorch-MPS) power both Pro modes, replacing on-device Vision; a YOLO-class detector adds racket and ball tracking. `backend/app/engine/angles.py` retains the 2D `compute_angle` and adds `compute_angle_3d` — both Pro modes coexist. The on-court deployment phase (P17) migrates the proven, unchanged Pro pipeline to a Jetson Orin Nano (TensorRT runtime, CSI cameras, battery-powered) for untethered on-court use. See `specs/offdevice-pipeline.md` for the full architecture and the Mac→Jetson migration notes.
