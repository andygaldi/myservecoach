# Pre-Pro Cleanup — Validation

## Definition of Done

Pre-Pro Cleanup is complete when the stale test file is removed and `scripts/verify.sh ios` passes with a clean, meaningful signal — no unrelated build failures blocking Pro Version work.

---

## 1. Stale Test Removal

| Check | How to verify |
|---|---|
| `MyServeCoachTests.swift` no longer exists in the repo | `git status` / `ls MyServeCoach/MyServeCoachTests/` shows the file is gone; `git log -1 --stat` shows it as deleted |
| No dangling references to the deleted types or mocks | `grep -rn "RecordServeViewModel\|MockVideoService\|MockPoseService\|MockCoachingService" MyServeCoach/` returns no results |
| No `project.pbxproj` cleanup needed | Confirm the project still uses `PBXFileSystemSynchronizedRootGroup` (`grep -n "PBXFileSystemSynchronizedRootGroup" MyServeCoach/MyServeCoach.xcodeproj/project.pbxproj`) — no manual file-reference removal required |

---

## 2. Verify Oracle is Green

| Check | How to verify |
|---|---|
| `scripts/verify.sh ios` passes with zero failures | Run `scripts/verify.sh ios` from repo root; `xcodebuild test` completes with `** TEST SUCCEEDED **` |
| Existing (non-stale) test suites still run and pass | Confirm the test output includes `CameraViewModelTests`, `PhaseReviewViewModelTests`, `VideoSourceSelectionViewModelTests`, `FrameSamplerServiceTests`, `FrameThumbnailGeneratorTests`, `PoseEstimationServiceTests`, `PoseFrameCodableTests`, `ReferenceFrameCodableTests`, `ServeSegmentationServiceTests` — all passing |

No manual/device check is required for this phase — it removes a test file with no runtime or UI surface; a real device is not needed to validate a test-suite deletion.

---

## Merge Criteria

`scripts/verify.sh ios` passes clean and the stale file is confirmed deleted. That is the entire bar for this phase — it is a minimal, single-purpose cleanup gate ahead of Pro Version Phase P1.
