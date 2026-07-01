# Pre-Pro Cleanup — Plan

**Surface:** `ios`

## Task Group 1 — Remove Stale Test File & Verify

1.1 **Delete the stale test file** — `git rm MyServeCoach/MyServeCoachTests/MyServeCoachTests.swift`. This removes both `ServeModelTests` and `RecordServeViewModelTests` (which reference the removed `Serve` and `RecordServeViewModel` types) along with their now-unused `MockVideoService`, `MockPoseService`, and `MockCoachingService` mocks. No `project.pbxproj` edit is required — the project uses `PBXFileSystemSynchronizedRootGroup`, so the file's absence is picked up automatically.

1.2 **Confirm no other references** — `grep -rn "MyServeCoachTests\.swift\|MockVideoService\|MockPoseService\|MockCoachingService" MyServeCoach/` to confirm nothing else in the codebase imports or references the deleted mocks. (Expected: no results outside the deleted file, since these mocks were only consumed by the deleted suites.)

1.3 **Run the verify oracle** — `scripts/verify.sh ios`. Expected: `xcodebuild test` builds and runs the full `MyServeCoachTests` target successfully with zero failures, including `CameraViewModelTests.swift` and the other existing suites (`PhaseReviewViewModelTests`, `VideoSourceSelectionViewModelTests`, `FrameSamplerServiceTests`, `FrameThumbnailGeneratorTests`, `PoseEstimationServiceTests`, `PoseFrameCodableTests`, `ReferenceFrameCodableTests`, `ServeSegmentationServiceTests`).

---

This is the only task group — the phase is a single atomic deletion-and-verify action with no dependent follow-up work.
