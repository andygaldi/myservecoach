# Phase P6d — Serve Count Robustness — Requirements

## Scope

Replace `segment_serves`'s count-by-absence (sustained low-velocity "rest" gaps) with
count-by-presence (hitting-wrist height peaks). The defect, root cause, and chosen approach are
settled in `specs/roadmap.md`'s P6d entry — this phase implements that approach, it does not
re-derive it. Velocity-based rest detection is demoted from *deciding how many serves there are*
to *placing the boundary* between two already-counted serves. A new, hand-recorded footage corpus
(fps matrix, a held-out clip, and negative cases) is a blocking prerequisite for calibrating and
verifying the new heuristic, and this phase also builds the tooling (a `--score` mode and a
keypoint-caching sweep tool) needed to calibrate against it without re-running pose/detection
inference on every parameter guess.

## In Scope

### Corpus placement and naming convention

- New directory: **`backend/tools/calibration_data/serve_segmentation_corpus/`** (gitignored,
  matching the existing `tools/calibration_data/` entry in `backend/.gitignore` — no video files
  are committed).
- **General-purpose naming convention** (not P6d-specific — designed to describe any future
  serve-footage clip, not just fps-matrix entries):
  ```
  {view}_{hand}_{type}_{count}_{fps}_{res}_{name}[_{variant}].MOV
  ```
  | Field | Vocabulary | Notes |
  |---|---|---|
  | `view` | `open` \| `closed` \| `behind` | Camera placement, matching the roadmap's own terms (open-side, closed-side/P15, behind-server/P7b). Every clip in this phase's corpus is `open` — Pro 2D and Lite are both open-side-only today. |
  | `hand` | `right` \| `left` | Server's hitting hand. |
  | `type` | `flat` \| `slice` \| `kick` \| `tosscatch` \| `ballbounce` \| `idle` \| `shadowswing` | Real serve types share the slot with negative-case motion categories — mutually exclusive descriptions of "what kind of motion this clip contains," so one field covers both without a schema fork. |
  | `count` | `{N}serve` | **Content count** — the number of real serves that actually occurred in the footage, independent of what any algorithm is expected to detect. Negative-case clips (including `shadowswing`, which contains a serve-*shaped* motion but no real serve) get `0serve`. The `N` suffix (`serve`) keeps this token unambiguous against `fps`/`res` digits under a loose grep. |
  | `fps` | `{N}fps` | Camera capture frame rate. |
  | `res` | `{width}x{height}` | Exact captured pixel dimensions (portrait orientation as recorded) — not a lossy shorthand like `1080p`/`4k`, which is ambiguous between portrait/landscape and doesn't pin exact dims. |
  | `name` | short identity token, e.g. `ag` | Server identity. No internal separators. |
  | `variant` | optional, e.g. `a`, `b`, `heldout` | Disambiguates otherwise-identical filenames (same view/hand/type/count/fps/res/name) and marks corpus role (`heldout`) as an instance of the same pattern rather than a special-cased prefix. |

  Every field value is itself separator-free (no embedded `_`) so the filename stays mechanically
  parseable by a plain `.split("_")`, not just greppable by eye — this is what makes the convention
  usable by future tooling, not only humans skimming a directory listing.
- Existing clips renamed into the convention (`git mv`, unreferenced elsewhere in code — verified
  by repo-wide grep):
  | Current path | New path |
  |---|---|
  | `calibration_data/test_2_serve_clip_c.MOV` (2 serves, 30fps, 720×1280) | `serve_segmentation_corpus/open_right_flat_2serve_30fps_720x1280_ag.MOV` |
  | `calibration_data/test_2_serve_clip_a.MOV` (2 serves, 60fps, 2160×3840) | `serve_segmentation_corpus/open_right_flat_2serve_60fps_2160x3840_ag_a.MOV` |
  | `calibration_data/test_2_serve_clip_b.MOV` (2 serves, 60fps, 1080×1920) | `serve_segmentation_corpus/open_right_flat_2serve_60fps_1080x1920_ag_b.MOV` |
  | `calibration_data/new_3_serve_clip.MOV` (3 serves, 60fps, 1080×1920) | `serve_segmentation_corpus/open_right_flat_3serve_60fps_1080x1920_ag.MOV` |
- `calibration_data/ag_three_serves.MOV` (3 serves, 30fps) is **not** moved or renamed — it is
  referenced by its historical name across `phases.py` comments, `segmentation_ground_truth.json`,
  and multiple prior phase triads. It fulfills the 3-serve/30fps matrix cell in place, outside the
  new convention (see Key Decisions — convention scope).
- New clips the user supplies, matching the convention (not yet present on disk — placed before
  the calibration task group runs; exact `fps`/`res` tokens fixed to whatever each clip actually
  is when placed):
  - `serve_segmentation_corpus/open_right_flat_5serve_30fps_<res>_ag.MOV`
  - `serve_segmentation_corpus/open_right_flat_5serve_60fps_<res>_ag.MOV`
  - `serve_segmentation_corpus/open_right_flat_<N>serve_<fps>fps_<res>_ag_heldout.MOV`
  - `serve_segmentation_corpus/open_right_tosscatch_0serve_<fps>fps_<res>_ag.MOV`
  - `serve_segmentation_corpus/open_right_ballbounce_0serve_<fps>fps_<res>_ag.MOV`
  - `serve_segmentation_corpus/open_right_idle_0serve_<fps>fps_<res>_ag.MOV`
  - `serve_segmentation_corpus/open_right_shadowswing_0serve_<fps>fps_<res>_ag.MOV` — `0serve` per
    the content-count convention above; the algorithm's expected detection of `1` for this clip
    lives only in `segmentation_count_ground_truth.json`'s `expected_count`, not in the filename.
- If a matrix cell's file is missing when the calibration/verification task group runs, **stop and
  ask the user to place it** — do not silently skip a cell or record it as an accepted gap.

### Count ground truth

- New file: **`backend/tools/segmentation_count_ground_truth.json`**, separate from the existing
  six-phase-timestamp `segmentation_ground_truth.json` (which stays untouched). Schema:
  ```json
  {
    "videos": {
      "<path relative to calibration_data/>": {
        "expected_count": 0,
        "held_out": false,
        "_note": "optional"
      }
    }
  }
  ```
- Every corpus entry (matrix cells, `ag_three_serves.MOV`, the held-out clip, all four negative
  cases) gets a row. The `open_right_shadowswing_0serve_..._ag.MOV` clip is recorded with
  `expected_count: 1` (note the mismatch against its own `0serve` filename token — the filename
  describes footage content, this field describes expected algorithm behavior) and a `_note`
  documenting why (see Key Decisions).

### Tooling — `segmentation_report.py --score` mode

- New `--score` flag: instead of (or in addition to) writing the HTML report, run
  `segment_serves` over every corpus video, compare `len(segments)` to
  `segmentation_count_ground_truth.json`'s `expected_count`, and print a pass/fail table. Rows for
  `held_out: true` videos are visually distinguished (e.g. a `[HELD OUT]` marker) so a developer
  scanning the output doesn't casually retune against them. A video listed in the ground truth but
  missing on disk is reported as `MISSING`, not a crash.

### Tooling — keypoint-caching sweep tool

- New script **`backend/tools/segmentation_sweep.py`**: infers pose/detection once per corpus
  video, caches the resulting `Frame`/`Detection` sequence to disk (gitignored, under
  `calibration_data/.keypoint_cache/`), and on subsequent runs loads the cache instead of
  re-running inference. Accepts a small grid of candidate values for the two new tunable constants
  (the floor multiplier and the peak-separation window) and reports, per combination, how many
  corpus videos count-match — turning a parameter question that costs minutes of CPU per guess
  (full pose + object-detection inference over every clip) into a near-instant one once the cache
  is warm.

### Algorithm — peak-detection serve counting

- `backend/app/engine/phases.py`: new hitting-wrist-height-peak counting, replacing rest-gap
  counting as the source of `segment_serves`'s serve count:
  - A body-relative floor per frame: `neck_y + k · |neck_y − pelvis_y|`, using the already-derived
    `neck`/`pelvis` midpoint keypoints (`pose_model.py`) and the existing `keypoint_y` helper.
  - A frame's hitting-wrist "score" is its height above that floor; only frames where the score is
    positive are peak candidates — this is the load-bearing hitting-side restriction that rejects
    a toss-and-catch (toss arm rises, hitting arm does not).
  - Local maxima of the score series, then greedy non-max suppression keyed on a minimum temporal
    separation between accepted peaks (real seconds, not frame count — fps-invariant by
    construction, same reasoning as `_frame_velocity`'s existing `dt`-normalization).
  - Accepted peak count **is** the serve count. Zero accepted peaks → `[]` (idle-only, and any
    clip where the hitting wrist never clears the floor).
- Velocity-based rest-gap detection is retained but demoted: given two consecutive accepted peaks,
  it searches only the span between them for a low-velocity window and places the boundary at that
  window's midpoint (today's existing math), falling back to the time-midpoint between the two
  peaks when no clear rest window resolves in that span. It can no longer add, remove, or merge a
  serve — only slide where the cut between two already-counted serves falls.
- The two new constants (floor multiplier, minimum peak separation) start at literature/first-pass
  defaults and are calibrated during this phase's own corpus-verification task group via the sweep
  tool — the plan does not pre-commit final values.

### Test rewrite

- `backend/tests/test_segment_serves.py`'s fixtures are rebuilt around vertical
  wrist-height-crosses-a-body-relative-floor motion (`neck`/`pelvis`/`{hitting}_wrist` keypoints)
  instead of the current horizontal wrist-drift-past-a-velocity-threshold fixtures, since the
  counting signal itself has changed. Existing test *intent* (single serve, two serves with a rest
  gap, all-idle rejected, leading/trailing idle not split off, a short mid-motion gap doesn't
  split, fps-invariance, the mid-routine-pause false-split regression) is preserved under the new
  fixture shape — this is a rewrite of how each case is constructed, not a drop of coverage.
- New unit tests directly on the peak/NMS primitives (independent of `segment_serves`'s frame-list
  return shape) covering: a toss-and-catch shape (toss wrist rises, hitting wrist doesn't → zero
  peaks), two peaks closer together than the minimum separation collapsing to one accepted peak,
  and missing neck/pelvis/wrist keypoints on a candidate frame excluding it without crashing.

### Documentation

- `HANDEDNESS` in `phases.py` gains a comment escalating its status from "known limitation" to
  "P7b prerequisite": once the count itself derives from the hitting wrist, a wrong hardcoded side
  produces a wrong *serve count*, not just wrong cues. No code change — `HANDEDNESS` stays
  hardcoded `{"hitting": "right", "toss": "left"}`; P7b is where it becomes configurable.

## Out of Scope

- **Any iOS change.** `SegmentResponse`'s wire shape (`segments: [ServeSegment]`) is unchanged —
  only which frames land in which segment and how many segments there are. iOS already treats the
  server-reported segment count as authoritative; no client code needs to know the counting method
  changed.
- **`detect_phases`'s six-phase heuristics.** Trophy pose, racket drop, contact, etc. are computed
  *within* an already-segmented serve and are untouched by this phase — a defect there is P4b/P6b's
  domain, not this one's.
- **`rules.json` / P5's calibrated thresholds.** No coaching-cue behavior changes.
- **Making `HANDEDNESS` configurable.** Documented as a P7b prerequisite; not implemented here (see
  Key Decisions).
- **A `stride` sweep.** The fps matrix varies actual camera-capture frame rate; `DEFAULT_STRIDE = 2`
  (the production `/segment/video` sampling rate) is unchanged and is what the corpus is evaluated
  at, matching `segmentation_report.py`'s existing default.
- **Rejecting the shadow-swing clip.** Recorded as `expected_count: 1`, a documented pose-only
  limitation, not a defect this phase fixes (see Key Decisions). No ball-detection signal is added
  to the counting path to attempt to distinguish it.
- **The Lite path.** `segment_serves` is Pro-2D-only; Lite's on-device Vision phase-guessing is
  untouched (isolation rule, unconditional).
- **Renaming legacy calibration clips.** `ag_three_serves.MOV`, `alcaraz_serve_1.mov`,
  `vesa_slow_mo.mov`, and `serve_1.MOV`–`serve_4.mov` keep their current names. Applying the new
  naming convention to them — and updating every comment/JSON key/doc reference that names them —
  is deferred to a later, deliberate pass, not folded into P6d (see Key Decisions).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Approach | Locked to the roadmap's hitting-wrist-peak + NMS design; velocity demoted to boundary placement only | User confirmed — the roadmap's root-cause analysis (noise-driven, non-monotonic-in-`dt` rest detection) and chosen fix are settled, not open for redesign in this spec. |
| `HANDEDNESS` | Comment-only escalation to "P7b prerequisite"; stays hardcoded | User confirmed — implementing configurable handedness with no caller ever passing anything but the default would be speculative scope; P7b is where a second value first matters. |
| Corpus directory | New `serve_segmentation_corpus/` subdirectory under `calibration_data/` | User chose this name over `p6d_corpus/` specifically so the directory's contents are self-describing without needing the roadmap phase code to interpret it. |
| Existing candidate clips | Renamed into the convention (`git mv`) rather than left under their old names | User confirmed — produces one uniform matrix the plan can enumerate by exact expected filename, rather than a mix of two naming schemes. |
| `ag_three_serves.MOV` | Left in place, not renamed | Referenced by name across code comments, the existing ground-truth JSON, and multiple prior phase triads; renaming it would be unrelated churn with real risk of breaking a stale reference. |
| Filename schema | `{view}_{hand}_{type}_{count}_{fps}_{res}_{name}[_{variant}].MOV`, general-purpose rather than P6d-specific | User designed this to describe any future serve clip (view angle, handedness, serve type included) so a filename carries enough information that the file rarely needs to be opened just to know what's in it; ordered fixed-vocabulary-first (view/hand/type) then numeric (count/fps/res) then identity (name) for grep-friendliness. |
| Field separators | Every field value is itself underscore-free (e.g. `tosscatch`, not `toss_catch`) | Keeps the filename mechanically parseable by a plain `.split("_")`, not just greppable by eye — required for the "future-proof" goal to mean anything to future tooling, not only humans. |
| Negative-case `type` values | Share the `type` slot with real serve types (`flat`/`slice`/`kick`) rather than a new field | `tosscatch`/`ballbounce`/`idle`/`shadowswing` are mutually exclusive with real serve types — "what kind of motion this clip contains" — so one field covers both without forking the schema for negative cases. |
| `count` field semantics | Content count — actual real serves in the footage, independent of algorithm behavior | User confirmed — the shadow-swing clip is the sharp case: it contains zero real serves (`0serve` in its filename) but the algorithm is expected to detect one (`expected_count: 1` in the ground-truth JSON only). Keeping the filename a neutral description of footage content, not a prediction of tool output, avoids the filename and the algorithm's behavior silently drifting apart as constants get retuned. |
| Convention scope | Applies to the new `serve_segmentation_corpus/` only, for now | User confirmed — repo-wide adoption would mean renaming `ag_three_serves.MOV`, `alcaraz_serve_1.mov`, `vesa_slow_mo.mov`, and `serve_1-4.mov` and updating every place that names them (code comments, the existing ground-truth JSON, prior phase triads); real churn and real breakage risk, better done as its own deliberate pass than folded into this phase's scope. |
| `heldout` marker | Lives in the `variant` slot, not a separate prefix | Makes the held-out clip's filename an instance of the same schema rather than a special case living outside it. |
| Count ground truth format | New, separate `segmentation_count_ground_truth.json` | User confirmed — keeps the existing six-phase-timestamp ground truth (with its tiered tolerances) conceptually and structurally separate from this simpler count-only concern, per the roadmap's own observation that "serve counts ... need no timestamps." |
| Held-out clip discipline | Hard merge gate — it must pass — but a failure is a disclosed finding, not something chased with constant retuning | User confirmed — exempting it from the pass bar would make it decorative; but re-tuning `k`/the separation window in direct response to its specific failure is curve-fitting by another name and defeats its purpose. A real fix would require reconsidering the approach, which is out of scope for reactive tuning mid-phase. |
| `negative_shadow_swing.MOV` expected count | `1`, documented as a known pose-only limitation | User confirmed — a ball-less shadow swing is genuinely indistinguishable from a real serve using only 2D pose (no ball detection reliably survives to gate on, per the roadmap's own 10.8%-presence finding). Scoping in a ball-based rejection signal here would expand this phase well beyond "fix the counting heuristic." |
| Sweep tool caching | Gitignored on-disk cache under `calibration_data/.keypoint_cache/`, keyed per video | Corpus videos require running the real pose + object-detection models once each; without caching, every parameter guess during calibration re-pays that cost across the whole corpus. |

## Context

- **P6d is the roadmap's scheduled fix for a defect P6 could only work around.** P6 constrained
  input (720×1280@30fps capture lock, import re-encode) rather than fixing the root cause; P6d
  fixes the root cause directly so the constraint stops being load-bearing for correctness.
- **The root cause is fully diagnosed in `specs/roadmap.md`'s P6d entry**, including the
  stride-subsampling table showing serve counts are non-monotonic in `dt` and the ground-truth-blind-spot
  explanation for why this survived P4/P4b/P6/P6b (the only multi-serve calibration clip,
  `ag_three_serves.MOV`, is 30fps, and the synthetic fps-invariance test fixture emits zero-noise
  velocity by construction).
- **`neck` and `pelvis` already exist** as derived midpoint keypoints
  (`backend/app/services/pose_model.py:88-90`, `_midpoint_keypoint` over
  `left_shoulder`/`right_shoulder` and `left_hip`/`right_hip`), and `angles.py`'s `hip_height`
  already prefers `pelvis` for exactly the stability reason this phase's floor computation needs.
  No new keypoint derivation is required — this phase composes existing primitives into a new
  signal.
- **`_frame_velocity`'s `dt`-normalization pattern is the model for the new peak-separation
  window**: both must be expressed in real seconds (not frame count) to stay fps-invariant, which
  is the entire point of this phase.
- **Ball detection is not a viable primary counting signal.** Per the roadmap: present in only
  10.8% of frames and specifically absent at the contact instant (motion blur, the fastest moment
  of the swing) — the opposite of where a contact-counting signal would need to be reliable. Pose
  is 100%-person-detected with 0.775 mean keypoint confidence on the same corpus, which is why the
  new counting signal is pose-only.
- **`slice_detections_by_segments` and both `/segment` router functions
  (`backend/app/routers/segment.py`) call `segment_serves` and consume its `list[list[Frame]]`
  return shape** — that shape and the function's public signature are unchanged; only the internal
  counting/boundary logic changes, so no caller needs to change.
- **`backend/.gitignore` already excludes all of `tools/calibration_data/`** — the new corpus
  directory, its videos, and the keypoint cache need no new gitignore entry; only the two new
  scripts and the new ground-truth JSON are code this phase commits.
