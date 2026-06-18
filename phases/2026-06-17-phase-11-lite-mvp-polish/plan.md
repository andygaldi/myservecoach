# Phase 11 — Lite MVP Polish: Plan

## Task Group 1 — Shared UI Components

Build the two reusable components that every subsequent task group depends on.

1.1 **`LoadingOverlayView`** — full-screen translucent overlay containing a `ProgressView` spinner and a configurable `String` label. Accepts a `message: String` parameter. Applied via a `.overlay` modifier so it sits above the current screen's content without a navigation push.

1.2 **`ErrorView`** — full-screen error view. Parameters:
- `systemImage: String` (SF Symbol name)
- `title: String`
- `message: String`
- `primaryActionLabel: String` + `primaryAction: () -> Void`
- `secondaryActionLabel: String?` + `secondaryAction: (() -> Void)?`

Both views live in `App/Views/Common/`.

---

## Task Group 2 — Loading States

Wire `LoadingOverlayView` into the two async operations.

2.1 **Pose estimation loading** — in the ViewModel that drives frame sampling + Vision processing, add a `@Published var isAnalyzing: Bool`. Set it `true` before the pipeline starts, `false` in `defer`. In the owning view, overlay `LoadingOverlayView(message: "Analyzing pose…")` when `isAnalyzing` is true.

2.2 **Reference frame fetch loading** — in `ReferenceFrameService` (or its owning ViewModel), add `@Published var isFetchingReferenceFrames: Bool`. Set it around the `URLSession` call. In the comparison/fetch-transition view, overlay `LoadingOverlayView(message: "Fetching reference frames…")` when this flag is true.

---

## Task Group 3 — Error Handling

Implement full-screen error views for each failure mode, wired to real error paths.

3.1 **Network failure** — in the reference frame fetch ViewModel, catch `URLError` and any HTTP non-2xx response. Set an `@Published var fetchError: AppError?`. When non-nil, replace the current screen content with `ErrorView`:
- Symbol: `wifi.exclamationmark`
- Title: "Couldn't Connect"
- Message: "Could not reach the server. Check your connection and try again."
- Primary: "Retry" → clears the error and re-triggers the fetch
- Secondary: "Cancel" → pops back to the manual frame selection screen

3.2 **No pose detected** — in the pose estimation ViewModel, after the Vision pipeline completes with zero keypoints across all sampled frames, set `@Published var noPoseDetected: Bool`. When true, replace the current screen with `ErrorView`:
- Symbol: `figure.stand`
- Title: "No Pose Detected"
- Message: "Make sure your full body is visible in the frame and the lighting is adequate."
- Primary: "Try Again" → navigates back to the record/import screen (dismisses the pose screen entirely)
- Secondary: none

3.3 **All phases unconfirmed guard** — on the Phase 7 manual frame selection screen, the "Continue" button is disabled when zero phases have been confirmed. Add an inline caption below the button: "Confirm at least one phase to continue." visible only when the button is disabled. No separate error view needed.

---

## Task Group 4 — History Screen Empty State

4.1 **`EmptyStateView`** — reusable view in `App/Views/Common/`. Parameters:
- `systemImage: String`
- `headline: String`
- `subheadline: String`

4.2 **Wire into history list** — in the session history view, when the SwiftData fetch returns an empty array, render:
```
EmptyStateView(
    systemImage: "list.bullet.clipboard",
    headline: "No sessions yet",
    subheadline: "Record or import a serve to get started."
)
```
instead of the `List`.

---

## Task Group 5 — App Icon & Launch Screen

5.1 **App icon placeholder** — in `Assets.xcassets`, populate the `AppIcon` image set with all required sizes (1024×1024 for App Store; 60pt @2x and @3x for iPhone home screen; additional sizes as required by Xcode's current template). Generate placeholder images programmatically (solid `#1A1A2E` background, white "MSC" text, rounded rectangle mask) or using a simple script. No missing-image warnings should remain in Xcode's asset catalog.

5.2 **Launch screen** — configure a `LaunchScreen` in `Info.plist` (or add `LaunchScreen.storyboard`). Content: white background, centered `UILabel`/"MyServeCoach" in the app's primary font weight, no images. Verify it appears correctly on iPhone SE and iPhone 15 Pro Max simulator sizes.

---

## Task Group 6 — Integration & Smoke Test

6.1 Run the full happy path on a real device (record → pose → phase review → fetch → comparison → history). Confirm:
- Spinner appears and disappears at both async steps.
- History empty state shows on first launch (before any sessions are saved).
- App icon and launch screen render correctly.

6.2 Test each error path manually:
- Kill the backend before the reference frame fetch → network error view appears; Retry re-fetches successfully when backend is back.
- Import a video with no person visible → no-pose-detected error view appears; Try Again returns to the record/import screen.
- On the phase review screen, skip all three confirmations → Continue button is disabled and caption is visible.
