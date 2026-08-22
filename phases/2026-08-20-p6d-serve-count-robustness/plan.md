# Phase P6d — Plan

> **Lite-isolation note:** no group touches Lite code. `segment_serves` is Pro-2D-only; its public
> signature and `SegmentResponse` wire shape are unchanged throughout.

> **Held-out discipline (applies to Group 6):** each of the corpus's seven held-out clips'
> expected count must pass, but its result must never be used to justify a constant change. If any
> fails after Groups 1–5 are otherwise calibrated and green, record the failure in `validation.md`
> run notes as a disclosed finding — do not adjust `HITTING_WRIST_FLOOR_K` or
> `MIN_PEAK_SEPARATION_SECONDS` in response to it specifically.
>
> **Shadow-swing exception (applies to Group 6):** the one row with `blocking: false` in
> `segmentation_count_ground_truth.json` (the shadow-swing clip) does not gate the merge even if it
> fails — see requirements.md Key Decisions for why this one clip, and no other negative-type clip,
> gets this treatment.

## Group 1 — Corpus Placement & Count Ground Truth (surface: `backend`, data)

1. `backend/tools/calibration_data/serve_segmentation_corpus/` already exists — the user has placed
   the full corpus (15 files; verified against real file metadata, every `fps`/`res` token
   matches). No file placement work remains in this group.
2. The four legacy candidate clips have already been renamed into the convention
   (`{view}_{hand}_{type}_{count}_{fps}_{res}_{name}[_{variant}].MOV`) and moved into
   `serve_segmentation_corpus/` — the user placed them there as **held-out** entries (`variant`
   ending in `holdout`) rather than as the plain `a`/`b`/`c`/`legacy` variants originally sketched
   for this step:
   ```
   test_2_serve_clip_c.MOV  -> open_right_flat_2serve_30fps_720x1280_galdi_holdout.MOV
   test_2_serve_clip_a.MOV  -> open_right_flat_2serve_60fps_2160x3840_galdi_holdout.MOV
   test_2_serve_clip_b.MOV  -> open_right_flat_2serve_60fps_1080x1920_galdi_holdout.MOV
   new_3_serve_clip.MOV     -> open_right_flat_3serve_60fps_1080x1920_galdi_holdout_b.MOV
   ```
   (`new_3_serve_clip.MOV` collides with the already-present
   `open_right_flat_3serve_60fps_1080x1920_galdi_holdout.MOV`, hence the `_b` second-level
   disambiguator on top of `holdout`.) No further file-placement work remains in this group.
   `calibration_data/ag_three_serves.MOV` remains untouched — the naming convention applies only to
   `serve_segmentation_corpus/`, not repo-wide (see requirements.md Key Decisions).
3. Create `backend/tools/segmentation_count_ground_truth.json`:
   ```json
   {
     "videos": {
       "serve_segmentation_corpus/open_right_flat_2serve_30fps_720x1280_galdi.MOV": {"expected_count": 2, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_2serve_30fps_720x1280_galdi_holdout.MOV": {"expected_count": 2, "held_out": true},
       "serve_segmentation_corpus/open_right_flat_2serve_30fps_1080x1920_galdi.MOV": {"expected_count": 2, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_2serve_60fps_1080x1920_galdi.MOV": {"expected_count": 2, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_2serve_60fps_2160x3840_galdi_holdout.MOV": {"expected_count": 2, "held_out": true},
       "serve_segmentation_corpus/open_right_flat_2serve_60fps_1080x1920_galdi_holdout.MOV": {"expected_count": 2, "held_out": true},
       "ag_three_serves.MOV": {"expected_count": 3, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_3serve_30fps_720x1280_galdi.MOV": {"expected_count": 3, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_3serve_30fps_1080x1920_galdi.MOV": {"expected_count": 3, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_3serve_60fps_1080x1920_galdi.MOV": {"expected_count": 3, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_3serve_60fps_1080x1920_galdi_holdout.MOV": {"expected_count": 3, "held_out": true},
       "serve_segmentation_corpus/open_right_flat_3serve_60fps_1080x1920_galdi_holdout_b.MOV": {"expected_count": 3, "held_out": true},
       "serve_segmentation_corpus/open_right_flat_4serve_30fps_1080x1920_galdi_holdout.MOV": {"expected_count": 4, "held_out": true},
       "serve_segmentation_corpus/open_right_flat_4serve_60fps_1080x1920_galdi.MOV": {"expected_count": 4, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_5serve_30fps_720x1280_galdi.MOV": {"expected_count": 5, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_5serve_60fps_1080x1920_galdi_holdout.MOV": {"expected_count": 5, "held_out": true},
       "serve_segmentation_corpus/open_right_idle_0serve_30fps_720x1280_galdi.MOV": {"expected_count": 0, "held_out": false},
       "serve_segmentation_corpus/open_right_tosscatch_3serve_30fps_720x1280_galdi.MOV": {"expected_count": 3, "held_out": false},
       "serve_segmentation_corpus/open_right_ballbounce_3serve_30fps_720x1280_galdi.MOV": {"expected_count": 3, "held_out": false},
       "serve_segmentation_corpus/open_right_shadowswing_2serve_30fps_720x1280_galdi.MOV": {
         "expected_count": 2,
         "held_out": false,
         "blocking": false,
         "_note": "Contains 2 real serves plus an unspecified number of ball-less shadow-swing reps. A shadow swing is pose-indistinguishable from a real serve (no ball signal to gate on), so segment_serves is expected to plausibly over-count. Documented, non-blocking limitation — see requirements.md Key Decisions. Every other negative-type clip (tosscatch, ballbounce) IS a hard blocking gate: their distractor motions are exactly what the body-relative floor is designed to filter."
       }
     }
   }
   ```
4. If the user has placed any corpus file not listed above, or a listed file turns out to be
   missing, stop and reconcile with the user before continuing — do not silently add or drop a
   ground-truth row.
5. No `scripts/verify.sh` run — this group is data/config only, verified structurally by Group 2's
   tests reading the file.

## Group 2 — `segmentation_report.py --score` Mode (surface: `backend`)

6. In `backend/tools/segmentation_report.py`, add a `score_videos` function:
   ```python
   def score_videos(
       video_paths: list[Path],
       ground_truth: dict,
       pose_model,
       detection_model,
   ) -> list[dict]:
       """Run segment_serves over every video in ground_truth['videos'] and compare the detected
       segment count to expected_count. Returns one result dict per ground-truth entry:
       {video_name, expected_count, actual_count, held_out, blocking, status} where status is
       "PASS" / "FAIL" / "MISSING" (file not found on disk). `blocking` defaults to True when a
       ground-truth entry omits the field."""
   ```
   Resolve each ground-truth key against `_TOOLS_DIR / "calibration_data" / video_name` (mirrors
   `test_segmentation_ground_truth.py`'s existing resolution). Reuse `build_frame_sequence` for
   inference and `segment_serves` for counting — no new inference path.
7. Add a `print_score_table(results: list[dict]) -> None` helper: one row per result, `[HELD OUT]`
   prefix on `held_out: true` rows, `[KNOWN LIMITATION]` prefix on `blocking: false` rows (both can
   apply to the same row, though today only the shadow-swing row has either), `MISSING` rows called
   out distinctly from `FAIL`. Print a summary line
   (`N/M blocking passed, K missing, showing held-out/non-blocking separately`).
8. Extend `_build_arg_parser()` with `--score` (`action="store_true"`) and `--ground-truth`
   (default `_TOOLS_DIR / "segmentation_count_ground_truth.json"`). In `main()`, when `--score` is
   set: load the ground truth JSON, call `score_videos` over its keys (ignoring `--videos`'s glob —
   the ground truth file is authoritative for which videos to score), print the table, and exit
   nonzero if any row with `blocking: true` (the default) and `held_out: false` is `FAIL`. Held-out
   failures print but don't affect exit code (Group 6 applies the real held-out merge-gate
   discipline manually — a held-out failure is still a hard gate for merging, just not something
   the sweep/score tooling auto-blocks on, since a developer running `--score` mid-calibration
   shouldn't be blocked by a clip they're not allowed to tune against anyway). `blocking: false`
   rows never affect exit code regardless of `held_out`.
9. Extend `backend/tests/test_segmentation_report.py` (synthetic-fixture style, no real models —
   mirrors the file's existing stub-model pattern):
   - `score_videos` with a stub `segment_serves`-equivalent returning a fixed count: PASS when
     counts match, FAIL when they don't.
   - A ground-truth entry whose video file doesn't exist on disk yields `status == "MISSING"`, not
     an exception.
   - A ground-truth entry omitting `blocking` defaults to `blocking: true`.
   - `print_score_table` output contains `[HELD OUT]` for a `held_out: true` row and
     `[KNOWN LIMITATION]` for a `blocking: false` row.
10. Run `scripts/verify.sh backend` — confirm green.

## Group 3 — Keypoint-Caching Sweep Tool (surface: `backend`)

11. Create `backend/tools/segmentation_sweep.py`:
    ```python
    """Caches pose/detection inference per corpus video so parameter sweeps over the peak-counting
    constants (HITTING_WRIST_FLOOR_K, MIN_PEAK_SEPARATION_SECONDS) run in seconds instead of
    minutes of CPU per guess."""
    ```
    - `class CachedVideoFrames(BaseModel): frames: list[Frame]; detections: list[list[Detection]]`
      in the tool module (or `app/models.py` if a shared location fits better — decide by whether
      anything outside `tools/` needs it; default to keeping it tool-local since nothing else does).
    - `def cache_path_for(video_path: Path, cache_dir: Path) -> Path` — one JSON file per video,
      named from the video's stem plus a content hash or mtime so a re-recorded clip invalidates
      its stale cache automatically rather than silently reusing old inference.
    - `def load_or_build_cache(video_path: Path, cache_dir: Path, stride: int, pose_model, detection_model) -> CachedVideoFrames` — loads the cache if present and valid, otherwise calls
      `build_frame_sequence` (imported from `segmentation_report.py`) and writes the cache.
    - `def sweep(video_paths: list[Path], ground_truth: dict, floor_k_values: list[float], min_separation_values: list[float], cache_dir: Path, pose_model, detection_model) -> list[dict]` —
      for every `(k, min_separation)` combination, monkeypatch/parameterize `segment_serves`'s
      constants (see Group 4's `segment_serves(..., floor_k=..., min_peak_separation_seconds=...)`
      parameters — the sweep must be able to pass these without editing module globals), count
      matches against non-held-out ground-truth entries only, and return
      `[{floor_k, min_peak_separation_seconds, matches, total}]` sorted best-first.
    - CLI: `--videos` (glob, default the ground-truth file's videos), `--ground-truth`,
      `--cache-dir` (default `calibration_data/.keypoint_cache/`), `--floor-k` (comma-separated
      list), `--min-separation` (comma-separated list). Prints the ranked sweep table.
12. Add `.gitignore` coverage if `.keypoint_cache/` isn't already implied by the existing
    `tools/calibration_data/` ignore entry — confirm by inspection; add an explicit
    `tools/calibration_data/.keypoint_cache/` line only if the existing entry doesn't already cover
    it (it should, since it's a subdirectory).
13. Add `backend/tests/test_segmentation_sweep.py` (synthetic fixtures, no real models, mirrors
    `test_segmentation_report.py`):
    - `load_or_build_cache` writes a cache file on first call and reuses it (no second call to the
      stub inference functions) on a second call with the same video.
    - A changed video (different mtime/hash) invalidates the cache and re-infers.
    - `sweep` over a tiny synthetic ground truth returns results sorted by descending match count.
    - Held-out entries are excluded from `matches`/`total` scoring.
14. Run `scripts/verify.sh backend` — confirm green.

## Group 4 — Algorithm: Peak-Detection Serve Counting (surface: `backend`)

15. In `backend/app/engine/phases.py`, add constants near the existing `LOW_MOTION_VELOCITY_THRESHOLD`
    block:
    ```python
    # Initial defaults — calibrated against the real corpus in this phase's Group 6; see
    # validation.md run notes for the values actually shipped and how they were chosen.
    HITTING_WRIST_FLOOR_K = 0.15
    MIN_PEAK_SEPARATION_SECONDS = 0.6
    ```
16. Add `_torso_length(frame: Frame) -> float | None`, `_hitting_wrist_floor_score(frame: Frame, hitting: str, floor_k: float) -> float | None`, and
    `_find_serve_peaks(frames: list[Frame], hitting: str, floor_k: float, min_peak_separation_seconds: float) -> list[int]`
    exactly as designed in requirements.md (body-relative floor via `neck`/`pelvis`, local-maxima
    detection over the positive-score series, greedy NMS by descending score with a real-seconds
    separation check). Reuse `keypoint_y` from `app.engine.angles` (already imported in this file).
17. Add `_place_boundary(frames: list[Frame], peak_a: int, peak_b: int, velocity_threshold: float, min_rest_seconds: float) -> int` —
    searches only `frames[peak_a+1:peak_b]` for the existing low-velocity rest-run logic (reuse
    `_frame_velocity`) and returns the midpoint index of the best rest run found; if none clears
    `min_rest_seconds` in that span, returns the frame index nearest the time-midpoint between
    `frames[peak_a].timestamp` and `frames[peak_b].timestamp`.
18. Rewrite `segment_serves`'s body to:
    - Return `[]` immediately for empty input (unchanged).
    - Compute `hitting = HANDEDNESS["hitting"]` and call `_find_serve_peaks` with the (now
      parameterized) constants.
    - Zero peaks → `[]`. One peak → `[frames]`. Two or more peaks → call `_place_boundary` between
      each consecutive pair, then slice `frames` at those boundaries exactly as today's tail-end
      slicing loop already does (this part of the function is unchanged).
    - Extend the function's parameter list with `floor_k: float = HITTING_WRIST_FLOOR_K` and
      `min_peak_separation_seconds: float = MIN_PEAK_SEPARATION_SECONDS`, keeping
      `min_rest_seconds`/`velocity_threshold`/`min_active_run_seconds` as before (still used by
      `_place_boundary`) — `min_active_run_seconds` may become unused if boundary placement no
      longer needs the active-run check now that peaks (not rest gaps) gate counting; if so, drop
      it from `_place_boundary`'s call and from the signature, and delete
      `MIN_ACTIVE_RUN_SECONDS` only if nothing else references it (grep before removing).
19. Update both call sites in `backend/app/routers/segment.py` — no signature change needed since
    all new parameters default; confirm by reading, don't blind-edit.
20. Run `scripts/verify.sh backend` — expect failures in `test_segment_serves.py` at this point
    (Group 5 rewrites it); confirm no *other* test file regresses.

## Group 5 — Test Rewrite (surface: `backend`)

21. Rewrite `backend/tests/test_segment_serves.py` fixtures around vertical
    wrist-crosses-body-relative-floor motion. Replace `_positioned_frame`/`_active_burst`/`_rest_burst`
    (which drove `right_wrist.x`) with helpers that set `neck`, `pelvis`, and `right_wrist` keypoints
    such that:
    - An "active" frame has `right_wrist.y` above the floor (`neck.y + k * |neck.y - pelvis.y|`) by
      a clear margin.
    - A "rest" frame has `right_wrist.y` below the floor.
    - `neck`/`pelvis` stay fixed across a burst so torso length is constant per test, isolating the
      wrist-height signal being tested.
    Preserve each existing case's intent under the new fixtures:
    `test_empty_frames_returns_empty_list`, `test_single_serve_no_rest_gap_returns_one_segment`,
    `test_all_idle_frames_returns_empty_list` (now: wrist never clears the floor → zero peaks →
    `[]`), `test_two_serves_separated_by_rest_gap_returns_two_segments`,
    `test_leading_idle_not_split_off`, `test_trailing_idle_not_split_off`,
    `test_velocity_ignores_low_confidence_keypoints` (unchanged — still exercises `_frame_velocity`
    directly), `test_segmentation_is_fps_invariant` (peak separation must be expressed in real
    seconds, not frame count — this test is the direct regression guard for that), and the two
    mid-routine-pause false-split regressions (reframed: a brief within-serve dip below the floor
    between two nearby peaks must not register as two accepted peaks if within
    `MIN_PEAK_SEPARATION_SECONDS`, and a real between-serve gap must still separate two peaks).
    `test_short_rest_gap_does_not_split` becomes a peak-separation test: two wrist-height peaks
    closer together than `MIN_PEAK_SEPARATION_SECONDS` collapse to one accepted peak.
22. Add new unit tests directly on `_find_serve_peaks` (imported alongside `segment_serves`):
    - `test_toss_and_catch_shape_yields_zero_peaks` — `left_wrist` (toss) rises above its own
      floor-equivalent height, `right_wrist` (hitting) never does; asserts `[]`.
    - `test_two_close_peaks_collapse_to_one` — two candidate local maxima within
      `MIN_PEAK_SEPARATION_SECONDS`; asserts exactly one accepted peak (the higher-scoring one).
    - `test_missing_neck_or_pelvis_excludes_frame_without_crashing` — a frame with a
      high-confidence `right_wrist` but no `neck`/`pelvis` keypoint contributes no candidate.
23. Run `scripts/verify.sh backend` — confirm green, including every other pre-existing backend
    test file unmodified by this phase (`test_phases.py`, `test_segment_endpoint.py`,
    `test_segment_video_endpoint.py`).

## Group 6 — Real-Corpus Calibration (surface: `backend`, manual/tooling-driven) — **hard merge gate**

> **Stop before this group and confirm with the user that the corpus in
> `serve_segmentation_corpus/` still matches Group 1's ground-truth JSON** (no files added/removed
> since this plan was written). This group needs real models and real footage; it is not part of
> the fast unit-test loop and should not be attempted against a corpus that's drifted from the
> ground truth.

24. Run `python backend/tools/segmentation_sweep.py` over the full corpus with a reasonable initial
    grid around the Group 4 defaults (e.g. `--floor-k 0.08,0.12,0.15,0.2,0.3` `--min-separation
    0.4,0.6,0.8,1.0`) to warm the keypoint cache and get a ranked candidate list. The sweep tool
    excludes `held_out: true` entries from scoring by design (Group 3); it does not need to also
    exclude `blocking: false` — the shadow-swing clip's likely over-count would just make it a
    low/non-contributing scorer, not a misleading one, across every candidate combination equally.
25. Pick the best-scoring `(floor_k, min_peak_separation_seconds)` combination over the
    **non-held-out** corpus and update `HITTING_WRIST_FLOOR_K`/`MIN_PEAK_SEPARATION_SECONDS` in
    `phases.py` to match.
26. Run `python backend/tools/segmentation_report.py --score` (full corpus, including all seven
    held-out clips) with the chosen constants. Every row with `blocking: true` (the default) —
    whether held-out or not — must be `PASS`; the shadow-swing row (`blocking: false`) is recorded
    but does not gate. Held-out rows are a hard gate too (see the plan-level Held-out discipline
    note above) — record each result either way, but do not iterate
    `floor_k`/`min_peak_separation_seconds` in response to a held-out-specific failure.
27. Run `RUN_MODEL_INTEGRATION_TESTS=1 pytest backend/tests/test_segmentation_ground_truth.py -v`
    — the existing six-phase-timestamp regression suite must stay green. Boundary placement moving
    (even with the same final serve count) can shift which frames land in which segment, which
    could shift `detect_phases`' within-segment results; this is the check that it didn't.
28. If any `blocking: true` row fails after a reasonable sweep grid, treat it as a genuine defect —
    widen the grid or revisit the floor/NMS design per requirements.md's locked approach, but do
    not special-case a single clip's constants. If a held-out or negative-case row's target itself
    turns out to be wrong (e.g. the recorded footage doesn't actually contain what its filename
    claims), fix the ground-truth entry, not the algorithm.
29. Record the final constants, the full `--score` table (including the shadow-swing clip's actual
    vs. expected count, even though it's non-blocking), and the sweep grid explored in
    `validation.md` run notes.

## Group 7 — Documentation & Cross-Cutting Verification (surface: `backend`)

30. In `backend/app/engine/phases.py`, extend the `HANDEDNESS` comment:
    ```python
    # Hardcoded right-handed server. A wrong hitting side previously produced only wrong cues;
    # since P6d, segment_serves' serve *count* also derives from the hitting wrist, so a wrong
    # side now miscounts serves too. P7b promotes this from known limitation to prerequisite —
    # it must become configurable before behind-camera work, which can't assume handedness from
    # framing alone.
    HANDEDNESS: dict[str, str] = {"hitting": "right", "toss": "left"}
    ```
31. Run `git diff --name-only develop...HEAD` and confirm no iOS file (`App/`) and no
    `rules.json`/`detect_phases`/`compute_metric_value`/`_passes` diff appears — this phase changes
    counting and boundary placement only.
32. Run `scripts/verify.sh backend` — confirm green as the final check.
33. Update `specs/roadmap.md`'s P6d entry status marker only as part of `/merge` (not this phase) —
    no action here, noted for the implementer so it isn't done early.
