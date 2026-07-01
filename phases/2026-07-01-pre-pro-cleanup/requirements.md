# Pre-Pro Cleanup — Requirements

## Scope

Fix the stale iOS test file that breaks `scripts/verify.sh ios`, so the build/test oracle is clean before Pro Version phases (P1+) begin.

## In Scope

- Delete `MyServeCoach/MyServeCoachTests/MyServeCoachTests.swift` in its entirety. Its two test suites (`ServeModelTests`, `RecordServeViewModelTests`) reference `Serve` and `RecordServeViewModel` — types that no longer exist anywhere in the codebase — and its mocks (`MockVideoService`, `MockPoseService`, `MockCoachingService`) are unused elsewhere. The file fails to compile, so it currently blocks `xcodebuild test` entirely.
- Confirm `scripts/verify.sh ios` passes after the deletion (`xcodebuild test -project MyServeCoach/MyServeCoach.xcodeproj -scheme MyServeCoach -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4" -quiet`).
- No Xcode project file changes needed — the project uses `PBXFileSystemSynchronizedRootGroup` (modern synchronized groups), so removing the file from disk (`git rm`) is sufficient; there is no manual `project.pbxproj` file reference to clean up.

### Scope Addendum (discovered during implementation)

Deleting `MyServeCoachTests.swift` unmasked a second, pre-existing, unrelated bug that had been hidden behind the compile failure: `VideoSourceSelectionViewModel.runPipeline` set `noPoseDetected = true` on the zero-segments path but never set `errorMessage`, failing two tests (`zeroServesTriggersError`, `handleExportSuccessZeroServes`) in `VideoSourceSelectionViewModelTests.swift`. Since `validation.md`'s Merge Criteria requires `scripts/verify.sh ios` to pass with zero failures, and the spec did not anticipate this conflict, the following were added to close it:

- `VideoSourceSelectionViewModel.swift` — set `errorMessage = "No serves detected. Try a different clip."` alongside `noPoseDetected = true` in the zero-segments branch of `runPipeline`.
- `ContentView.swift` — the "Try Again" action on the `noPoseDetected` full-screen `ErrorView` now also clears `errorMessage`, preventing a stale inline banner (`VideoSourceSelectionView`'s error text) from surfacing after the overlay is dismissed — the deep review caught that both flags fired together and only one was being cleared.

This is a small, necessary scope expansion to satisfy the phase's own written merge bar, not a deliberate widening of intent.

## Out of Scope

- Backfilling a test for `ServeSession` default field values — trivial SwiftData init, no logic to protect, would be busywork for this cleanup-only phase.
- Any other roadmap cleanup items — the roadmap's Pre-Pro Cleanup section lists only this one bullet; nothing else is folded in.
- Any Pro Version (P1+) code, scaffolding, or design work.
- Changes to `VideoServiceProtocol` / `PoseServiceProtocol` / `CoachingServiceProtocol` — these remain as orphaned-but-harmless scaffolding for future epics; removing them is not part of this cleanup and risks scope creep into unrelated protocol design decisions.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Fix approach | Delete `MyServeCoachTests.swift` entirely, don't rewrite | The file's only content is dead test suites against removed types; `CameraViewModelTests.swift` already covers the current recording-flow init-state behavior the old test attempted to provide. Nothing of value survives a rewrite. |
| Backfill coverage for `ServeSession` | Skip | Trivial SwiftData `@Model` init with no computed logic; not worth a dedicated test in a cleanup-scoped phase. |
| Phase scope | Exactly the one roadmap bullet | Keeps the phase small and independently verifiable per the roadmap's stated philosophy; avoids scope creep into unrelated cleanup. |
| Xcode project file | No `project.pbxproj` edit | Confirmed via `PBXFileSystemSynchronizedRootGroup` in the pbxproj — file system deletion alone is sufficient. |

## Context

Phase 6's pivot note and the Pre-Pro Cleanup roadmap entry both flag this as tooling debt surfaced while adopting the loop-based `/spec` → `/phase` → `/merge` workflow: `scripts/verify.sh ios` is meant to be the self-verification oracle `/phase` uses after each task group, but a pre-existing stale test file causes it to report build failures unrelated to any actual code change, making it useless as a signal.

This phase is a pure prerequisite gate — it produces no product functionality — so that Phase P1 (Off-Device 2D Pose Service) and all subsequent Pro Version phases start from a green `scripts/verify.sh ios` baseline.
