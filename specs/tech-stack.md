# Tech Stack

## iOS App

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift 6 | Strict concurrency |
| UI | SwiftUI | MVVM architecture; views stay thin |
| Persistence | SwiftData | Local session history; no iCloud sync in MVP |
| Video capture | AVFoundation | `AVCaptureSession` for recording; portrait lock; MVP requires open-side camera placement (perpendicular to serve direction) |
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
| Reference frame library | Static assets (MVP) | Curated images stored in the backend, organized by phase key (trophy_pose, racket_drop, contact); served as URLs or base64 |
| Calibration tooling | Python + OpenCV | `backend/tools/` developer utilities; take keypoint JSON (exported from iOS app) + video file and produce an HTML visual report (sampled frame thumbnails + highlighted phase frames); a separate script prints joint angles at detected phase frames for future Pro Version threshold calibration |
| Coaching engine | Deferred (Pro Version) | Rule-based engine and `rules.json` exist from Phase 4 but are not used by the Lite MVP; preserved for future Pro Version development |
| LLM coaching | Claude API (Pro Version) | Natural-language cues in a later phase; not in MVP |
| Hosting | Raspberry Pi (Pro Version plan) | Local dev server for Lite MVP; Pro Version plan is to run the API server on a Raspberry Pi connected to the iPhone over a local network — no cloud round-trip, all data stays on court; Pi also hosts a second camera for multi-angle 3D pose estimation |

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

- **On-device pose estimation for initial guess only**: Vision runs on the phone to produce a heuristic phase-frame guess (trophy pose, racket drop, contact point) from keypoint velocity analysis. This guess is treated as a starting point, not a final answer — the user reviews and corrects it in the manual frame selection UI. Vision's limitations under real court conditions (varied backgrounds, no racket detection) are acknowledged; fully automated segmentation is deferred to the Pro Version.
- **Manual frame confirmation as ground truth**: The user's confirmed phase frames are the canonical result for a session. All downstream steps (reference frame fetch, comparison display, persistence) use these confirmed frames, not raw Vision output.
- **Backend as reference frame library**: The FastAPI backend's primary role in the Lite MVP is to serve a curated library of phase frames from high-quality serves. The coaching rule engine (Phase 4) remains in the codebase but is not invoked by the Lite MVP — it is preserved for Pro Version development.
- **Network required, no offline fallback**: The comparison screen depends on fetching reference frames from the backend. If the backend is unreachable, the app shows a clear error. No local caching of reference frames in MVP.
- **Rule-based engine preserved, not active**: `rules.json` and `phases.py` from Phases 4–6 are kept in the backend for future Pro Version use. They are not called from the Lite MVP iOS app.
- **Local persistence only**: SwiftData stores session history on-device. No user account or cloud sync in MVP.
- **No authentication in MVP**: The app is local-first; no login required until cloud sync or social features are introduced.
- **Single recording angle (MVP)**: Phase-frame heuristics are calibrated for the open-side view only (phone perpendicular to the serve direction, player's hitting side visible). Behind-server and closed-side angles are deferred to the Pro Version.
- **Pro Version pose estimation — Raspberry Pi**: The plan for the Pro Version is to run pose estimation off-device on a Raspberry Pi connected to the iPhone over a local network. The Pi replaces the cloud backend as the API server (keeping all data local to the court and eliminating internet latency), and provides a mounting point for a second camera. With two synchronized camera feeds, joint positions can be triangulated into 3D coordinates, enabling accurate toss height and lateral position measurements that a single phone camera cannot reliably produce. This also enables the racket-detection and background-removal work needed to make automatic serve segmentation robust enough for the Assessment and Set Goal workflows.
