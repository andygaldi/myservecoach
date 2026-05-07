# Phase 5 — Video Library Import: Plan

Each task group produces working, committable code before the next begins.

---

## Group 1 — Source Selection Screen

1. Create `VideoSourceSelectionView` (SwiftUI) with two buttons: "Record new" and "Choose from library".
2. Create `VideoSourceSelectionViewModel` holding picker-presented state and navigation triggers.
3. Wire the "Record new" button to navigate to the existing camera/recording screen (no behavior change).
4. Wire the "Choose from library" button to present `PhotosPicker` (placeholder action for now — wired in Group 2).
5. Insert `VideoSourceSelectionView` as the Assessment entry point, replacing the direct launch into the camera screen.

**Commit checkpoint:** Source selection screen appears at Assessment start; "Record new" path works end-to-end.

---

## Group 2 — PhotosPicker Integration

1. Add `PhotosUI` import and configure `PhotosPicker` with a `.video` filter in `VideoSourceSelectionViewModel`.
2. Handle picker dismissal without selection (no-op, stay on source selection screen).
3. Handle Photos permission denial: show an inline explanation and a Settings deep-link using `UIApplication.open`.
4. On successful selection, receive `PhotosPickerItem` and trigger asset export (stub — implemented in Group 3).

**Commit checkpoint:** Picker opens, video-only filter confirmed, permission denial shows explanation + Settings link.

---

## Group 3 — Asset Export to Temp URL

1. Implement `PhotosPickerItem` → `AVAsset` → temp file URL export using `loadTransferable` or `PHImageManager` + `AVAssetExportSession`.
2. Export as `.mov` or `.mp4` to the app's temp directory.
3. Clean up the temp file after the pipeline completes (success or error).
4. Pass the temp URL into the existing Phase 2 pipeline entry point (`VideoAnalyzer` or equivalent).

**Commit checkpoint:** Selected library video is exported to a local temp URL and handed to the Phase 2 pipeline; keypoints logged to console.

---

## Group 4 — Zero-Serves Error State

1. Detect the zero-segmented-serves case after pipeline completion.
2. Display an inline error message in `VideoSourceSelectionView` (or a transitional screen): *"No serves detected. Try a different clip."*
3. Reset state so the user can select a different video or switch to recording.

**Commit checkpoint:** Selecting a non-serve video surfaces the inline error; user can retry without restarting the app.

---

## Group 5 — Tests & Verification

1. Unit test: asset export produces a valid file URL for a known video fixture.
2. Unit test: zero-serves path triggers the error state (mock pipeline returning empty array).
3. Manual test on device: live-recording path unaffected end-to-end.
4. Manual test on device: library video selected → segmented serves logged → same results as equivalent live recording.
5. Manual test: Photos permission denial handled gracefully.
