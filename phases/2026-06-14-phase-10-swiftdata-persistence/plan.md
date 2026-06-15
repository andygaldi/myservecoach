# Phase 10 — Plan

## Group 1 — SwiftData Models

1. Create `App/Models/SwiftData/ServeSession.swift` — `@Model` class with properties:
   - `id: UUID` (default `UUID()`)
   - `date: Date` (default `Date.now`)
   - `inputType: String`
   - `videoURL: URL?`
   - `@Relationship(deleteRule: .cascade) var phases: [ServePhase]` (default `[]`)

2. Create `App/Models/SwiftData/ServePhase.swift` — `@Model` class with properties:
   - `id: UUID` (default `UUID()`)
   - `phaseKey: String`
   - `label: String`
   - `frameImageData: Data`
   - `frameTimestamp: Double`
   - `referenceFrameURLs: [String]`
   - `var session: ServeSession?`

3. In `MyServeCoachApp.swift` (the `@main` struct), add `.modelContainer(for: ServeSession.self)` to the `WindowGroup`. SwiftData infers the full schema from the `@Relationship`.

## Group 2 — Persistence Logic

4. Create `App/Services/SessionPersistenceService.swift` — a simple struct (not a class, no `@Observable`) with one static or injected method:

   ```swift
   func save(
       session confirmedFrames: [ConfirmedPhaseFrame],
       referenceLibrary: ReferenceFrameLibrary,
       inputType: String,
       videoURL: URL?,
       into context: ModelContext
   )
   ```

   Implementation:
   - Instantiate `ServeSession` with `inputType` and `videoURL`.
   - For each `ConfirmedPhaseFrame`, instantiate `ServePhase`:
     - `frameImageData` = `frame.image.jpegData(compressionQuality: 0.85) ?? Data()`
     - `frameTimestamp` = `CMTimeGetSeconds(frame.timestamp)`
     - `referenceFrameURLs` = `referenceLibrary.referenceFrames[frame.phaseKey]?.map(\.imageURL.absoluteString) ?? []`
   - Append phases to `session.phases`.
   - Call `context.insert(session)`.
   - No explicit `try context.save()` needed — SwiftData auto-saves on the next run-loop turn; add it explicitly if immediate disk flush is required.

5. In `ComparisonView` (Phase 9), inject `@Environment(\.modelContext) private var modelContext` and call `SessionPersistenceService().save(...)` in `.onAppear` (guarded by a `alreadySaved` flag to prevent double-save on re-appear).

## Group 3 — `SessionHistoryView`

6. Create `App/Views/SessionHistoryView.swift`:
   - `@Query(sort: \ServeSession.date, order: .reverse) private var sessions: [ServeSession]`
   - `NavigationStack` wrapping a `List`:
     - Each row: `SessionHistoryRowView` (see step 7).
     - `.onDelete` modifier calls `context.delete(session)` for swipe-to-delete.
   - Empty state: `ContentUnavailableView("No Sessions Yet", systemImage: "clock")` when `sessions.isEmpty` (iOS 17+).
   - `NavigationTitle("History")`.

7. Create `App/Views/SessionHistoryRowView.swift`:
   - Accepts a `ServeSession`.
   - Displays: thumbnail from `session.phases.first(where: { $0.phaseKey == "trophy_pose" })?.frameImageData` decoded to `UIImage`; session date formatted as `"MMM d, yyyy · h:mm a"`; input type badge (`"Recorded"` / `"Imported"`) as a small secondary-color label.
   - Falls back to a gray rectangle if image data is missing or decode fails.

## Group 4 — `HistoryComparisonView`

8. Create `App/Views/HistoryComparisonView.swift`:
   - Accepts a `ServeSession`.
   - Reconstructs display data from persisted records:
     - User frames: `ServePhase.frameImageData` → `UIImage(data:)`
     - Reference frames: `ServePhase.referenceFrameURLs` → `[ReferenceFrame]` (map strings to `URL` then to `ReferenceFrame` structs)
   - Reuses `ComparisonPhaseRowView` and `ReferenceCarouselView` from Phase 9 — no new view components needed.
   - `NavigationTitle("Serve Comparison")` matching the live flow.

9. Wire `SessionHistoryView` list rows to `HistoryComparisonView` via `.navigationDestination(for: ServeSession.self)`.

## Group 5 — `TabView` App Root

10. Update `ContentView.swift` (or `MyServeCoachApp.swift` if the root view lives there) to wrap existing content in a `TabView`:

    ```swift
    TabView {
        RecordTabView()
            .tabItem { Label("Record", systemImage: "camera") }
        SessionHistoryView()
            .tabItem { Label("History", systemImage: "clock") }
    }
    ```

    `RecordTabView` is the existing `NavigationStack`-based new-session flow, extracted into its own view if it isn't already.

11. Ensure the existing `NavigationStack` for the record flow remains intact inside the Record tab — no changes to Phase 7/8/9 navigation behavior.

## Group 6 — Integration Smoke Test

12. Build and run on simulator or device.
13. Complete a full session (record/import → phase review → comparison screen).
14. Switch to the History tab — the completed session appears in the list with the correct date and trophy-pose thumbnail.
15. Tap the session — `HistoryComparisonView` opens showing all three phase rows; user frames load from stored Data; reference images load via `AsyncImage`.
16. Swipe to delete the session in the history list — it disappears and the empty state appears.
17. Confirm no regressions: the Record tab still flows through Phases 7→8→9 correctly; the comparison screen still appears after reference frame fetch.
