# Phase 7 — Manual Frame Selection UI: Requirements

## Goal

After Phase 2 pose estimation produces guessed phase frames, present a sequential review screen where the user confirms (or corrects) the frame for each serve phase before comparison. The confirmed frames become the canonical phase frames for the session — all downstream steps use these, not the raw Vision output.

## Scope

### Phase Review Flow

- Presented immediately after pose estimation completes.
- Steps through the three phases in order: **trophy pose → racket drop → contact point**.
- One phase per screen step (sequential, not all three at once).
- Back/Next navigation between steps; final step has a **Done** button.
- All three phases must be confirmed before Done is enabled — no skipping.

### Per-Step Screen

- Phase label (e.g. "Trophy Pose — Step 1 of 3") at the top.
- Thumbnail of the currently set frame displayed above the video player.
- Inline **AVPlayer** showing the full recorded/imported clip with a seek bar.
- **"Use This Frame"** button: captures the player's current time, renders a still from the asset via `AVAssetImageGenerator`, and updates the confirmed frame for this phase.
- Next is disabled until the user has tapped "Use This Frame" at least once for the current step.

### No-Guess Fallback

- When Vision returns no confident guess for a phase, the player's initial seek position is set to the **video midpoint**.
- A label reads "No pose detected — pick manually" to explain why no frame is pre-selected.

### Output

- Three confirmed `PhaseFrame` values (phase key + `CMTime` + thumbnail `UIImage`).
- Passed downstream to the Phase 8 reference frame fetch.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Layout | One phase at a time | Keeps user focused; simpler confirmation state |
| Scrub mechanism | Inline AVPlayer + "Use This Frame" | User can see motion, not just stills |
| Skip allowed? | No — all three required | Downstream comparison requires all phases |
| No-guess fallback | Midpoint, required pick | Avoids silent omissions; user is always aware |

## Out of Scope

- Re-editing a confirmed frame after tapping Done (no back-from-results editing).
- Displaying Vision confidence scores to the user.
- Thumbnail strip / frame grid scrubbing (deferred).
- Playback speed controls.
