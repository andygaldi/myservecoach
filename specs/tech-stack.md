# Tech Stack

## iOS App

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift 6 | Strict concurrency |
| UI | SwiftUI | MVVM architecture; views stay thin |
| Persistence | SwiftData | Local session history; no iCloud sync in MVP |
| Video capture | AVFoundation | `AVCaptureSession` for recording; portrait lock |
| Pose estimation | Apple Vision | `VNDetectHumanBodyPoseRequest`; on-device, no API cost |
| Serve segmentation | Apple Vision | On-device; detects serve boundaries via pose velocity / keypoint activity within `VNDetectHumanBodyPoseRequest` output |
| Networking | URLSession | `async/await`; posts keypoint JSON to backend; network required — no offline fallback |
| Audible feedback | AVSpeechSynthesizer | Speaks per-serve goal result in Set Goal workflow; no external TTS dependency |
| Min deployment | iOS 17 | Required for SwiftData + latest Vision APIs |

## Backend

| Concern | Choice | Notes |
|---|---|---|
| Language | Python 3.12 | |
| Framework | FastAPI | `POST /analyze` receives keypoints, returns cues |
| Coaching engine | Rule-based (MVP) | `rules.json` threshold config; supports optional `goal_id` for Set Goal workflow |
| LLM coaching | Claude API (future) | Natural-language cues in a later phase; not in MVP |
| Hosting | TBD | Local dev server for MVP; cloud target TBD |

## Testing

| Layer | Tool |
|---|---|
| iOS unit tests | XCTest |
| SwiftUI snapshot tests | ViewInspector |
| Backend unit tests | pytest |
| Manual | Real device; serve recording on court |

## Repository Structure

iOS app and FastAPI backend live in the same repository (monorepo). Backend code goes in `backend/`; iOS app code stays at the repo root under `App/`. This keeps the tight iOS ↔ backend contract (keypoint JSON schema, coaching cues format) in a single commit history and eliminates cross-repo coordination overhead for a solo project. If the backend needs to be extracted later (e.g., cloud hosting with independent deploys, separate team), `git filter-repo` can do that without losing history.

## Key Architectural Decisions

- **On-device pose extraction and serve segmentation**: Vision runs on the phone for both pose estimation and serve boundary detection (via keypoint velocity analysis). Segmentation runs on a saved video file in Assessment and on the live camera feed in Set Goal. Only filtered keypoint JSON is sent to the backend. Video never leaves the device; Set Goal session video is discarded after the session ends.
- **Network required, no offline fallback**: Analysis depends on a backend POST. If the backend is unreachable, the app shows a clear error. No queueing or on-device rule fallback.
- **Rule-based engine first**: Deterministic coaching output keeps the MVP debuggable and fast. LLM layer added later as an enhancement, not a dependency.
- **Local persistence only**: SwiftData stores session history on-device. No user account or cloud sync in MVP.
- **No authentication in MVP**: The app is local-first; no login required until cloud sync or social features are introduced.
- **Audible feedback is on-device only**: AVSpeechSynthesizer speaks the per-serve result in the Set Goal workflow. No internet required for the spoken cue itself; only the analysis POST needs connectivity.
