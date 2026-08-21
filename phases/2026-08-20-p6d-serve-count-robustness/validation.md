# Phase P6d — Validation

## Definition of Done

Phase P6d is complete when all of the following pass.

## Corpus Placement & Count Ground Truth (Group 1)

| Check | How to verify |
|---|---|
| `serve_segmentation_corpus/` exists with the four renamed legacy clips at their new paths (as `holdout`/`holdout_b` variants, since the user placed them as held-out entries rather than as plain `a`/`b`/`c`/`legacy` variants) | `ls backend/tools/calibration_data/serve_segmentation_corpus/` — `open_right_flat_2serve_30fps_720x1280_galdi_holdout.MOV`, `open_right_flat_2serve_60fps_2160x3840_galdi_holdout.MOV`, `open_right_flat_2serve_60fps_1080x1920_galdi_holdout.MOV`, `open_right_flat_3serve_60fps_1080x1920_galdi_holdout_b.MOV` present alongside the user-placed corpus. |
| Every corpus filename matches the `{view}_{hand}_{type}_{count}_{fps}_{res}_{name}[_{variant}].MOV` convention, with no field value containing an internal `_` | Inspection — each filename splits cleanly into exactly 7 or 8 `_`-delimited tokens (8 when `variant` is present) matching requirements.md's field table. |
| `ag_three_serves.MOV` left in place, unrenamed | `ls backend/tools/calibration_data/ag_three_serves.MOV` still resolves. |
| Full user-placed corpus present (15 files: the 2/3/4/5-serve matrix cells, three holdout clips, and idle/tosscatch/ballbounce/shadowswing) | `ls backend/tools/calibration_data/serve_segmentation_corpus/` against the table in requirements.md's "Corpus placement and naming convention" section — already confirmed present before this spec revision landed. |
| `segmentation_count_ground_truth.json` has one entry per corpus video (20 total: 15 user-placed + 4 legacy-renamed + `ag_three_serves.MOV`) with `expected_count` equal to each filename's `count` token, `held_out: true` on all seven holdout clips, and `blocking: false` only on the shadow-swing row | Inspection — cross-check against plan.md Group 1 step 3's JSON verbatim. |

## `--score` Mode (Group 2)

| Check | How to verify |
|---|---|
| `score_videos` reports PASS/FAIL correctly against a stub count | `-only-testing` (or plain) run of `backend/tests/test_segmentation_report.py`'s new score cases. |
| A ground-truth entry with no file on disk reports `MISSING`, not an exception | Same suite. |
| A ground-truth entry omitting `blocking` defaults to `blocking: true` | Same suite. |
| Held-out and non-blocking rows are visually distinguished in `print_score_table`'s output | Same suite — asserts `[HELD OUT]` appears for a `held_out: true` row and `[KNOWN LIMITATION]` for a `blocking: false` row. |
| `scripts/verify.sh backend` green | Full backend suite. |

## Keypoint-Caching Sweep Tool (Group 3)

| Check | How to verify |
|---|---|
| A cached video's inference is not re-run on a second call | `backend/tests/test_segmentation_sweep.py` — stub inference call count is 1 after two `load_or_build_cache` calls on the same (unchanged) video. |
| A changed video invalidates its cache | Same suite — different mtime/hash triggers re-inference. |
| `sweep` ranks results best-first and excludes held-out entries from scoring | Same suite. |
| `scripts/verify.sh backend` green | Full backend suite. |

## Peak-Detection Algorithm (Group 4)

| Check | How to verify |
|---|---|
| `segment_serves`'s public signature and `list[list[Frame]]` return shape are unchanged (new params are all defaulted) | Inspection of the diff; `backend/app/routers/segment.py`'s two call sites compile/run unmodified. |
| `_find_serve_peaks` counts via positive-score local maxima + greedy NMS on real-second separation | Code inspection against requirements.md's design; covered end-to-end by Group 5's tests. |
| Boundary placement between two peaks reuses existing rest-gap logic, bounded to the span between them, with a time-midpoint fallback | Code inspection of `_place_boundary`; covered by Group 5's rewritten two-serve tests. |
| No other backend test file regresses from the Group 4 rewrite | `scripts/verify.sh backend` — only `test_segment_serves.py` is expected to fail until Group 5 lands. |

## Test Rewrite (Group 5)

| Check | How to verify |
|---|---|
| Every pre-existing `test_segment_serves.py` case's *intent* is preserved under the new vertical-motion fixtures | `pytest backend/tests/test_segment_serves.py -v` — all cases pass; diff review confirms no case was silently dropped rather than reframed. |
| `test_segmentation_is_fps_invariant` still passes with peak separation expressed in real seconds | Same file — this is the direct regression guard against reintroducing a frame-count-based (fps-dependent) separation check. |
| New peak/NMS unit tests cover toss-and-catch rejection, close-peak collapse, and missing-keypoint exclusion | Same file — `test_toss_and_catch_shape_yields_zero_peaks`, `test_two_close_peaks_collapse_to_one`, `test_missing_neck_or_pelvis_excludes_frame_without_crashing`. |
| `scripts/verify.sh backend` fully green | Full backend suite, zero failures. |

## Real-Corpus Calibration (Group 6) — **hard merge gate**

Run against the full real corpus with real models. **Every `blocking: true` row must pass before
merging** (whether `held_out` or not) — the sole exception is the shadow-swing row
(`blocking: false`), which is recorded but never gates.

| Check | How to verify |
|---|---|
| Sweep grid explored and a `(floor_k, min_peak_separation_seconds)` combination selected on non-held-out data | `python backend/tools/segmentation_sweep.py --floor-k ... --min-separation ...` output, recorded in run notes below. |
| Every `blocking: true`, non-held-out corpus row (matrix cells + `ag_three_serves.MOV` + `tosscatch`/`ballbounce`/`idle`) is `PASS` | `python backend/tools/segmentation_report.py --score` full table. **Blocking.** |
| All seven held-out rows (2-serve at 30fps/720×1280, 60fps/1080×1920, and 60fps/2160×3840; 3-serve/60fps ×2; 4-serve/30fps; 5-serve/60fps) recorded; if any fails, disclosed as a finding rather than chased with constant retuning | Same `--score` run; run notes state each outcome and confirm no post-hoc constant change was made in direct response to a held-out-specific failure. **Every held-out row must still PASS to merge** — see plan.md's held-out discipline note for what "disclosed, not chased" means in practice. |
| Six-phase timestamp ground truth regression still passes | `RUN_MODEL_INTEGRATION_TESTS=1 pytest backend/tests/test_segmentation_ground_truth.py -v` — zero failures. |
| `tosscatch`/`ballbounce` clips correctly count only their real serves, ignoring the mixed-in distractor motion | Same `--score` table; both clips show `PASS` (detected count equals their real-serve count) — a failure here is a genuine defect in the body-relative floor, not an accepted gap. |
| Shadow-swing clip's result recorded but non-blocking | Same `--score` table; the row shows `[KNOWN LIMITATION]`, and its actual vs. expected (2) count is recorded in run notes regardless of PASS/FAIL — does not affect the merge decision. |

## Documentation & Cross-Cutting (Group 7)

| Check | How to verify |
|---|---|
| `HANDEDNESS`'s comment documents the P7b prerequisite escalation | Inspection of `backend/app/engine/phases.py`. |
| No iOS file, `rules.json`, or `detect_phases`/`compute_metric_value`/`_passes` diff | `git diff --name-only develop...HEAD` excludes `App/`; `git diff develop...HEAD -- backend/rules.json` limited to whatever `detect_phases`-adjacent code this phase legitimately didn't touch (empty for `rules.json`). |
| Full backend suite green as the final check | `scripts/verify.sh backend`. |

## Merge Criteria

Minimum bar for squash-merging into `develop`:

1. `scripts/verify.sh backend` green.
2. Every Group 1–5 and Group 7 table row above verified.
3. **Group 6's hard gate fully satisfied**: every `blocking: true` corpus row PASS — including all
   seven held-out clips (results disclosed, not used to retune constants) — and the six-phase
   ground-truth regression suite green. Not disclosable — if the corpus doesn't match the
   ground-truth JSON or Group 6 was never run, the phase does not merge. The shadow-swing clip
   (`blocking: false`) is the sole exception and never gates.
4. No iOS file, `rules.json`, or phase-detection/rule-evaluation logic in the changed-file list —
   this phase changes serve counting and segment boundary placement only.
5. The shadow-swing clip's `expected_count: 2` and `blocking: false` are confirmed intentional (not
   accidentally left as a TODO) in the final ground-truth JSON.

**Run notes:**

_(Filled in during `/phase` and `/phase-review`.)_
