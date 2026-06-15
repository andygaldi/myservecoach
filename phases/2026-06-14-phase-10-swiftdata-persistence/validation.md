# Phase 10 — Validation

Phase 10 is complete when all of the following pass.

## SwiftData Models

- [ ] `ServeSession` and `ServePhase` compile as `@Model` classes with no warnings.
- [ ] `.modelContainer(for: ServeSession.self)` is present in `MyServeCoachApp` and the app launches without a SwiftData schema error.
- [ ] Cascade delete: deleting a `ServeSession` in the model context also removes all its child `ServePhase` records (verify via a unit test or debugger inspection — no orphan rows).

## Persistence Logic

- [ ] After completing the full flow and reaching `ComparisonView`, exactly one `ServeSession` is inserted into the model context (not zero, not two on re-appear).
- [ ] That `ServeSession` has exactly three child `ServePhase` records (one per phase key: `trophy_pose`, `racket_drop`, `contact`).
- [ ] Each `ServePhase.frameImageData` decodes back to a non-nil `UIImage`.
- [ ] Each `ServePhase.referenceFrameURLs` is non-empty and contains valid URL strings.
- [ ] `inputType` is `"recorded"` when the session came from the live camera and `"imported"` when it came from the Photos picker.

## `SessionHistoryView`

- [ ] History tab is visible in the `TabView` and tapping it shows the history list.
- [ ] After saving a session, the History tab shows exactly one row without requiring an app restart.
- [ ] The row displays: a non-blank trophy-pose thumbnail, the formatted session date, and an input-type badge.
- [ ] Completing a second session appends a second row; sessions are ordered most-recent-first.
- [ ] Swipe-to-delete removes the row and all child phases from the store; the row does not reappear after the swipe.
- [ ] When no sessions exist, the empty state (`"No Sessions Yet"`) is shown instead of a blank list.

## `HistoryComparisonView`

- [ ] Tapping a history row opens `HistoryComparisonView` with the navigation title `"Serve Comparison"`.
- [ ] All three phase rows render: Trophy Pose, Racket Drop, Contact Point, in that order.
- [ ] The user's frame image on the left loads from stored `Data` — not blank, not a placeholder.
- [ ] Reference frame images on the right load via `AsyncImage` from the stored URLs; loading indicators appear while fetching.
- [ ] Back button returns to the history list (not to the Record tab root).
- [ ] Re-opening a session works offline (user frames render; reference images may fail to load if backend is unreachable — that is acceptable).

## Record Tab — No Regressions

- [ ] The Record tab still presents the existing new-session flow unchanged (video input → pose estimation → phase review → comparison).
- [ ] Phase 7 manual frame selection still works normally inside the Record tab.
- [ ] Phase 8 reference frame fetch still works; network error alert still appears when the backend is unreachable.
- [ ] Phase 9 `ComparisonView` still appears after all three frames are confirmed and reference frames are fetched.
- [ ] App does not crash under normal conditions anywhere in either tab.

## Not Required for Merge

- iCloud sync or cross-device session access.
- Session search, filter, or sort controls.
- Exporting or sharing comparison screenshots.
- Coaching cues alongside history session frames.
- SwiftData migration handling (no schema changes from a prior shipped version).
