# Phase 5 — Video Library Import: Requirements

## Context

Assessment currently requires the user to record a new clip live. Phase 5 adds a second input path: selecting an existing video from the Photos library. The selected video feeds through the same Phase 2 pipeline (frame sampling → pose estimation → serve segmentation) so results and persistence are identical regardless of input source.

This is the first phase that touches the Assessment entry point. Phases 6–7 (calibration) depend on both input paths being available — real footage must be importable from external sources, not just captured live.

## Scope

- A source selection screen is presented at the start of every Assessment session.
- Two options: **Record new** (existing live-capture flow) and **Choose from library** (new).
- `PhotosPicker` (iOS 16+) is used to request a single video asset. The picker is configured to request video only — no full Photos library permission prompt.
- The selected video asset is exported to a local temp file, then handed to the existing Phase 2 `VideoAnalyzer` (or equivalent) exactly as a live-recorded file would be.
- If the pipeline returns zero segmented serves, an inline error message is shown: *"No serves detected. Try a different clip."* The user can return to source selection and try again.
- No UI polish (icons, transition animations) — deferred to Phase 11.
- No changes to the live-capture path behavior.

## Out of Scope

- iCloud video assets that require download before processing (out of scope for MVP; local assets only).
- Error handling beyond the zero-serves case (network errors, pose failures) — Phase 11.
- Multi-video selection.
- Any modification to the Phase 2 segmentation logic itself.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Picker API | `PhotosPicker` (PhotosUI, iOS 16+) | Matches tech-stack decision; video-only filter avoids full library permission |
| Asset export | `PHAsset` → temp URL via `AVAssetExportSession` or `PHImageManager` | Pipeline expects a file URL; must be local before processing begins |
| Zero-serves error | Inline message on results/transition screen | Non-disruptive; consistent with Phase 11 error-handling plan |
| UI polish | None | Strictly functional; Phase 11 covers all polish |
| Permission denial | Show inline explanation + settings deep-link | User must understand why the option is unavailable without a crash |

## Tech Stack Alignment

- **PhotosUI** — `PhotosPicker` with `.video` filter; iOS 16+ (min deployment is iOS 17).
- **Swift 6 strict concurrency** — asset export and pipeline handoff must be `async/await`; no callback pyramids.
- **SwiftUI MVVM** — source selection screen is a thin view; a `ViewModel` owns picker state and pipeline dispatch.
- **Phase 2 pipeline** — `VideoAnalyzer` (or equivalent service) is called with a `URL`; this phase must not change its interface, only its callers.
