# Phase 9 — Side-by-Side Comparison Screen

## Scope

Dedicated SwiftUI results screen that displays the user's three confirmed phase frames alongside reference frames fetched in Phase 8. This is the payoff screen for the Lite MVP: the user sees, side by side, how their trophy pose / racket drop / contact point compares to a high-quality server.

The screen is pushed onto the existing `NavigationStack` immediately after the Phase 8 reference frame fetch succeeds (end of the phase review flow). The back button returns to the last phase review step.

No new networking is introduced. The screen consumes the `ReferenceFrameLibrary` already held in the phase review view model from Phase 8.

## Layout

Vertically scrollable list with three section rows, one per phase, in order:

1. Trophy Pose
2. Racket Drop
3. Contact Point

Each row layout:
- Phase label (e.g. "Trophy Pose") as a section header above the image pair.
- User's confirmed frame on the **left**, reference frame(s) on the **right**.
- Both sides are equal width, filling the screen horizontally.
- Frames are displayed at a fixed aspect ratio (match the source image aspect ratio; do not crop).

## Reference Frame Carousel

The backend may return multiple reference frames per phase. The right-hand side of each row is a horizontally swipeable `TabView`-style carousel. If only one reference frame exists for a phase, the carousel shows that single frame with no swipe affordance. A page indicator (dots) is shown below the carousel when there are two or more frames.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Layout | Vertical `ScrollView` with one row per phase | Matches roadmap spec; all three comparisons visible on a single scrollable canvas |
| Navigation | Pushed onto `NavigationStack` | Consistent with existing nav stack from phase review; back returns to last review step |
| Reference carousel | `TabView(.page)` with dot indicator | Native SwiftUI paging with zero third-party dependencies; degrades gracefully to a single static image |
| Image loading | `AsyncImage` with a loading placeholder | Reference frames are remote URLs (Phase 8 contract); user frames are local `UIImage` from the captured video frame |
| User frame source | `UIImage` from `ConfirmedPhaseFrame.image` | Phase 7 already captures the frame image at confirmation; no second disk read needed |
| Empty / error state | Not applicable | Screen is only reachable after a successful fetch (Phase 8 already surfaces network errors before navigation) |

## Data Model Consumed

```swift
// From Phase 7 — user's confirmed frames
struct ConfirmedPhaseFrame {
    let phaseKey: String   // "trophy_pose" | "racket_drop" | "contact"
    let label: String
    let image: UIImage
    let timestamp: CMTime
}

// From Phase 8 — fetched reference frames
struct ReferenceFrame: Codable {
    let phase: String
    let label: String
    let imageURL: URL
}

struct ReferenceFrameLibrary: Codable {
    let referenceFrames: [String: [ReferenceFrame]]  // array per phase key
}
```

> **Note on Phase 8 contract**: Phase 8 implemented `[String: ReferenceFrame]` (single frame per phase). The backend needs to be updated to return `[String: [ReferenceFrame]]` (array) to support the carousel. This is a non-breaking expansion — if the backend returns a single object, the iOS decoder wraps it in a one-element array. The backend change is in scope for this phase.

## Navigation Entry Point

`PhaseReviewViewModel` (Phase 7/8) already holds:
- `confirmedFrames: [ConfirmedPhaseFrame]` — set when user confirms each phase
- `referenceLibrary: ReferenceFrameLibrary?` — set after successful Phase 8 fetch

When `referenceLibrary` is set (non-nil), the view model sets a `showComparison: Bool` flag that triggers a `NavigationLink` or `.navigationDestination` push to `ComparisonView`.

## Out of Scope

- Persisting comparison session data to SwiftData (Phase 10)
- Sharing or exporting the comparison screen
- Any coaching cues or textual analysis alongside the frames
- Pose skeleton overlay on frames
- Multiple recording angles
