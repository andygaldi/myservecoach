# Phase 7 — Manual Frame Selection UI: Validation

## Unit Tests (XCTest)

- [x] `PhaseReviewViewModel.setFrame` stores the correct `CMTime` for the active phase and does not overwrite other phases.
- [x] `isDoneEnabled` is `false` until all three phases have a confirmed timestamp; becomes `true` immediately when the third is set.
- [x] `advance()` increments `currentStepIndex`; does not go past 2.
- [x] `retreat()` decrements `currentStepIndex`; does not go below 0.
- [x] `initialSeekTime` returns the guessed timestamp when Vision produced a confident guess.
- [x] `initialSeekTime` returns video midpoint when Vision produced no guess for that phase.
- [x] `FrameThumbnailGenerator.thumbnail(at:for:)` returns a non-nil `UIImage` for a valid test asset + timestamp.
- [x] `FrameThumbnailGenerator.thumbnail(at:for:)` throws for a timestamp beyond the asset's duration.

## Manual Tests (Real Device Required)

### Happy path — Vision guess available
- [x] Record or import a serve clip; pose estimation runs; `PhaseReviewView` appears showing "Trophy Pose — Step 1 of 3".
- [x] Player is pre-seeked to the Vision-guessed frame for trophy pose.
- [x] Scrubbing and tapping "Use This Frame" updates the thumbnail above the player.
- [x] "Next" is disabled before any frame is set; enabled after "Use This Frame" is tapped.
- [x] Tapping Next advances to "Racket Drop — Step 2 of 3"; player pre-seeks to that guess.
- [x] Repeat for contact point (step 3); Next label changes to "Done".
- [x] "Done" is disabled until step 3 frame is confirmed; enabled after.
- [x] Tapping Done passes three confirmed `PhaseFrame` values to the next screen.

### Back navigation
- [x] Tapping Back on step 2 returns to step 1; previously confirmed frame is still shown.
- [x] Changing the frame on step 1 after returning and tapping Next again re-confirms with the new value.

### No-guess fallback
- [x] For a phase where Vision had no confident detection, player starts at video midpoint.
- [x] "No pose detected — pick manually" label is visible.
- [x] User can still set a frame manually and proceed.

### Cancel / abandon
- [x] Navigating back past step 1 (or tapping a cancel button) returns to the input selection screen.
- [x] Restarting a session clears any previously confirmed frames.

## Merge Criteria

- All unit tests pass (`Cmd+U` in Xcode, zero failures).
- Manual walkthrough above completes without crashes or errors on a real device.
- Confirmed `CMTime` values match what was visually selected (within ~0.1 s, verified by logging).
- No regressions: recording (Phase 1), video import (Phase 5), and pose estimation (Phase 2) flows still work end-to-end.
- No compiler warnings introduced in new files.
