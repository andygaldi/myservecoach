# Phase 1 — Video Capture UI: Plan

Each task group is independently committable and leaves the app in a working state.

---

## Group 1 — AVCaptureSession + Preview Layer

1. Add `NSCameraUsageDescription` to `Info.plist`
2. Create `CameraService` in `App/Services/Video/` — configures `AVCaptureSession` with a `.video` input and starts/stops the session
3. Create `CameraPreviewView: UIViewRepresentable` — wraps an `AVCaptureVideoPreviewLayer` filling its bounds, portrait locked (`videoGravity: .resizeAspectFill`)
4. Add `toggleCamera()` to `CameraService` — swaps `AVCaptureDeviceInput` inside `beginConfiguration`/`commitConfiguration`; sets `isMirrored = true` on the front camera connection; no-ops while recording
5. Add `cameraPosition: AVCaptureDevice.Position` (default `.back`) to `CameraViewModel`; wire to `CameraService.toggleCamera()`
6. Mount `CameraPreviewView` full-screen in `RecordServeView`, replacing the current stub; add a flip button overlay (SF Symbol `camera.rotate`) that calls `viewModel.toggleCamera()` and is disabled when `state == .recording`
7. Manual test: live preview renders on a real device; flip button switches between rear and front camera

---

## Group 2 — Record/Stop and Temp File Output

1. Add `AVCaptureMovieFileOutput` to `CameraService`; expose `startRecording(to:)` and `stopRecording()` with an `AVCaptureFileOutputRecordingDelegate`
2. Extend `CameraViewModel` with `RecordingState` enum (`idle`, `recording`, `previewing(URL)`) using `@Observable`
3. Wire the Record/Stop button in `RecordServeView` to `CameraViewModel.toggleRecording()`
4. On recording completion callback, transition state to `.previewing(tempURL)` and surface the URL
5. Manual test: tap Record → tap Stop → temp `.mov` exists at the returned URL

---

## Group 3 — Post-Recording Playback Preview

1. Add `VideoPlayer` sheet or overlay to `RecordServeView` that activates when state is `.previewing(url)`
2. Include a "Use This Clip" button (transitions back to `.idle`, forwards URL to parent) and a "Retake" button (deletes temp file, resets to `.idle`)
3. Manual test: recorded clip plays back correctly; Retake correctly resets the camera

---

## Group 4 — Simulator Placeholder

1. Create `SimulatorPlaceholderView` — centered SF Symbol camera icon + "Camera not available in Simulator" copy, styled to match app accent color
2. Guard `CameraView` with `#if targetEnvironment(simulator)` to render the placeholder instead of initializing `AVCaptureSession`
3. Manual test: running in Xcode Simulator shows the placeholder without a crash

---

## Group 5 — Permission Denial Handling + Unit Tests

1. Handle `.denied` / `.restricted` auth status in `CameraViewModel` — expose a `permissionDenied: Bool` flag
2. Show a non-blocking banner in `RecordServeView` with a Settings deep-link (`UIApplication.openSettingsURLString`) when `permissionDenied` is true
3. Write XCTest unit tests for `CameraViewModel` state transitions:
   - `idle → recording` on `startRecording()`
   - `recording → previewing` on `recordingFinished(url:)`
   - `previewing → idle` on `retake()`
   - `permissionDenied` flag set correctly from `.denied` status
   - `cameraPosition` toggles `.back → .front → .back` on successive `toggleCamera()` calls
   - `toggleCamera()` is a no-op when `state == .recording`
