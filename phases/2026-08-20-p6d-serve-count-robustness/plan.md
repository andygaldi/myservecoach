# Phase P6d — Plan

> **Lite-isolation note:** no group touches Lite code. `segment_serves` is Pro-2D-only; its public
> signature and `SegmentResponse` wire shape are unchanged throughout.

> **Held-out discipline (applies to Group 6):** the held-out clip's expected count must pass, but
> its result must never be used to justify a constant change. If it fails after Groups 1–5 are
> otherwise calibrated and green, record the failure in `validation.md` run notes as a disclosed
> finding — do not adjust `HITTING_WRIST_FLOOR_K` or `MIN_PEAK_SEPARATION_SECONDS` in response to
> it specifically.

## Group 1 — Corpus Placement & Count Ground Truth (surface: `backend`, data)

1. Create `backend/tools/calibration_data/serve_segmentation_corpus/`.
2. `git mv` the four existing candidate clips into the convention
   (`{view}_{hand}_{type}_{count}_{fps}_{res}_{name}[_{variant}].MOV`):
   ```
   git mv backend/tools/calibration_data/test_2_serve_clip_c.MOV backend/tools/calibration_data/serve_segmentation_corpus/open_right_flat_2serve_30fps_720x1280_ag.MOV
   git mv backend/tools/calibration_data/test_2_serve_clip_a.MOV backend/tools/calibration_data/serve_segmentation_corpus/open_right_flat_2serve_60fps_2160x3840_ag_a.MOV
   git mv backend/tools/calibration_data/test_2_serve_clip_b.MOV backend/tools/calibration_data/serve_segmentation_corpus/open_right_flat_2serve_60fps_1080x1920_ag_b.MOV
   git mv backend/tools/calibration_data/new_3_serve_clip.MOV backend/tools/calibration_data/serve_segmentation_corpus/open_right_flat_3serve_60fps_1080x1920_ag.MOV
   ```
   (These paths are gitignored — `git mv` will report the rename but the files themselves are not
   tracked; this step is a plain filesystem rename that stays consistent with git's view either
   way.) Leave `calibration_data/ag_three_serves.MOV` untouched — the naming convention applies
   only to `serve_segmentation_corpus/`, not repo-wide (see requirements.md Key Decisions).
3. Confirm with the user that the remaining corpus files are placed, named per the convention with
   `fps`/`res` matching each clip's actual capture (content `count` — see requirements.md's
   `count` field semantics):
   - `serve_segmentation_corpus/open_right_flat_5serve_30fps_<res>_ag.MOV`
   - `serve_segmentation_corpus/open_right_flat_5serve_60fps_<res>_ag.MOV`
   - `serve_segmentation_corpus/open_right_flat_<N>serve_<fps>fps_<res>_ag_heldout.MOV`
   - `serve_segmentation_corpus/open_right_tosscatch_0serve_<fps>fps_<res>_ag.MOV`
   - `serve_segmentation_corpus/open_right_ballbounce_0serve_<fps>fps_<res>_ag.MOV`
   - `serve_segmentation_corpus/open_right_idle_0serve_<fps>fps_<res>_ag.MOV`
   - `serve_segmentation_corpus/open_right_shadowswing_0serve_<fps>fps_<res>_ag.MOV`
   If any is missing, note it and continue with Groups 2–5 (which don't need the files present) —
   Group 6 is where a missing file blocks.
4. Create `backend/tools/segmentation_count_ground_truth.json`, keyed by each clip's actual final
   filename (fill in the real `<fps>`/`<res>` tokens from step 3 once placed):
   ```json
   {
     "videos": {
       "serve_segmentation_corpus/open_right_flat_2serve_30fps_720x1280_ag.MOV": {"expected_count": 2, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_2serve_60fps_2160x3840_ag_a.MOV": {"expected_count": 2, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_2serve_60fps_1080x1920_ag_b.MOV": {"expected_count": 2, "held_out": false},
       "ag_three_serves.MOV": {"expected_count": 3, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_3serve_60fps_1080x1920_ag.MOV": {"expected_count": 3, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_5serve_30fps_<res>_ag.MOV": {"expected_count": 5, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_5serve_60fps_<res>_ag.MOV": {"expected_count": 5, "held_out": false},
       "serve_segmentation_corpus/open_right_flat_<N>serve_<fps>fps_<res>_ag_heldout.MOV": {"expected_count": null, "held_out": true, "_note": "fill in <N>/<fps>/<res> and expected_count once placed"},
       "serve_segmentation_corpus/open_right_tosscatch_0serve_<fps>fps_<res>_ag.MOV": {"expected_count": 0, "held_out": false},
       "serve_segmentation_corpus/open_right_ballbounce_0serve_<fps>fps_<res>_ag.MOV": {"expected_count": 0, "held_out": false},
       "serve_segmentation_corpus/open_right_idle_0serve_<fps>fps_<res>_ag.MOV": {"expected_count": 0, "held_out": false},
       "serve_segmentation_corpus/open_right_shadowswing_0serve_<fps>fps_<res>_ag.MOV": {
         "expected_count": 1,
         "held_out": false,
         "_note": "Documented pose-only limitation, not a defect: a ball-less shadow swing is indistinguishable from a real serve using hitting-wrist-height alone. Filename's 0serve is content count (no real serve occurred); expected_count is what the algorithm is expected to detect. See requirements.md Key Decisions."
       }
     }
   }
   ```
   Replace every `<fps>`/`<res>`/`<N>` placeholder with the clip's real values once placed
   (step 3).
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
       {video_name, expected_count, actual_count, held_out, status} where status is
       "PASS" / "FAIL" / "MISSING" (file not found on disk)."""
   ```
   Resolve each ground-truth key against `_TOOLS_DIR / "calibration_data" / video_name` (mirrors
   `test_segmentation_ground_truth.py`'s existing resolution). Reuse `build_frame_sequence` for
   inference and `segment_serves` for counting — no new inference path.
7. Add a `print_score_table(results: list[dict]) -> None` helper: one row per result, `[HELD OUT]`
   prefix on `held_out: true` rows, `MISSING` rows called out distinctly from `FAIL`. Print a
   summary line (`N/M passed, K missing, showing held-out separately`).
8. Extend `_build_arg_parser()` with `--score` (`action="store_true"`) and `--ground-truth`
   (default `_TOOLS_DIR / "segmentation_count_ground_truth.json"`). In `main()`, when `--score` is
   set: load the ground truth JSON, call `score_videos` over its keys (ignoring `--videos`'s glob —
   the ground truth file is authoritative for which videos to score), print the table, and exit
   nonzero if any non-held-out, non-missing row is `FAIL` (held-out failures print but don't affect
   exit code, matching the disclose-don't-block-here stance — Group 6 applies the real merge gate
   manually, this is just the tool's own exit semantics for CI-style use).
9. Extend `backend/tests/test_segmentation_report.py` (synthetic-fixture style, no real models —
   mirrors the file's existing stub-model pattern):
   - `score_videos` with a stub `segment_serves`-equivalent returning a fixed count: PASS when
     counts match, FAIL when they don't.
   - A ground-truth entry whose video file doesn't exist on disk yields `status == "MISSING"`, not
     an exception.
   - `print_score_table` output contains `[HELD OUT]` for a `held_out: true` row.
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

> **Stop before this group and confirm with the user that every corpus file listed in Group 1
> step 3 is present** (`5serve_30fps.MOV`, `5serve_60fps.MOV`, the held-out clip, all four
> `negative_*.MOV` clips). This group needs real models and real footage; it is not part of the
> fast unit-test loop and should not be attempted against a partial corpus.

24. Run `python backend/tools/segmentation_sweep.py` over the full corpus with a reasonable initial
    grid around the Group 4 defaults (e.g. `--floor-k 0.08,0.12,0.15,0.2,0.3` `--min-separation
    0.4,0.6,0.8,1.0`) to warm the keypoint cache and get a ranked candidate list.
25. Pick the best-scoring `(floor_k, min_peak_separation_seconds)` combination over the
    **non-held-out** corpus and update `HITTING_WRIST_FLOOR_K`/`MIN_PEAK_SEPARATION_SECONDS` in
    `phases.py` to match.
26. Run `python backend/tools/segmentation_report.py --score` (full corpus, including the held-out
    clip) with the chosen constants. Every non-held-out row must be `PASS`. The held-out row is a
    hard gate too (see the plan-level Held-out discipline note above) — record its result either
    way, but do not iterate `floor_k`/`min_peak_separation_seconds` in response to it.
27. Run `RUN_MODEL_INTEGRATION_TESTS=1 pytest backend/tests/test_segmentation_ground_truth.py -v`
    — the existing six-phase-timestamp regression suite must stay green. Boundary placement moving
    (even with the same final serve count) can shift which frames land in which segment, which
    could shift `detect_phases`' within-segment results; this is the check that it didn't.
28. If any non-held-out row fails after a reasonable sweep grid, treat it as a genuine defect —
    widen the grid or revisit the floor/NMS design per requirements.md's locked approach, but do
    not special-case a single clip's constants. If a held-out or negative-case row's target itself
    turns out to be wrong (e.g. the recorded footage doesn't actually contain what its filename
    claims), fix the ground-truth entry, not the algorithm.
29. Record the final constants, the full `--score` table, and the sweep grid explored in
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
