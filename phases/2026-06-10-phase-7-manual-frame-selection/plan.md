# Phase 7 — Manual Frame Selection UI: Plan

## Task Group 1 — Data Model & ViewModel

1.1 Define `PhaseFrame` struct: `phase` (enum: `trophyPose`, `racketDrop`, `contactPoint`), `timestamp` (`CMTime`), `thumbnail` (`UIImage?`).

1.2 Create `PhaseReviewViewModel` (`@Observable`):
- `guessedFrames: [PhaseFrame]` — populated from Phase 2 output.
- `confirmedTimestamps: [ServePhase: CMTime]` — keyed by phase; grows as user confirms.
- `currentStepIndex: Int` — 0–2.
- `currentPhase: ServePhase` — derived from index.
- `isDoneEnabled: Bool` — true when all three phases have a confirmed timestamp.
- `func setFrame(at time: CMTime)` — stores timestamp for current step; triggers thumbnail render.
- `func advance()` / `func retreat()` — step navigation with boundary guards.
- `func initialSeekTime(for phase: ServePhase) -> CMTime` — returns guessed timestamp if confident, else video midpoint.

1.3 Wire ViewModel to receive guessed frames from the Phase 2 pose pipeline output.

## Task Group 2 — Video Player Component

2.1 Create `VideoPlayerView: UIViewControllerRepresentable` wrapping `AVPlayerViewController`.
- Exposes a `Binding<CMTime>` for the current playback time (updated on `periodicTimeObserver`).
- Seek bar provided by `AVPlayerViewController` (no custom seek UI needed).

2.2 Create `FrameThumbnailGenerator`:
- Wraps `AVAssetImageGenerator` with `appliesPreferredTrackTransform = true`.
- `func thumbnail(at time: CMTime, for asset: AVAsset) async throws -> UIImage`.
- Called after "Use This Frame" to render the still.

## Task Group 3 — Phase Review Screen

3.1 Create `PhaseReviewView`:
- Header: phase label + step counter ("Trophy Pose — Step 1 of 3").
- Thumbnail area: shows confirmed frame image, or a placeholder if not yet set.
- `VideoPlayerView` for the full clip.
- "Use This Frame" button: calls `viewModel.setFrame(at: currentPlayerTime)`, then `FrameThumbnailGenerator` to render and display the still.
- Back / Next buttons in a bottom toolbar; Next → "Done" on step 3.
- "No pose detected — pick manually" label shown when falling back to midpoint.

3.2 On appear for each step, seek the player to `viewModel.initialSeekTime(for: currentPhase)`.

## Task Group 4 — Navigation Integration

4.1 Insert `PhaseReviewView` in the app's navigation flow after the Phase 2 pipeline completes.

4.2 On Done, pass the three confirmed `PhaseFrame` values to the next destination (Phase 8 stub — `ReferenceFrameFetchView` placeholder).

4.3 Handle cancel / back-to-start: pop to the input selection screen, discarding in-progress confirmation state.

## Task Group 5 — Unit Tests

5.1 `PhaseReviewViewModelTests`:
- `setFrame` stores the correct timestamp for the current phase.
- `isDoneEnabled` is false until all three phases are confirmed.
- `advance()` increments index; blocked at 2.
- `retreat()` decrements index; blocked at 0.
- `initialSeekTime` returns guessed time when confident, midpoint when no guess.

5.2 `FrameThumbnailGeneratorTests`:
- Returns a non-nil `UIImage` for a valid test asset at a known timestamp.
- Throws for an invalid timestamp beyond asset duration.
