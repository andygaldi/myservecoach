# Phase 9 — Validation

Phase 9 is complete when all of the following pass.

## Backend

- [ ] `GET /reference-frames` returns each phase value as a JSON **array** (not a plain object).
- [ ] Each array element has `phase` (string), `label` (string), and `image_url` (valid URL string).
- [ ] `pytest backend/` passes with no failures (updated array assertions included).
- [ ] Every `image_url` in the response resolves: `curl <url>` returns HTTP 200 with a JPEG/PNG `Content-Type`.

## iOS — Unit Tests

- [ ] `ReferenceFrameLibrary` decodes correctly from a multi-frame JSON fixture (array per phase, ≥1 element each).
- [ ] `ReferenceFrameLibrary` decodes correctly from a single-frame fixture (one-element array per phase).
- [ ] `ComparisonView` renders without crashing when initialized with three `ConfirmedPhaseFrame` stubs and a `ReferenceFrameLibrary` stub (ViewInspector snapshot or XCTest host-app render test).

## iOS — Manual / Device Verification

- [ ] After confirming all three phase frames, `ComparisonView` is pushed automatically — no additional tap required.
- [ ] All three phase rows appear on the comparison screen: Trophy Pose, Racket Drop, Contact Point, in that order (scroll to verify all three).
- [ ] User's confirmed frame renders on the **left** side of every row — not blank, not a placeholder.
- [ ] Reference frame(s) render on the **right** side via `AsyncImage` — image loads within a reasonable time (≤5 s on a good connection); a loading indicator is visible while the image is fetching.
- [ ] When the backend returns more than one reference frame for a phase, the carousel is swipeable and page-indicator dots are visible.
- [ ] When only one reference frame exists per phase, no page-indicator dots appear and no swipe gesture is recognized.
- [ ] The navigation title reads "Serve Comparison".
- [ ] The back button returns to the last phase review step (the contact-point frame review screen), not to the home screen.

## Regression

- [ ] Phase 7 manual frame selection flow is unaffected: the phase review screens still present in order, user can still scrub and confirm each frame.
- [ ] Phase 8 network error alert still appears when the backend is unreachable (error is caught before navigation to `ComparisonView` — the comparison screen is never pushed on a failed fetch).
- [ ] App does not crash anywhere in the flow under normal conditions.

## Not Required for Merge

- Persisting the comparison session to SwiftData (Phase 10).
- Sharing or exporting the comparison screen.
- Coaching cues or text analysis alongside the frames.
- Remote / production hosting of reference frames (local dev server is sufficient).
- More than one curated reference image per phase (single-element arrays are valid).
