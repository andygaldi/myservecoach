# Phase 10 — SwiftData Persistence

## Scope

Persist every completed serve comparison session to on-device storage and expose a history list screen where the user can browse past sessions and re-open the side-by-side comparison view.

A session is persisted at the moment `ComparisonView` first appears (after reference frames are fetched and all three phases are confirmed). No backend changes are required.

## SwiftData Models

### `ServeSession`

Top-level record for one serve comparison session.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | Primary key |
| `date` | `Date` | When the session was saved |
| `inputType` | `String` | `"recorded"` or `"imported"` |
| `videoURL` | `URL?` | Original video URL; may become stale if video is deleted from Photos |
| `phases` | `[ServePhase]` | Child records; relationship with cascade delete |

### `ServePhase`

One confirmed phase frame within a session.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | Primary key |
| `phaseKey` | `String` | `"trophy_pose"` \| `"racket_drop"` \| `"contact"` |
| `label` | `String` | Display label (e.g. `"Trophy Pose"`) |
| `frameImageData` | `Data` | PNG/JPEG encoding of the user's confirmed `UIImage`; persisted at save time so history renders even if the source video is deleted |
| `frameTimestamp` | `Double` | CMTime seconds value; stored for reference/debugging |
| `referenceFrameURLs` | `[String]` | Ordered list of reference frame URL strings for this phase; sourced from the fetched `ReferenceFrameLibrary` at save time; no extra network call needed when re-opening |
| `session` | `ServeSession` | Back-reference to parent |

## Navigation Structure

A `TabView` is added at the app root with two tabs:

- **Record** (camera icon) — the existing new-session flow (video input selection → pose estimation → phase review → comparison)
- **History** (clock/list icon) — the new `SessionHistoryView`

`ContentView` (or the app root) is updated to host the `TabView`. The existing `NavigationStack` for the record flow lives inside the Record tab.

## History Screen (`SessionHistoryView`)

- `List` of `ServeSession` records, sorted by `date` descending (most recent first).
- Each row: session date (formatted), input type badge (`Recorded` / `Imported`), and the user's trophy-pose frame image as a thumbnail.
- Empty state: centered text and icon when no sessions exist yet.
- Tapping a row navigates to `HistoryComparisonView`.

## Re-opening a Session (`HistoryComparisonView`)

Reuses `ComparisonView` visually. Reconstructs the data it needs from persisted `ServePhase` records:

- User frame: decoded from `frameImageData` → `UIImage`.
- Reference frames: `referenceFrameURLs` strings → `[ReferenceFrame]` structs with `AsyncImage` URLs.

No backend call is made when re-opening a session. `AsyncImage` loads reference images from the stored URLs; if the backend is offline the images will fail to load (same behavior as the live flow — this is acceptable per the MVP "network required" policy).

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Frame image storage | `Data` in SwiftData | History renders correctly even if source video is deleted from Photos; avoids re-extraction latency |
| Reference frame storage | URL strings in SwiftData | No extra network round-trip to open history; image bytes still loaded lazily by `AsyncImage`; smaller storage footprint than full image Data |
| History navigation | `TabView` at app root | Standard iOS pattern; clean separation between new-session flow and history; easy to extend in Phase 11 |
| Persistence trigger | On `ComparisonView` appear | Session is only saved once the user has reached the payoff screen; partial flows (cancelled phase reviews, failed fetches) produce no history entry |
| SwiftData container | `.modelContainer(for:)` in `@main` | Single shared container; no custom migration in MVP |
| Delete sessions | Swipe-to-delete in history list | Standard `List` behavior; cascade delete removes child `ServePhase` records |

## Out of Scope

- iCloud sync or cross-device history
- Editing or renaming a saved session
- Exporting or sharing comparison screenshots
- Session search or filtering
- Coaching cues or text analysis (Phase 11 polish)
- Multiple recording angles
