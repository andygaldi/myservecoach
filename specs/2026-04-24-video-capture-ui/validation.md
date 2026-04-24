# Phase 1 — Video Capture UI: Validation

All criteria must pass before merging into `develop`.

---

## 1. Camera preview renders on real device; flip button works

**How to test:** Build and run on a physical iPhone (iOS 17+). Navigate to the record screen.

**Pass:**
- Live camera feed fills the screen in portrait orientation with no black frame, no crash, and no visible latency on launch
- Tapping the flip button switches to the front camera (preview updates, mirrored); tapping again returns to rear
- Flip button is disabled and non-interactive during an active recording

**Fail:** Black/blank preview, crash on launch, session initialization error in the console, flip button crashes or has no effect, or flip button remains tappable during recording.

---

## 2. Record produces a valid `.mov` file

**How to test:** Tap Record, hold for ~3 seconds, tap Stop.

**Pass:**
- The app transitions to the playback preview screen
- The recorded clip plays back correctly via `VideoPlayer`
- A `.mov` file exists at `FileManager.default.temporaryDirectory` with a non-zero file size

**Fail:** No file written, file size is 0, playback is blank, or the app crashes during/after recording.

---

## 3. Simulator shows placeholder

**How to test:** Run the app target in any Xcode Simulator.

**Pass:** The record screen displays the `SimulatorPlaceholderView` (camera icon + explanatory copy). No `AVCaptureSession` is initialized; no crash.

**Fail:** Black screen, crash, or attempt to initialize a capture session in the Simulator.

---

## 4. Unit tests pass for ViewModel state transitions

**How to test:** Run the `MyServeCoachTests` target in Xcode (`Cmd+U`).

**Pass:** All six `CameraViewModel` state-machine tests pass:
- `idle → recording`
- `recording → previewing`
- `previewing → idle` (retake)
- `permissionDenied` flag from `.denied` auth status
- `cameraPosition` toggles `.back → .front → .back`
- `toggleCamera()` is a no-op when state is `.recording`

**Fail:** Any test case fails or the test target does not compile.

---

## 5. No regressions

**How to test:** Navigate through any other screens present in the app.

**Pass:** Existing stub views still compile and render without errors after Phase 1 changes.

**Fail:** Build errors or runtime crashes introduced in unrelated screens.
