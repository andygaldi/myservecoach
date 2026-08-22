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

Groups 1–5 implemented and verified via `scripts/verify.sh backend` (green, 202 passed / 3
skipped) before starting Group 6.

**Sweep grid (initial pass, `segmentation_sweep.py`):** `--floor-k 0.05,0.1,0.15,0.2,0.25
--min-separation 0.3,0.4,0.5,0.6,0.8,1.0` against the 13 non-held-out corpus videos (cache-cold
first pass; real inference across all 13 took roughly an hour of wall-clock CPU time, dominated by
one clip — `open_right_ballbounce_3serve_30fps_720x1280_galdi.MOV` — taking disproportionately
long relative to its frame count, cause not further investigated since it completed). Best score:
12/13 matches, achieved by several combinations including `floor_k=0.15,
min_peak_separation_seconds ∈ {0.5, 0.6, 0.8, 1.0}` (the Group 4 defaults' column). The one
non-matching row at every combination in this grid was the shadow-swing clip
(`blocking: false`), exactly the documented, non-gating known limitation — not a real failure.
`(0.15, 0.6)` (the Group 4 defaults) was confirmed to already sit at this ceiling: 12/12 on the
*blocking* non-held-out rows.

**`--score` full corpus (first pass, `floor_k=0.15, min_peak_separation_seconds=0.6`):** all 19
corpus rows with `blocking: true` PASS, including all 7 held-out clips
(`open_right_flat_2serve_30fps_720x1280_galdi_holdout.MOV`,
`open_right_flat_2serve_60fps_1080x1920_galdi_holdout.MOV`,
`open_right_flat_2serve_60fps_2160x3840_galdi_holdout.MOV`,
`open_right_flat_3serve_60fps_1080x1920_galdi_holdout.MOV`,
`open_right_flat_3serve_60fps_1080x1920_galdi_holdout_b.MOV`,
`open_right_flat_4serve_30fps_1080x1920_galdi_holdout.MOV`,
`open_right_flat_5serve_60fps_1080x1920_galdi_holdout.MOV`). `tosscatch`/`ballbounce` both PASS
(3/3), confirming the body-relative floor correctly ignores the mixed-in distractor motion in
both. Shadow-swing: expected 2, actual 3 — `[KNOWN LIMITATION]`, non-blocking, recorded per the
merge criteria's explicit exception.

**Six-phase regression suite — genuine defect found and fixed.** Running
`RUN_MODEL_INTEGRATION_TESTS=1 pytest backend/tests/test_segmentation_ground_truth.py -v` at
`(0.15, 0.6)` surfaced a real regression: `vesa_slow_mo.mov` (a legacy slow-motion clip, not part
of the new corpus) — expected 1 serve, detected 4. Root-caused by re-running the identical suite
against the pre-P6d baseline (`git stash` on `phases.py` only): baseline correctly counted 1 serve
for this clip (only a pre-existing `contact`-phase timing miss), confirming this was a rewrite
regression, not a stale ground-truth entry. Cause: a single slow-motion swing's wrist trajectory
produces several weak, closely-spaced local maxima above the body-relative floor (scores as low as
0.004–0.13) that `min_peak_separation_seconds=0.6` was too tight to collapse into one accepted
peak.

Per plan.md step 28 ("widen the grid ... but do not special-case a single clip's constants"), the
grid was widened (`floor_k` up to 0.35, `min_peak_separation_seconds` up to 3.0) and scored against
both the cached P6d corpus and a locally-cached `vesa_slow_mo.mov`. Result: holding
`floor_k=0.15` and raising `min_peak_separation_seconds` to `1.5` fixes `vesa_slow_mo.mov` (1
detected) while holding the P6d blocking corpus at its prior ceiling (12/12) — confirmed by
re-running the full `--score` pass (identical result to the `(0.15, 0.6)` table above: 19/19
blocking PASS, 7/7 held-out PASS, shadow-swing unchanged at actual=3) and the six-phase suite
again.

**Final constants: `HITTING_WRIST_FLOOR_K = 0.15`, `MIN_PEAK_SEPARATION_SECONDS = 1.5`.**

**Six-phase suite, final state:** still not fully green — `serve_2.mov` (`trophy_pose`,
delta=0.205 > tolerance=0.13), `alcaraz_serve_1.mov` (`start`/`release`/`racket_drop`/`finish`, all
failing), and `vesa_slow_mo.mov` (`contact`, delta=0.137 > tolerance=0.075) still fail. All three
were re-verified against the pre-P6d baseline run and are **byte-identical** (same deltas, same
phases) to failures that already existed before this phase's changes — pre-existing
`detect_phases` six-phase heuristic issues, explicitly out of scope per requirements.md ("Out of
Scope: `detect_phases`'s six-phase heuristics ... a defect there is P4b/P6b's domain, not this
one's"). Zero *new* failures remain after the fix; the plan's "must stay green" precondition
(step 27) turned out to already be false at baseline for reasons unrelated to serve counting — this
is disclosed here rather than silently redefined. The count-specific regression this phase owns
(`vesa_slow_mo.mov`'s serve count) is resolved.

Raising `min_peak_separation_seconds` to 1.5 required widening several fast-unit-test fixtures in
`test_segment_serves.py`, `test_segment_endpoint.py`, and `test_segmentation_report.py` whose
two-peak gaps were sized for the old 0.6s threshold (~0.85s real gap) and no longer cleared 1.5s;
re-widened to ~2.0–2.2s real gaps with margin. `scripts/verify.sh backend` confirmed green
afterward (202 passed, 3 skipped) — same count as before Group 6, no coverage lost.

**`/phase-review` — three-perspective deep review (correctness / design / spec compliance), findings applied:**

- **Fixed — dead test-fixture duplication.** `_kp`/`_positioned_frame`/`_hump`/`_rest_burst` and
  the `NECK_Y`/`PELVIS_Y`/`IDLE_WRIST_Y`/`PEAK_WRIST_Y` geometry constants were defined nearly
  verbatim in both `test_segment_serves.py` and `test_segment_endpoint.py`. Consolidated the
  shared Frame-returning versions into `conftest.py` (`kp`, `positioned_frame`, `hump`,
  `rest_burst`, plus the four geometry constants); `test_segment_serves.py` now imports them
  under their prior local names (zero call-site changes), `test_segment_endpoint.py` keeps thin
  local `_hump`/`_rest_burst` wrappers that add the `.model_dump()` conversion its JSON-posting
  fixtures need. `FLOOR_Y`/`BOUNCE_WRIST_Y` stay local to `test_segment_serves.py` since nothing
  else uses them.
- **Fixed — stale comment.** `test_segment_serves.py`'s `test_two_close_peaks_collapse_to_one`
  had a comment referencing the pre-calibration sweep optimum (`0.6s`) instead of the actually-
  shipped `MIN_PEAK_SEPARATION_SECONDS` (`1.5`); updated to name the constant instead of a stale
  literal so it can't drift out of sync again.
- **Fixed — unused import.** `test_segmentation_sweep.py` imported `CachedVideoFrames` from
  `tools.segmentation_sweep` without ever referencing it; removed.
- **Fixed — cosmetic undercount in `print_score_table`'s summary line.**
  `segmentation_report.py`: a `blocking: true`/`held_out: false` row with `status == "MISSING"`
  was counted only toward `missing`, never toward `blocking_total`, so the printed "N/M blocking
  passed" ratio understated `M` for a genuinely-missing required video. `main()`'s actual exit-code
  gate was unaffected (any non-`PASS` status already fails it), so this was display-only; fixed by
  making the `blocking_total`/`blocking_passed` accounting unconditional on `MISSING` status
  rather than mutually exclusive with it.
- **Disclosed, not changed — six-phase suite "byte-identical to baseline" claim.** The review
  flagged that Merge Criteria item 3 literally requires the six-phase regression suite green, but
  the run notes above disclose three pre-existing failures instead, backed by a `git stash`-based
  baseline comparison described in prose rather than an attached diff/table. Left as-is: the
  comparison method (running the identical suite against `phases.py` reverted via `git stash`) is
  sound and was actually performed, not fabricated; re-attaching a full before/after delta table
  here would be redone work the reviewer flagged as unverifiable-from-the-diff-alone, not as
  wrong. Recorded here so a future reader has the caveat, not just the conclusion.

All four applied fixes re-verified via `scripts/verify.sh backend`: 202 passed, 3 skipped — same
count as before the review, no coverage lost.
