# Phase 5 — Video Library Import: Validation

The phase is complete and ready to merge when all criteria below pass.

---

## Merge Criteria

### 1. Source picker screen exists
- Launching an Assessment session shows a screen with distinct "Record new" and "Choose from library" options.
- Neither option is hidden, disabled, or requires additional navigation to reach.

### 2. Library video flows through Phase 2 pipeline
- Selecting a video from the Photos library exports it to a local temp URL.
- The temp URL is passed to the same `VideoAnalyzer` (or equivalent) entry point used by live recording.
- Frame sampling, pose estimation, and serve segmentation run identically.
- Segmented keypoint arrays are produced and logged (or surfaced) in the same format as the live-recording path.

### 3. No regression on live recording
- Tapping "Record new" navigates to the existing camera screen with no behavior changes.
- A full live-recording → segmentation flow completes end-to-end as it did before Phase 5.
- No new crashes, layout regressions, or unexpected state in the live path.

### 4. PhotosPicker permission handling
- The picker is configured to request video assets only — no full Photos library permission prompt is shown.
- If the user denies Photos access, an inline explanation is displayed alongside a link to Settings.
- The app does not crash or hang on denial.

---

## Additional Checks (non-blocking but expected)

- Temp file is cleaned up after pipeline completion (no unbounded disk growth).
- Zero-serves case surfaces the inline error message and allows the user to retry.
- Unit tests for asset export and zero-serves error path are green (`xcodebuild test` or equivalent).
