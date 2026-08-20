# Phase P6d — Validation

## Definition of Done

Phase P6d is complete when all of the following pass.

## Corpus Placement & Count Ground Truth (Group 1)

| Check | How to verify |
|---|---|
| `serve_segmentation_corpus/` exists with the four renamed matrix clips at their new paths | `ls backend/tools/calibration_data/serve_segmentation_corpus/` — `2serve_30fps.MOV`, `2serve_60fps_a.MOV`, `2serve_60fps_b.MOV`, `3serve_60fps.MOV` present. |
| `ag_three_serves.MOV` left in place, unrenamed | `ls backend/tools/calibration_data/ag_three_serves.MOV` still resolves. |
| Full corpus present before Group 6 runs (5serve×2fps, held-out, 4 negatives) | Manual confirmation with the user per plan.md Group 1 step 3; Group 6 does not proceed on a partial corpus. |
| `segmentation_count_ground_truth.json` has one entry per corpus video with correct `expected_count`/`held_out` | Inspection — cross-check against the table in requirements.md's "Corpus placement and naming convention" section; the held-out row's key/count updated to match the actually-placed file. |

## `--score` Mode (Group 2)

| Check | How to verify |
|---|---|
| `score_videos` reports PASS/FAIL correctly against a stub count | `-only-testing` (or plain) run of `backend/tests/test_segmentation_report.py`'s new score cases. |
| A ground-truth entry with no file on disk reports `MISSING`, not an exception | Same suite. |
| Held-out rows are visually distinguished in `print_score_table`'s output | Same suite — asserts `[HELD OUT]` appears for a `held_out: true` row. |
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

Run against the full real corpus with real models. **All rows must pass before merging**, except
where explicitly noted as disclose-don't-block.

| Check | How to verify |
|---|---|
| Sweep grid explored and a `(floor_k, min_peak_separation_seconds)` combination selected on non-held-out data | `python backend/tools/segmentation_sweep.py --floor-k ... --min-separation ...` output, recorded in run notes below. |
| Every non-held-out corpus row (matrix + `ag_three_serves.MOV` + negatives) is `PASS` | `python backend/tools/segmentation_report.py --score` full table. **Blocking.** |
| Held-out row recorded; if it fails, disclosed as a finding rather than chased with constant retuning | Same `--score` run; run notes state the outcome either way and confirm no post-hoc constant change was made in direct response to it. **The held-out row must still PASS to merge** — see plan.md's held-out discipline note for what "disclosed, not chased" means in practice. |
| Six-phase timestamp ground truth regression still passes | `RUN_MODEL_INTEGRATION_TESTS=1 pytest backend/tests/test_segmentation_ground_truth.py -v` — zero failures. |
| Negative cases reject/register per their documented expected counts, including the disclosed `negative_shadow_swing.MOV` limitation | Same `--score` table; `negative_shadow_swing.MOV` shows `PASS` against `expected_count: 1`, not treated as a bug. |

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
3. **Group 6's hard gate fully satisfied**: every non-held-out corpus row PASS, the held-out row
   PASS (with its result disclosed, not used to retune constants), and the six-phase ground-truth
   regression suite green. Not disclosable — if the full corpus was never placed or Group 6 was
   never run, the phase does not merge.
4. No iOS file, `rules.json`, or phase-detection/rule-evaluation logic in the changed-file list —
   this phase changes serve counting and segment boundary placement only.
5. `negative_shadow_swing.MOV`'s `expected_count: 1` is confirmed intentional (not accidentally
   left as a TODO) in the final ground-truth JSON.

**Run notes:**

_(Filled in during `/phase` and `/phase-review`.)_
