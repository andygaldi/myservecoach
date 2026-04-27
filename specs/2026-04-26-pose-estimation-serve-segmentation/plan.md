# Phase 2 — On-Device Pose Estimation & Serve Segmentation: Plan

Each task group is independently committable and leaves the app in a working state.

---

## Group 1 — Shared Types & Frame Sampler

1. Define `JointPoint: Codable` struct in `App/Services/Pose/` — `x: Float`, `y: Float`, `confidence: Float`
2. Define `PoseFrame: Codable` struct — `timestamp: Double` (seconds from video start), `joints: [String: JointPoint]` (keyed by `VNHumanBodyPoseObservation.JointName.rawValue`)
3. Define sampling constant `kPoseSampleStride: Int = 3` in a `PoseConstants` enum (gives ~10 fps from a 30 fps source)
4. Create `FrameSamplerService` in `App/Services/Video/` — accepts an `AVAsset`, generates an ordered list of `CMTime` values at every `kPoseSampleStride`-th frame using the track's nominal frame rate, then requests `CGImage` frames via `AVAssetImageGenerator` with `appliesPreferredTrackTransform = true`
5. Return type: `[(time: CMTime, image: CGImage)]`
6. Manual test: call from a scratch playground or `didFinishRecording` and `print` the returned count for a known-length clip

---

## Group 2 — Pose Estimation Service

1. Create `PoseEstimationService` in `App/Services/Pose/`
2. Entry point: `func estimatePoses(from frames: [(time: CMTime, image: CGImage)]) async -> [PoseFrame]`
3. For each frame, create a `VNImageRequestHandler` and perform a `VNDetectHumanBodyPoseRequest`
4. Map the first `VNHumanBodyPoseObservation` (if any) to a `PoseFrame` — iterate all recognized points, convert Vision's normalized `(x, y)` coordinates to `JointPoint`, skip frames where no observation is returned
5. Only include joints with confidence `>= 0.3`; omit the frame entirely if fewer than 4 joints pass the threshold
6. Manual test: run on a real-device recording of a serve; print frame count in vs. PoseFrames out to verify the Vision pipeline is firing

---

## Group 3 — Serve Segmentation Service

1. Create `ServeSegmentationService` in `App/Services/Pose/`
2. Define segmentation constants in `PoseConstants`:
   - `kVelocityThreshold: Float = 0.015` (normalized units per frame; tune after first real-data test)
   - `kMinGapFrames: Int = 8` (consecutive low-velocity frames required to declare a gap between serves)
   - `kMinServeFrames: Int = 12` (minimum frames for a segment to count as a serve)
3. Implement velocity computation: for each consecutive pair of `PoseFrame`s, compute the mean Euclidean displacement across all joints present in both frames (normalized 0–1 coordinates); result is a `Float` per frame transition
4. Implement gap detection: scan the velocity array for runs of `kMinGapFrames` consecutive values below `kVelocityThreshold`; each gap is a serve boundary
5. Split the `[PoseFrame]` sequence at boundaries; discard segments shorter than `kMinServeFrames` frames
6. Return `[[PoseFrame]]` — one inner array per detected serve
7. Manual test: feed a 10-serve recording; confirm the returned array count is in the right ballpark

---

## Group 4 — Pipeline Integration & Console Output

1. Create `PoseAnalysisPipeline` actor in `App/Services/Pose/` — owns `FrameSamplerService`, `PoseEstimationService`, and `ServeSegmentationService`
2. Entry point: `func analyze(videoURL: URL) async throws -> [[PoseFrame]]`
3. Add a `JSONEncoder` with `.prettyPrinted` and `.sortedKeys` output formatting
4. After segmentation, encode each serve segment and `print` to the console in the format:
   ```
   [MyServeCoach] Serve 1/3 — 24 frames
   { "timestamp": 0.0, "joints": { ... } }
   ...
   [MyServeCoach] Serve 2/3 — 19 frames
   ...
   ```
5. Wire `PoseAnalysisPipeline.analyze(videoURL:)` into the "Use This Clip" action in `CameraViewModel` (call it; ignore the result for now beyond logging)
6. Manual test: tap "Use This Clip" after recording a serve sequence; verify segmented JSON appears in the Xcode console

---

## Group 5 — Unit Tests

1. Add `PoseFrameCodableTests` — encode a hand-crafted `PoseFrame` to JSON and decode it back; assert round-trip equality
2. Add `ServeSegmentationServiceTests` — synthesize `[PoseFrame]` sequences with known velocity patterns:
   - Two high-velocity bursts separated by a clear gap → expect 2 segments
   - Single continuous burst → expect 1 segment
   - Burst shorter than `kMinServeFrames` → expect 0 segments (filtered out)
   - Empty input → expect 0 segments
3. Add `FrameSamplerServiceTests` (using a pre-built test `.mov` bundled in the test target, or a `AVAsset` stub) — verify returned frame count matches `floor(durationFrames / kPoseSampleStride)`
4. Run all tests: `Cmd+U`; all must pass before merge
