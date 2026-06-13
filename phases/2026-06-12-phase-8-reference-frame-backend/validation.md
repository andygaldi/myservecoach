# Phase 8 — Validation

Phase 8 is complete when all of the following pass.

## Backend

- [ ] `GET /reference-frames` returns HTTP 200 with valid JSON.
- [ ] Response contains exactly three top-level keys under `reference_frames`: `trophy_pose`, `racket_drop`, `contact`.
- [ ] Each entry contains `phase` (string), `label` (string), and `image_url` (valid URL string).
- [ ] Each `image_url` resolves: `curl <url>` returns HTTP 200 with a JPEG/PNG `Content-Type`.
- [ ] `pytest backend/` passes with no failures.

## iOS

- [ ] `ReferenceFrame` and `ReferenceFrameLibrary` decode correctly from a sample JSON fixture in a unit test.
- [ ] `ReferenceFrameService.fetchReferenceFrames()` succeeds against the locally running backend (log output visible in Xcode console after phase confirmation).
- [ ] When the backend is unreachable (stopped), an error alert appears within a reasonable timeout (≤15 s) — no crash, no silent failure.
- [ ] Tapping Retry in the error alert re-fires the fetch; if the backend is restored, the fetch succeeds.

## Integration (on device or simulator)

- [ ] Full flow completes end-to-end: record or import video → pose estimation → manual phase review → confirm all three frames → reference frames fetched → URLs logged to console.
- [ ] No regressions in the Phase 7 manual frame selection UI (phase review still works normally before the fetch fires).
- [ ] App does not crash or hang at any point in the flow.

## Not Required for Merge

- Displaying reference frames in a comparison UI (Phase 9).
- Persisting reference frame URLs (Phase 10).
- Fetching from a remote host (local dev server is sufficient).
