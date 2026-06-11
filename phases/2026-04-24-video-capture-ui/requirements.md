# Phase 1 — Video Capture UI: Requirements

## Scope

Implement the full-screen camera capture UI that allows a user to record their serve and review the clip before proceeding. This is the entry point to the Assessment workflow.

### In Scope

- Full-screen portrait camera preview via `AVCaptureSession` + `AVCaptureVideoPreviewLayer`
- Record/Stop button: single tap starts recording, second tap stops and saves to a temp `.mov` file
- Post-recording playback preview using SwiftUI `VideoPlayer` (AVKit), displayed immediately after stopping
- Simulator placeholder screen — static view with explanatory copy shown when no camera is available
- Camera flip button to toggle between rear (default) and front camera mid-session

### Out of Scope

- Pose estimation or frame sampling (Phase 2)
- Uploading or analyzing the recorded video (Phase 5+)
- Persistent storage of the recorded file (Phase 7)
- Audio recording (microphone not needed; video only)
- Landscape orientation support

---

## Technical Decisions

### Recording Output: `AVCaptureMovieFileOutput`

Use `AVCaptureMovieFileOutput` writing to `FileManager.default.temporaryDirectory`. This is the simplest path for Phase 1 — it records a complete `.mov` file with a single delegate callback on completion. Phase 2 will need per-frame access; at that point the pipeline can be upgraded to `AVAssetWriter` if needed, but Phase 1 doesn't require it and shouldn't anticipate it.

### Architecture: MVVM

`CameraViewModel` owns the `AVCaptureSession` lifecycle and all state transitions. `CameraView` (SwiftUI) is a thin wrapper over `UIViewRepresentable` for the preview layer and observes the ViewModel. `RecordingState` enum drives the UI:

```
idle → recording → previewing → idle
```

`CameraViewModel` is `@Observable` (Swift 5.9+ macro). No Combine publishers; use `async/await` for permission checks.

### Camera Position Toggle

`CameraViewModel` exposes a `cameraPosition: AVCaptureDevice.Position` property (default `.back`). Tapping the flip button calls `toggleCamera()`, which replaces the current `AVCaptureDeviceInput` on the session inside a `beginConfiguration`/`commitConfiguration` block — no session restart needed. The front camera preview connection has `isMirrored = true` to match user expectation (same as the native Camera app). Toggling is disabled while recording is active.

### Simulator Detection

Check `ProcessInfo` or target `#if targetEnvironment(simulator)` compile directive to conditionally show a `SimulatorPlaceholderView` instead of initializing `AVCaptureSession` (which would crash on Simulator).

### Permissions

Request `NSCameraUsageDescription` at first launch via `AVCaptureDevice.requestAccess(for: .video)`. If denied, show an inline permission-denied banner with a Settings deep-link rather than crashing or silently failing.

---

## Context

The camera view is the first screen the user sees in the Assessment workflow (mission: "record serve → get coaching cues in seconds"). It must feel immediate and native — no loading spinners, no onboarding modals. The tech-stack mandates portrait lock and real-device testing for any camera feature.

This phase produces no networking or analysis code. Its only output is a temp `.mov` URL passed downstream in later phases.
