# Phase P6c — Assessment Results Visualization (2D) — Requirements

## Scope

Turn the Pro 2D Assessment results screen from a flat, per-serve list of cue text into an
aggregate, visual assessment. Three coordinated changes: (1) the backend stops discarding the
deviation and phase-timing data it already computes and surfaces it on `AnalyzeResponse`/`Cue`;
(2) iOS retains the four coaching-relevant phase frames per serve — image, keypoints, and
detections — and persists them alongside cues; (3) the results screen gains a cross-serve
aggregate section and a net-new `Canvas`-based pose-skeleton + deviation overlay renderer drawn
on each phase frame.

The overlay work is P13's "skeleton on results-screen keyframes" pulled forward; P13 is narrowed
to the pre-recording live-feed overlay only (already reflected in `specs/roadmap.md`).

## In Scope

### Backend — surface computed deviation and phase timing

- **`Cue` gains deviation fields** (`backend/app/models.py`): `metric`, `joints`,
  `measured_value`, `comparison`, `threshold`, `threshold_min`, `threshold_max`. Every one of
  these is already available inside `evaluate_rules` (`backend/app/engine/rules.py:109-133`) —
  `value` comes back from `compute_metric_value` and is currently used only for the `_passes`
  check and then dropped; the rest are fields on the matched `_Rule`. No new computation, no new
  math, no rules.json change.
- **`AnalyzeResponse` gains `phases`** (`backend/app/models.py`): a list of `PhaseDetection`
  entries (`phase`, `frame_index`, `timestamp`) for every phase `detect_phases` resolved to a
  non-`None` frame. `analyze.py` already holds the full `phase_frames` dict and today reads only
  `trophy_pose is not None` from it for the clean-serve summary; the frame index is recovered by
  matching the phase frame's `timestamp` against `request.frames`.
- **Wire-format only.** `detect_phases` and `evaluate_rules`' detection/evaluation logic,
  `rules.json` thresholds, and the segmentation path are all unchanged — this phase makes existing
  results visible, it does not change any result.
- **Keypoints are not re-sent.** iOS already holds every segment's `frames` (and `detections`)
  from `POST /v1/segment/video` before it calls `/v1/analyze`; the returned `timestamp` is enough
  to look the frame up client-side. Duplicating keypoints in `AnalyzeResponse` would be dead
  payload.

### iOS — retain phase frames, keypoints, and detections

- **`AssessmentServeResult` carries phase frames.** For each serve, for the four coaching-relevant
  phases — `release`, `trophy_pose`, `racket_drop`, `contact` — retain the phase frame's
  `BackendFrame` (keypoints), the `[BackendDetection]` at that timestamp, and a JPEG image
  extracted from the analyzed video at the returned timestamp via `FrameThumbnailGenerator`.
  Retained for **every** serve, not only serves with cues, so a clean serve still shows its motion.
  `start` and `finish` are detected by the backend and returned in `phases` but are not extracted
  or displayed.
- **SwiftData persistence.** A new `PhaseFrameRecord` child of `ServeResult` mirroring Lite's
  `PhaseRecord.frameImageData` pattern, holding the phase key, timestamp, JPEG data, and the
  keypoints/detections encoded as JSON `Data`. `CueRecord` gains the deviation fields so history
  replay can render the same overlay and "measured X · target Y" text.

### iOS — aggregate cue view

- **Cross-serve aggregate section** at the top of `AssessmentResultView`, below the existing
  header: cues grouped by `ruleId` across all serves, each row showing the message, the flagged
  count ("3 of 4 serves"), and the phase — ordered major-before-minor then by frequency. The
  existing per-serve sections are retained below, now carrying frame images and overlays.

### iOS — skeleton + deviation overlay renderer

- **Net-new `Canvas`/`Path` renderer** (no overlay renderer exists in the iOS app today). Draws
  the full pose skeleton dimmed over the extracted phase frame, with the specific joints/segment
  the violated rule measured highlighted in the severity color, plus a visual indicator of the
  rule's ideal: a dashed ray/arc for `angle` and `angle_from_vertical`, a shaded target band for
  `y_diff`/`x_diff`, and a target box plus ball marker for `ball_offset_x`/`ball_offset_y`.
- **Live-drawn, not baked.** The persisted image is the clean frame; the overlay is drawn at
  display time from the persisted keypoints. Restyling the overlay later re-renders already-saved
  sessions correctly.

### iOS — history parity

- `AssessmentHistoryDetailView` gains the same aggregate section, frame images, and overlays,
  read from the new SwiftData fields. Sessions saved before this phase have no `PhaseFrameRecord`s
  and `nil` deviation fields, and must degrade gracefully to today's text-only rendering rather
  than crashing or showing empty image wells.

## Out of Scope

- **Any change to detection or rule-evaluation behavior.** `detect_phases`, `evaluate_rules`'s
  pass/fail logic, `segment_serves`, and `rules.json` thresholds are untouched. If the visualized
  deviations reveal a mis-calibrated threshold, that is a finding to record, not a fix to make
  here — thresholds are P5's domain.
- **The pre-recording live-feed skeleton overlay and joint-confidence warning.** That remains
  P13; this phase's renderer draws on still frames from a completed analysis only.
- **`start` and `finish` frame extraction/display.** Detected and returned in `phases`, but no
  rules target them and the user explicitly scoped display to release/trophy/drop/contact.
- **Video scrubbing, frame correction, or phase re-selection on the Pro results screen.** Pro 2D's
  premise is automatic segmentation; manual correction is permanently Lite's flow.
- **Any change to `PhaseReviewView`, the Lite pipeline/segmentation services, `LibraryVideoExporter`,
  `ContentView`, or Lite's `PhaseRecord`/comparison views.** Isolation rule, unconditional.
- **P7 Set Goal mode**, `goal_result`, and speech synthesis.
- **A SwiftData migration plan for pre-P6c sessions.** New fields are optional/defaulted so
  existing stores open unchanged; old sessions simply render text-only.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Results layout | Aggregate section on top, existing per-serve sections retained below (now with images + overlays) | User confirmed — adds a prioritized top-level read ("this flaw recurs in 3 of 4 serves") without losing the per-serve detail that already works. |
| Frames retained | `release`, `trophy_pose`, `racket_drop`, `contact` for **every** serve; not `start`/`finish` | User explicitly overrode the roadmap's narrower "flagged-phase" wording — retaining all four coaching-relevant phases unconditionally means a clean serve still shows its motion, and no rule targets `start`/`finish` so their frames would be inert. |
| Cue deviation payload | Full rule spec: `metric`, `joints`, `measured_value`, `comparison`, `threshold`/`threshold_min`/`threshold_max` | User confirmed — carrying `metric` + `joints` lets the overlay derive what to draw from the cue itself, so adding or editing a rule in `rules.json` needs no matching iOS change. The alternative (a hardcoded `ruleId` → visual map on the client) would silently drift out of sync with the backend. |
| Phase timing transport | New `phases: [PhaseDetection]` on `AnalyzeResponse` (phase, frame_index, timestamp); keypoints **not** re-sent | iOS already holds all segment frames and detections from `/v1/segment/video`; the timestamp is a sufficient join key. Keeps `AnalyzeResponse` small and keeps one source of truth for keypoints. |
| Overlay content | Dimmed full skeleton + highlighted measured segment + ideal indicator | User confirmed — the dimmed skeleton gives anatomical context so the user can see *where in the body* the flaw is, while the highlight keeps the flagged segment unmistakable. |
| Overlay production | Live-drawn at display time over a persisted clean JPEG; keypoints persisted as JSON `Data` | User confirmed — a baked-in overlay freezes styling at save time and can't be re-rendered when rule set or visual design changes. Live drawing costs one extra persisted JSON blob per phase frame. |
| Ideal indicators | All metric types get a drawn indicator (ray/arc for angles, band for diffs, box + ball marker for ball offsets) | User confirmed — every cue's deviation should be *visible*, not merely readable as numeric text. Accepts a larger renderer surface in exchange for uniform treatment across all nine current rules. |
| History parity | `AssessmentHistoryDetailView` gets the full aggregate + overlay treatment; pre-P6c sessions degrade to text-only | User confirmed — the data is persisted anyway, so a saved session looking markedly poorer than a fresh one would be a gratuitous inconsistency. |
| Real-device visual check | **Hard merge gate**, not best-effort — the phase does not merge without a real-device run against the Mac-hosted backend | User explicitly upgraded this above P6b's best-effort precedent. The y-flip / aspect-fit bug class can be asserted numerically in unit tests but not *proven* to render correctly on real footage; a mirrored or offset skeleton would ship looking plausible in tests and wrong in the app. |
| Frame-extraction latency | Concrete budget: extraction adds **≤ 2 s** to a 5-serve clip (~20 frames, ≈100 ms/frame); exceeding it blocks the merge pending optimization | User chose a hard budget over a record-only note. Retaining four frames per serve is net-new `AVAssetImageGenerator` work on the Pro analysis path; without a bar, a slow extraction loop would silently degrade the flow P6 just made usable. Remedies if exceeded: batch via `AVAssetImageGenerator.images(for:)`, or move extraction off the critical path so cues render first. |
| View-layer test coverage | View models, pure geometry, and formatters only — no SwiftUI view-body assertions | User confirmed. ViewInspector is named in `specs/tech-stack.md` but is not wired into the test target today; adding it is its own piece of work and would expand this phase's scope without covering the actual risk (which is geometry math, already directly testable). |
| Keypoint coordinate convention | Overlay maps normalized Vision-convention coords (origin bottom-left, y up) into SwiftUI `Canvas` space (origin top-left, y down) with an explicit y-flip, then into the aspect-fit image rect | Backend `pose_model.py:85` and `object_detection.py:37-47` both normalize to 0–1 **and** y-flip to match Vision's convention. Drawing them directly in `Canvas` without flipping back would render every skeleton upside down — this is the single likeliest source of a silent visual bug in this phase. |

## Context

- **P6c is the roadmap's scheduled follow-up to P6**, which shipped the Pro 2D Assessment flow
  end-to-end but with a deliberately plain results screen: `AssessmentResultView.swift` renders a
  header plus one bulleted `Text(cue.message)` row per cue per serve, with no imagery at all.
- **The backend already computes everything this phase needs and throws it away.**
  `evaluate_rules` (`rules.py:123-132`) computes `value` via `compute_metric_value`, tests it with
  `_passes`, and constructs a `Cue` from four fields — discarding the measured value and every
  threshold. `analyze.py:13-24` builds the full `phase_frames` dict from `detect_phases` and reads
  exactly one boolean off it. This phase is overwhelmingly plumbing, not new analysis.
- **iOS already receives the keypoints it needs.** `ProServeAnalysisPipeline.analyze`
  (`ProServeAnalysisPipeline.swift:35-50`) gets `[ProServeSegment]` — each with `frames` and
  `detections` — from `/v1/segment/video`, then passes them to `coachingService.analyze` and keeps
  only the `CoachingResult`. Retaining the segment's frames alongside the result is a local change
  to that loop.
- **`FrameThumbnailGenerator`** (`App/Services/Video/FrameThumbnailGenerator.swift`) is Lite's
  existing `AVAssetImageGenerator` wrapper with ±0.1s tolerance, already used by the Lite phase
  review path. The analyzed video URL is available as `VideoSourceSelectionViewModel.pendingVideoURL`
  and is already threaded into `AssessmentResultViewModel(results:inputType:videoURL:)` — currently
  stored and used only for persistence, never read for imagery.
- **Lite's persistence precedent:** `PhaseRecord` stores `frameImageData: Data` + `frameTimestamp`
  per confirmed phase. `PhaseFrameRecord` mirrors that shape for Pro, adding the keypoint/detection
  JSON the overlay needs. All new SwiftData properties get defaults, matching the existing models'
  style (`CueRecord`, `ServeResult`) which already default every stored property.
- **`CueOrdering`** (`App/Models/CueOrdering.swift`) already provides the shared
  major-before-minor/Kovacs-phase comparator over both `Cue` and `CueRecord`; the aggregate
  grouping's ordering should build on it rather than reimplement phase ordering.
- **Three-mode isolation rule** (`specs/mission.md`, `specs/tech-stack.md`): every iOS file this
  phase touches is on the Pro 2D route introduced in P6. Lite's route is byte-for-byte unchanged.
