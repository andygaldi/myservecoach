# Phase 11 — Lite MVP Polish: Requirements

## Scope

Polish the Lite Version into a shippable, user-facing state. Phase 11 is the final gate before the Lite MVP is considered complete. No new features are added; this phase closes all rough edges in UX, error handling, and branding.

## In Scope

### Loading & Progress States
- Full-screen spinner overlay during pose estimation (frame sampling + `VNDetectHumanBodyPoseRequest` processing).
- Full-screen spinner overlay while fetching reference frames from the backend (`GET /reference-frames`).
- Each overlay shows a contextual label: "Analyzing pose…" or "Fetching reference frames…".
- Overlays block all interaction until the operation completes or fails.

### Error Handling
- **Network failure** (reference frame fetch fails): full-screen error view with icon, user-readable message ("Could not connect to the server. Check your connection and try again."), and a **Retry** button that re-triggers the fetch. A **Cancel** button returns the user to the manual frame selection screen.
- **No pose detected** (Vision returns no body keypoints for any sampled frame): full-screen error view with message ("No pose detected. Make sure your full body is visible in the frame.") and a **Try Again** button that navigates back to the recording/import screen.
- **All phases unconfirmed** (user skips confirmation for all three frames): prevent progression — show an inline warning on the phase review screen ("Please confirm at least one phase to continue."). The Continue button is disabled until at least one phase is confirmed.
- Error views are reusable: a single `ErrorView` component accepts an icon, title, body text, primary action label + handler, and optional secondary action label + handler.

### Empty State — History Screen
- When there are no saved `ServeSession` records in SwiftData, the history list shows a centered empty-state view: icon (e.g., SF Symbol `list.bullet.clipboard`), headline ("No sessions yet"), and a subheadline ("Record or import a serve to get started."). No list rows are shown.

### App Icon & Launch Screen
- `Assets.xcassets` contains a complete `AppIcon` image set. All required sizes are filled — the artwork itself is a placeholder (solid color + "MSC" text or equivalent) pending a final design pass. No missing icon warnings in Xcode.
- A `LaunchScreen.storyboard` (or `Info.plist` launch screen key) is configured. It shows the app name ("MyServeCoach") centered on a white background. No complex animation or images required.

## Out of Scope
- Animated transitions or skeleton loading placeholders (deferred).
- Offline caching of reference frames (explicitly deferred per tech-stack decisions).
- App Store assets (screenshots, app description, privacy policy).
- Actual icon artwork — a real design is a follow-on task outside this phase.
- Any Pro Version features.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Loading UI pattern | Full-screen overlay with spinner + label | Blocks accidental interaction during async ops; clearer than inline progress bars for operations the user cannot interrupt meaningfully |
| Error surface | Full-screen error view with Retry/Cancel | Critical failures (no network, no pose) must be impossible to miss; full-screen ensures the user understands what happened and what to do |
| "All phases unconfirmed" handling | Inline disabled-button warning on phase review screen | This is a soft guard, not a catastrophic failure; inline is appropriate because the user is already on the relevant screen |
| App icon | Placeholder — complete image set, placeholder artwork | Shipping with missing icons causes Xcode/App Store warnings; a placeholder fills the slot cleanly without blocking the phase on design work |
| Empty state | Dedicated EmptyStateView component | Reusable pattern; consistent with Apple HIG recommendations for empty list screens |

## Context

Phases 1–10 have established a fully functional Lite MVP flow:
- Record or import a serve video → on-device pose estimation → manual phase frame review → reference frame fetch → side-by-side comparison → SwiftData persistence → history list.

Phase 11 adds the guardrails and polish that turn this working prototype into an app a target user (club-level competitive tennis player) could actually hand to a friend:
- No raw crashes or blank screens on expected error conditions.
- No missing-icon warnings or white-screen launch.
- Clear feedback during the two operations the user must wait on (pose estimation, network fetch).

After Phase 11 merges, the Lite Version MVP is complete. Future work begins in the Pro Version phases (P1+).
