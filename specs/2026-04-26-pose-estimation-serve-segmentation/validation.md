# Phase 2 — On-Device Pose Estimation & Serve Segmentation: Validation

All criteria must pass before merging into `develop`.

---

## 1. Frame sampler returns the correct count

**How to test:** Record a ~10-second clip (approximately 300 frames at 30 fps). After tapping "Use This Clip", check the console.

**Pass:**
- The logged frame count is approximately `floor(total_frames / 3)` (±1 frame for rounding)
- No `AVAssetImageGenerator` errors in the console
- Processing completes within 5 seconds on a real device

**Fail:** Frame count is 0, wildly off, or the call throws an unhandled error.

---

## 2. Pose estimation produces non-empty output on a real serve recording

**How to test:** Record yourself hitting 2–3 serves in good lighting, tap "Use This Clip".

**Pass:**
- At least 50% of sampled frames produce a `PoseFrame` (Vision found a body pose)
- The Xcode console shows `[MyServeCoach] Serve N/M — X frames` entries (at least one serve detected)
- No crash; no unhandled Swift concurrency warning or actor isolation error

**Fail:** 0 `PoseFrame`s returned, app crashes, or the console shows no serve output at all.

---

## 3. Serve segmentation counts serves correctly

**How to test:** Record a clip with exactly 3 clearly separated serves (step away from the baseline between each to create obvious low-motion gaps). Tap "Use This Clip".

**Pass:**
- Console output shows `Serve 1/3`, `Serve 2/3`, `Serve 3/3` (count may be ±1 due to threshold sensitivity — acceptable at this stage)
- Each serve segment contains at least `kMinServeFrames` frames
- No segment contains frames clearly belonging to a rest period (visual inspection of timestamps)

**Fail:** All frames collapsed into one segment, or more than 6 segments reported for a 3-serve clip.

---

## 4. Console JSON is valid and matches the defined schema

**How to test:** Copy a printed `PoseFrame` JSON block from the Xcode console and paste it into a JSON validator (or `python3 -m json.tool`).

**Pass:**
- JSON parses without errors
- Top-level keys are `timestamp` (number) and `joints` (object)
- Each joint entry has `x`, `y`, `confidence` as numbers
- Joint name keys match `VNHumanBodyPoseObservation.JointName` raw values (e.g. `"right_wrist_joint"`)

**Fail:** Malformed JSON, missing keys, or type mismatches.

---

## 5. Unit tests pass

**How to test:** Run the `MyServeCoachTests` target (`Cmd+U`).

**Pass:** All of the following pass:
- `PoseFrameCodableTests` — encode/decode round-trip matches the original struct
- `ServeSegmentationServiceTests` — all four synthetic sequences (two-burst, single-burst, short-burst, empty) produce the expected segment count
- `FrameSamplerServiceTests` — returned frame count matches `floor(durationFrames / kPoseSampleStride)`

**Fail:** Any test case fails or the test target does not compile.

---

## 6. No regressions from Phase 1

**How to test:** Rebuild and run the full app on device; exercise Phase 1 flows.

**Pass:**
- Camera preview still renders, record/stop still works, playback preview still works
- "Retake" correctly discards the clip and resets state (no dangling `PoseAnalysisPipeline` call)
- Simulator still shows the placeholder without a crash

**Fail:** Any Phase 1 behaviour broken by Phase 2 changes.

---

## 7. No main-thread blocking

**How to test:** While the pipeline is running (after "Use This Clip"), attempt to interact with the app UI — e.g., tap the Retake button.

**Pass:** UI remains responsive; Retake is tappable. Xcode's main-thread checker shows no violations.

**Fail:** UI freezes for more than 1 second during analysis, or the main-thread checker fires.
