# Phase P6b — Segmentation Robustness & Empty-Clip Detection (2D) — Requirements

## Scope

Close all three `segment_serves` known gaps disclosed at the end of Phase P6 (see
`specs/roadmap.md` P6): (1) an all-idle clip never returns an empty segment list, so the
already-built-and-tested `ProServeAnalysisError.noSegmentsDetected` path is unreachable from the
real backend; (2) a player with an elaborate pre-serve routine (multiple ball bounces, grip
adjustments) can false-split one genuine serve into two; (3) Photos-library imports bypass the Pro
2D live-capture 1280×720@30fps lock entirely, since `LibraryVideoExporter.copyToTemp` does a byte
copy with no re-encoding. Scheduled ahead of P7 because P7's continuous multi-serve capture
inherits all three bugs.

## In Scope

- **Empty-clip detection (backend)** — `segment_serves` (`backend/app/engine/phases.py`) returns
  `[]` when `has_seen_active` never becomes `True` across the whole frame list, i.e. per-frame
  velocity never crosses `LOW_MOTION_VELOCITY_THRESHOLD` anywhere in the clip. Reuses the exact
  motion signal the function already computes — no new heuristic. New unit test(s) in
  `backend/tests/test_segment_serves.py` covering an all-idle synthetic sequence. No change needed
  to `POST /v1/segment/video` (`backend/app/routers/segment.py`) or `SegmentResponse` — an empty
  `segment_serves` result already flows through as `SegmentResponse(segments=[])`, which iOS's
  existing `guard !segments.isEmpty else { throw ProServeAnalysisError.noSegmentsDetected }`
  (`ProServeAnalysisPipeline.swift:35-39`) already handles correctly and already has passing tests
  for.
- **False-split mitigation (backend), hard merge gate** — add synthetic multi-pause test fixtures
  to `test_segment_serves.py` reproducing the false-split failure mode (one continuous serve
  interrupted by a rest gap at or above `MIN_REST_SECONDS`, simulating a mid-routine ball-bounce or
  grip-adjustment pause). Find a fix that measurably reduces false splits on the synthetic fixtures
  without regressing any real calibration video's expected serve count
  (`backend/tools/segmentation_ground_truth.json`) or any existing `test_segment_serves.py`/
  `test_segmentation_ground_truth.py` case. Not limited to retuning
  `MIN_REST_SECONDS`/`LOW_MOTION_VELOCITY_THRESHOLD` — if simple threshold retuning can't satisfy
  both constraints, broaden the investigation to other signals/heuristics (e.g. a
  minimum-active-run-length requirement before a rest gap counts as a boundary, similar in spirit
  to P4b's willingness to reopen heuristic formulas rather than just their weights). If still stuck
  after a genuine broadened attempt, stop and ask the user for direction rather than merging with
  the gap unresolved or silently downgrading this to best-effort — see Key Decisions.
- **Import normalization (iOS)** — re-encode Photos-library-imported Pro 2D clips to
  1280×720@30fps before segmentation, matching the resolution/fps `segment_serves` is validated
  against and `CameraService`'s existing Pro 2D live-capture lock. Implemented via
  `AVAssetExportSession` + `AVMutableVideoComposition` inside `runProPipeline`
  (`VideoSourceSelectionViewModel.swift`), gated on `inputType == "imported"` — recorded Pro 2D
  clips already arrive correctly locked via `CameraService` and skip this step. Lite's import path
  (`runLitePipeline`, `LibraryVideoExporter.copyToTemp`) is completely unmodified.

## Out of Scope

- **`segment_serves`'s time-based architecture, the `ServePhase` enum, or `detect_phases`.** This
  phase tunes robustness, not architecture — same posture as P4b.
- **Collecting real hand-labeled elaborate-pre-serve-routine footage.** Not available this phase;
  the false-split mitigation is validated against synthetic fixtures plus the existing real
  calibration videos, not new real elaborate-routine footage. A true confirmation against real
  multi-bounce footage (per the original P6 known-gap text: "proper P4b-style calibration with a
  larger hand-labeled dataset covering varied player routines") remains future work if such footage
  becomes available later — but the fix itself, validated as best as current data allows, is a hard
  merge gate for this phase (see Key Decisions).
- **Re-encoding recorded (non-imported) Pro 2D clips.** Already correctly locked at capture via
  `CameraService`; re-encoding them would be redundant work with no correctness benefit.
- **Any change to Lite's import/copy path, `PhaseReviewView`, the Lite pipeline/segmentation
  services, or `ContentView`.** Isolation rule, unconditional.
- **`rules.json` / rule calibration.** Still P5's domain, unaffected by this phase.
- **P7 Set Goal mode itself.** This phase only removes blockers P7 would otherwise inherit.
- **New backend endpoints or response schema changes.** `segment_serves`'s empty-list behavior
  already surfaces correctly through the existing `/v1/segment/video` endpoint and
  `SegmentResponse` shape; no `models.py`/router changes are needed.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Empty-clip rule | `segment_serves` returns `[]` when `has_seen_active` never becomes `True` across the whole clip | User confirmed — reuses the existing velocity-threshold signal already computed inside `segment_serves`, no new heuristic invented. |
| False-split footage | No new real footage this phase; tune against existing `calibration_data/` + synthetic multi-pause fixtures | User confirmed — matches P4b's precedent of absorbing footage if available without blocking scope on footage that doesn't exist yet. |
| False-split fix, merge gate | Hard merge gate — must measurably reduce synthetic false splits without regressing any real video's expected serve count. Not limited to `MIN_REST_SECONDS`/`LOW_MOTION_VELOCITY_THRESHOLD`; broaden to other signals/heuristics if simple retuning fails; ask the user for direction if still stuck after a genuine attempt | User explicitly upgraded this from a best-effort/disclosable gap to a hard gate — this bug is the direct cause of the false-split issue P7 would otherwise inherit, so it should not ship half-fixed. |
| Import re-encode target | `AVAssetExportSession` + `AVMutableVideoComposition` forcing 1280×720@30fps | User confirmed — matches the resolution/fps `segment_serves` is validated against, the same target `CameraService` already locks live Pro 2D recording to. |
| Re-encode gating | Only when `inputType == "imported"`, inside `runProPipeline`; recorded clips skip re-encoding | Recorded Pro 2D clips are already captured at 1280×720@30fps via `CameraService`'s existing lock — re-encoding them would be redundant work with no correctness benefit. `runPipeline(on:inputType:)` already threads `inputType` ("recorded" vs. "imported") through to `runProPipeline`, so this needs no new plumbing. |
| Temp file cleanup | Re-encode writes to a new temp URL; both the original copied-import temp file and the intermediate re-encoded file are removed on error, and the re-encoded file replaces `pendingVideoURL` on success | Avoids leaking two temp files per Pro 2D imported session — extends `runProPipeline`'s existing url-removal-on-error discipline to the new intermediate file. |

## Context

- **P6's two Known-gap TODOs** (`specs/roadmap.md`) are the direct source of this phase's scope.
  Gap 1 (empty-clip): `segment_serves` has no explicit "at least one segment" guard — it's
  structural. `boundaries` only grows inside the loop, and `segments.append(frames[start:])`
  (`phases.py:93`) always executes once after the loop, unconditionally appending whatever remains
  as a final segment — even a clip of pure idle/noise where `has_seen_active` never fires. Gap 2/3
  (false-split, import normalization) are documented in the same P6 known-gap blockquote, alongside
  the investigation that produced the Pro 2D camera lock in the first place (5 real clips tested;
  60fps/4K clips under-segmented identically, 30fps clips did not).
- **No existing "no serves" case anywhere.** `backend/tools/segmentation_ground_truth.json` has 7
  videos, each with ≥1 expected serve — no empty-clip entry exists, and
  `backend/tests/test_segment_serves.py` has no all-idle test today. This phase's synthetic
  fixtures are the first coverage of that case.
- **`LibraryVideoExporter.copyToTemp`** (`App/Services/Video/LibraryVideoExporter.swift:17-23`) is
  a plain `FileManager.copyItem(at:to:)` — no re-encoding, no `AVFoundation` import at all in that
  file today. `AVAssetExportSession`/`AVMutableVideoComposition`/`AVAssetWriter`/`AVAssetReader` are
  used nowhere in production code in this app (only in a test fixture builder,
  `FrameSamplerServiceTests.swift`'s `makeTestVideo` helper) — this phase introduces the app's
  first production re-encode surface.
- **`copyToTemp` happens before the Lite/Pro branch, inside `Transferable` machinery** — it is
  `nonisolated static` and mode-unaware, called from `LibraryMovie.importing` during
  `PhotosPickerItem.loadTransferable`, well before `VideoSourceSelectionViewModel.runPipeline`
  switches on `selectedMode`. Gating re-encoding at that layer would require threading mode
  awareness into `LibraryVideoExporter` itself; gating inside `runProPipeline` instead (after the
  byte-copied `url` already exists, before `proPipeline.analyze(videoURL:)` is called) achieves the
  same mode-isolation with no change to `LibraryVideoExporter` or the Lite path at all.
- **`CameraService`'s Pro 2D lock** (`CameraService.swift:84-125`) sets `session.sessionPreset =
  .hd1280x720` and locks `activeVideoMinFrameDuration`/`activeVideoMaxFrameDuration` to 30fps, but
  only for live capture (`sessionMode == .pro2D`) — it has no effect on Photos-library-selected
  videos, which is exactly the gap this phase's import-normalization work closes.
- **Three-mode isolation rule** (`specs/mission.md`, `specs/tech-stack.md`): this phase's code is
  Pro-2D-only and additive, same as P4/P4b/P6. It must not modify `PhaseReviewView`, the Lite
  pipeline/segmentation services, `LibraryVideoExporter.copyToTemp`'s existing behavior, or
  `ContentView`.
