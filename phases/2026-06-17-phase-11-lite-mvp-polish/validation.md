# Phase 11 — Lite MVP Polish: Validation

## Definition of Done

Phase 11 is complete when all criteria below pass. The Lite MVP is then considered shippable.

---

## 1. Loading States

| Check | How to verify |
|---|---|
| Spinner appears immediately when pose estimation starts | Run on real device; tap Record or import a video; observe overlay before the phase review screen appears |
| "Analyzing pose…" label is visible on the spinner overlay during pose estimation | Visual check during the above |
| Spinner appears when reference frame fetch begins | Confirm phase frames; observe overlay before the comparison screen appears |
| "Fetching reference frames…" label is visible | Visual check during the above |
| Spinner disappears when each operation completes or fails | Confirm overlay is gone once the next screen loads or an error view replaces it |
| No interaction is possible while a spinner is shown (buttons behind the overlay are not tappable) | Attempt to tap during a slow fetch (throttle network in Settings → Developer) |

---

## 2. Error Handling

### 2a. Network Failure

| Check | How to verify |
|---|---|
| Full-screen error view replaces the loading state when the backend is unreachable | Stop the FastAPI server; complete phase confirmation; verify the error view appears |
| Error view shows the wifi symbol, "Couldn't Connect" title, and the correct body message | Visual check |
| Retry button re-triggers the fetch | Start the server again; tap Retry; verify the comparison screen loads |
| Cancel button returns to the manual frame selection screen | Tap Cancel; verify navigation state |

### 2b. No Pose Detected

| Check | How to verify |
|---|---|
| Full-screen error view appears when Vision returns no keypoints | Import a video of a blank wall or an empty court; verify the error view appears instead of the phase review screen |
| Error view shows the correct symbol, title ("No Pose Detected"), and body message | Visual check |
| Try Again navigates back to the record/import screen | Tap Try Again; verify the app returns to the session-start screen with no stale state |

### 2c. All Phases Unconfirmed

| Check | How to verify |
|---|---|
| Continue button is disabled when no phases are confirmed | Open the phase review screen; skip all three confirmations without tapping any confirm button; verify Continue is greyed out |
| Caption "Confirm at least one phase to continue." is visible below the disabled button | Visual check |
| Confirming one phase re-enables Continue | Tap confirm on any single phase; verify the button becomes tappable |

---

## 3. History Screen Empty State

| Check | How to verify |
|---|---|
| Empty-state view shows on the history screen when no sessions exist | Delete the app and reinstall (or reset SwiftData store) to clear all sessions; navigate to history |
| Empty state shows the list.bullet.clipboard icon, "No sessions yet" headline, and "Record or import a serve to get started." subheadline | Visual check |
| Empty state disappears after completing one session | Complete a full session; return to history; verify the session appears in a list (no empty state) |

---

## 4. App Icon & Launch Screen

| Check | How to verify |
|---|---|
| No missing-image warnings in Xcode's asset catalog for AppIcon | Open `Assets.xcassets` → AppIcon; zero yellow warning triangles |
| App icon renders on the home screen (Simulator) | Build and run on iPhone 15 Pro simulator; press Home; verify icon is visible (not a blank square) |
| Launch screen shows "MyServeCoach" on a white background | Cold-launch the app on both iPhone SE (smallest) and iPhone 15 Pro Max (largest) simulators; verify the launch screen appears correctly before the main UI loads |

---

## 5. No Regressions

| Check | How to verify |
|---|---|
| Full happy-path flow completes without crashes | Record (or import) → pose estimation → phase review → confirm all three → fetch reference frames → comparison screen → tap back → history shows the new session → tap session → comparison screen re-opens |
| XCTest unit test suite passes | `Cmd+U` in Xcode; zero failures |
| No new Xcode build warnings introduced | Build (`Cmd+B`); warning count is equal to or less than pre-phase baseline |

---

## Merge Criteria

All validation checks above pass on a real iPhone (or the Simulator for icon/launch checks). The branch is squash-merged into `develop` and tagged as the Lite MVP completion commit.
