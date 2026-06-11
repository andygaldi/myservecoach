# Phase 2 — On-Device Pose Estimation & Serve Segmentation: Requirements

## Scope

Process a recorded serve video entirely on-device: extract frames, estimate human body pose on each frame using Apple Vision, detect serve boundaries via keypoint velocity analysis, and log the segmented result as JSON. No UI changes; no backend call. This phase produces the keypoint data structure that Phase 5 will POST to the backend.

### In Scope

- Frame extraction from a recorded `.mov` at every 3rd frame (~10 fps from a 30 fps source)
- On-device human body pose estimation via `VNDetectHumanBodyPoseRequest` (Apple Vision)
- Serve boundary detection using per-joint velocity thresholds across consecutive frames
- `PoseFrame` and `JointPoint` Codable types (the shared iOS ↔ backend keypoint contract)
- Console-only output: segmented keypoint JSON printed via `print()` after "Use This Clip"
- XCTest unit tests for the segmentation algorithm and Codable round-trip

### Out of Scope

- Any on-screen UI showing pose results or serve count (Phase 6)
- Backend network call (Phase 5)
- SwiftData persistence of keypoints (Phase 7)
- Live-feed pose detection for Set Goal (Phase 10)
- Skeleton overlay drawing (Phase 13)

---

## Technical Decisions

### Frame Sampling: `AVAssetImageGenerator` at stride 3

Extract frames using `AVAssetImageGenerator` with `appliesPreferredTrackTransform = true` (handles portrait rotation). Build the request-time list by reading the video track's `nominalFrameRate`, computing the total frame count, and stepping every `kPoseSampleStride = 3` frames. Set `requestedTimeToleranceBefore` and `requestedTimeToleranceAfter` to `CMTime(value: 1, timescale: 600)` (one video frame) rather than `.zero` to avoid dropped frames at non-keyframe boundaries.

At 30 fps this yields ~10 pose samples/sec — sufficient temporal resolution to capture trophy pose, racket drop, and contact events while keeping Vision calls tractable on a single recording.

### Pose Estimation: `VNDetectHumanBodyPoseRequest`

Use the single-frame request handler path (`VNImageRequestHandler`), not the sequence handler, because frames are processed offline (not a live stream). Run requests serially in an `async` loop rather than a concurrent task group to avoid memory spikes from many simultaneous Vision allocations.

Map `VNHumanBodyPoseObservation` recognized points to `JointPoint` using normalized coordinates (Vision's `(x, y)` are in `[0, 1]²` with the origin at the bottom-left; preserve this convention in `JointPoint` — the backend must be aware of it). Filter joints below 0.3 confidence; discard frames where fewer than 4 joints pass.

### Keypoint JSON Schema

```json
{
  "timestamp": 0.333,
  "joints": {
    "right_wrist_joint":   { "x": 0.52, "y": 0.71, "confidence": 0.91 },
    "right_elbow_1_joint": { "x": 0.50, "y": 0.60, "confidence": 0.88 },
    ...
  }
}
```

Joint name keys are `VNHumanBodyPoseObservation.JointName.rawValue` strings (e.g. `"right_wrist_joint"`). This is the schema that Phase 3's `POST /analyze` endpoint will consume — defining it here locks the contract for both sides.

### Serve Segmentation: Velocity Threshold

For each consecutive pair of `PoseFrame`s, compute mean joint displacement:

```
velocity(t) = mean over shared joints of sqrt((x_t - x_{t-1})² + (y_t - y_{t-1})²)
```

A serve boundary is declared at any run of `kMinGapFrames = 8` consecutive frame transitions where `velocity < kVelocityThreshold = 0.015` (normalized units). These constants are deliberately conservative initial values — expect tuning on real data. Segments shorter than `kMinServeFrames = 12` frames are discarded as noise.

All threshold constants live in a `PoseConstants` enum so they can be adjusted without touching algorithm code.

### Architecture

`PoseAnalysisPipeline` is a Swift `actor` to serialise access to the Vision/AVFoundation state and ensure the processing runs on a background executor without blocking the main thread. It is owned by `CameraViewModel` (one instance per session). The pipeline's output type, `[[PoseFrame]]`, is the boundary surface — services below it are implementation details.

---

## Context

Phase 1 delivers a `.mov` URL at the "Use This Clip" tap. Phase 2 consumes that URL and emits segmented keypoints. The console output is the primary debugging tool for calibrating Vision confidence thresholds and segmentation constants before a backend exists. Print Vision results verbosely at this stage; they can be silenced in a later phase.

The on-device constraint (no video upload, on-device Vision) is a hard architectural requirement from `tech-stack.md` — it keeps latency low, avoids bandwidth costs, and means no video ever leaves the device in the Assessment workflow.
