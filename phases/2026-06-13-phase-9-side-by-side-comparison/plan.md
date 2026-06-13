# Phase 9 — Plan

## Group 1 — Backend: Expand Reference Frame Response to Array

1. Update `GET /reference-frames` in `backend/main.py` to return each phase as an array of frame objects instead of a single object. This supports the carousel while remaining backward-compatible (existing single-frame data becomes a one-element array).

   New response shape:
   ```json
   {
     "reference_frames": {
       "trophy_pose": [
         { "phase": "trophy_pose", "label": "Trophy Pose", "image_url": "..." }
       ],
       "racket_drop": [...],
       "contact": [...]
     }
   }
   ```

2. Add any additional curated reference images to `backend/static/reference_frames/` (e.g. `trophy_pose_2.jpg`) if more than one reference per phase is ready. If only one image is available per phase, the array will have one element — that is a valid production state.

3. Update `backend/tests/test_reference_frames.py`:
   - Each phase value is now a JSON array (not an object).
   - Each array element has `phase`, `label`, and `image_url`.
   - Existing count/key assertions still hold.

4. Run `pytest backend/` — all tests pass.

## Group 2 — iOS: Update `ReferenceFrameLibrary` Codable Model

5. In `App/Models/`, change `ReferenceFrameLibrary.referenceFrames` from `[String: ReferenceFrame]` to `[String: [ReferenceFrame]]`.

6. Update any Phase 8 call sites that index into `referenceFrames` (e.g. `library.referenceFrames["trophy_pose"]`) to handle the array. Phase 8 only logs URLs to the console — update those log statements to iterate the array.

7. Add or update the unit test that decodes a sample JSON fixture: fixture now has arrays; decoding must succeed and produce the correct element counts.

## Group 3 — iOS: `ReferenceCarouselView` Component

8. Create `App/Views/ReferenceCarouselView.swift` — a self-contained SwiftUI view that:
   - Accepts `frames: [ReferenceFrame]`.
   - Uses `TabView(selection:)` with `.tabViewStyle(.page(indexDisplayMode: .automatic))`.
   - Each page is an `AsyncImage` rendering the `imageURL`, with a `ProgressView` placeholder while loading and a gray rectangle on error.
   - When `frames.count == 1`, the `TabView` renders without visible page dots (`.indexDisplayMode(.never)`).
   - Fixed aspect ratio container (e.g. `aspectRatio(3/4, contentMode: .fit)`) so all frames are the same height regardless of source dimensions.

## Group 4 — iOS: `ComparisonPhaseRowView` Component

9. Create `App/Views/ComparisonPhaseRowView.swift` — one row in the comparison list:
   - Section header: phase label text (`"Trophy Pose"`, `"Racket Drop"`, `"Contact Point"`), bold, left-aligned.
   - Two-column `HStack` below the label:
     - Left: user's `UIImage` wrapped in `Image(uiImage:).resizable().scaledToFit()` inside the same fixed aspect ratio container.
     - Right: `ReferenceCarouselView(frames: referenceFrames)`.
   - "You" / "Reference" sub-labels below each column in a smaller, secondary color.
   - A `Divider` below the row to visually separate phases.

## Group 5 — iOS: `ComparisonView` (Main Screen)

10. Create `App/Views/ComparisonView.swift`:
    - `NavigationTitle("Serve Comparison")` with `.navigationBarTitleDisplayMode(.inline)`.
    - `ScrollView(.vertical)` containing a `VStack(spacing: 24)` of three `ComparisonPhaseRowView` instances, one per phase in order: trophy pose → racket drop → contact.
    - Receives `confirmedFrames: [ConfirmedPhaseFrame]` and `referenceLibrary: ReferenceFrameLibrary` as init parameters.
    - Resolves each phase by matching `confirmedFrames[i].phaseKey` to `referenceLibrary.referenceFrames[phaseKey] ?? []`.
    - Order is fixed: `["trophy_pose", "racket_drop", "contact"]`.

## Group 6 — iOS: Wire Navigation

11. In the Phase 7/8 view or view model, add a `.navigationDestination(isPresented: $showComparison)` that presents `ComparisonView` when `referenceLibrary` is set and the user has confirmed all three frames.
12. Set `showComparison = true` in the existing completion handler that fires after the Phase 8 fetch succeeds (replacing or extending the console log).
13. Verify the back button returns to the last phase review step (no changes needed if using `NavigationStack` push — confirm default behavior).

## Group 7 — Integration Smoke Test

14. Start the FastAPI backend locally (`uvicorn backend.main:app --reload`).
15. Build and run on device or simulator.
16. Complete the full flow: record/import → pose estimation → phase review → confirm all three frames → reference frames fetched → `ComparisonView` appears automatically.
17. Confirm:
    - All three phase rows are visible by scrolling.
    - User's frame renders on the left for each phase (correct frame, not blank).
    - Reference frame(s) render on the right; carousel dots appear if more than one image exists for any phase; swiping cycles through frames.
    - Back button returns to the phase review screen.
18. No regressions: re-run Phase 7 manual frame selection to confirm it still works normally (phase review is unaffected by the navigation addition).
