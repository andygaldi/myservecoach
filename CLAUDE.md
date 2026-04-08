# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MyServeCoach is an iOS application that analyzes tennis serve technique using video capture and AI coaching feedback. The project is in early development — the repo currently contains documentation and planning artifacts; application code is being built incrementally.

## Architecture

**iOS App (SwiftUI + MVVM)**
- `App/Views/` — SwiftUI view components (kept thin, no business logic)
- `App/ViewModels/` — View logic and state
- `App/Models/SwiftData/` — Persistent data models using SwiftData
- `App/Services/Video/` — AVFoundation video capture pipeline
- `App/Services/Pose/` — On-device pose estimation via Apple's Vision framework
- `App/Services/Coaching/` — Serve analysis logic and coaching cues

**Backend (FastAPI / Python)**
- REST API receiving keypoint JSON from iOS
- Serve phase detection: trophy pose, racket drop, contact point
- Angle computation utilities and a rule engine (`rules.json`)
- Returns coaching cues JSON to the iOS app

**Data flow:**
1. User records serve video (AVFoundation)
2. Frames are sampled and pose-estimated on-device (Vision framework)
3. Filtered keypoints are POSTed to the FastAPI backend (URLSession)
4. Backend runs rule-based analysis and returns coaching cues
5. iOS displays keyframe thumbnails and coaching summary (SwiftUI)
6. Results are cached locally (SwiftData)

## Build & Run

iOS app requires **macOS + Xcode** (latest stable). Build and run entirely within Xcode:
- Build: `Cmd+B`
- Run on Simulator: `Cmd+R`
- Camera features must be tested on a **real device** (Simulator has no camera)

Backend (FastAPI): commands will be added once the backend scaffold is in place.

## Testing

- **Unit tests** (XCTest): pose pipeline math, video processing abstractions, coaching logic
- **Snapshot tests**: SwiftUI views via ViewInspector
- **Manual tests**: serve recording, video playback, pose detection accuracy, edge cases (low light, shaky camera)

Print Vision results to the console early on for pose debugging.

## Git & Branch Strategy

- `main` — production-ready releases
- `develop` — active development (branch from here)
- `feature/<name>`, `bugfix/<name>`, `chore/<name>` — short-lived branches

PRs merge into `develop` via squash & merge. Stable releases are tagged (`v0.x.x`) on `main`.

Commit messages reference the Linear issue ID where applicable: `[MSC-XXXX] description`.

## Issue Tracking

Issues are managed in **Linear**. Issue IDs follow the pattern `MSC-XXXX`. The project roadmap and epics (video capture MVP, pose extraction, backend serve analysis, results UI) are defined in `docs/linear-project.csv`.

## Claude Code Usage Notes

Well-suited for: generating SwiftUI components, AVFoundation pipelines, Vision pose-analysis functions, Swift refactoring, test scaffolding, and PR descriptions.

Not suitable for: code signing/provisioning, simulator/device debugging, real-time UI previews, or Xcode-specific configuration errors — handle those directly in Xcode.
