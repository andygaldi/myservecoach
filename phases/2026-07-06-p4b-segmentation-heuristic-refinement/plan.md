# Phase P4b — Plan

> **Lite-isolation note:** every task group touches only `backend/`. No group modifies
> `PhaseReviewView`, the Lite pipeline/segmentation services, `ContentView`, or any file under
> `App/`. `RTMPoseModel`, `ObjectDetectionModel`, and `calibration_report.py` are consumed
> unmodified, same as P4.

## Group 1 — Trophy Pose Precision Fix (surface: `backend`)

1. In `backend/app/engine/phases.py`'s `detect_phases`, in the trophy-pose loop (the `# 1. Trophy
   pose: ...` section): compute `hitting_shoulder_y = keypoint_y(frame, f"{hitting}_shoulder")`
   alongside the other keypoint lookups at the top of the loop body (next to
   `toss_wrist_y`/`toss_shoulder_y`/`hitting_wrist_y`/`hitting_hip_y`), and add it to the
   `any(v is None for v in [...])` guard list so a frame missing it is skipped like the others.
   Then add a new condition **immediately after** the existing
   `hitting_elbow_y is not None and hitting_wrist_y <= hitting_elbow_y` check and before the angle
   computation block:
   ```python
   if hitting_elbow_y is not None and hitting_elbow_y > hitting_shoulder_y:
       continue
   ```
   This rejects a candidate frame when the hitting elbow has already risen above hitting-shoulder
   height — evidence (see `requirements.md` Context) shows this discriminates the two broken
   `ag_three_serves.MOV` trophy picks from every other video's correct pick. Gated by
   `hitting_elbow_y is not None`, matching the existing style: when the elbow keypoint is absent,
   this check is skipped, consistent with the pre-existing `trophy_no_elbow_idx` fallback path.
   Update the loop's leading docstring comment to document the new condition (elbow at or below
   shoulder height).
2. In `backend/tests/test_phases.py`, add to the `# --- Trophy pose detection ---` section:
   - `test_trophy_rejected_when_elbow_above_shoulder`: build a frame from `TROPHY_KPS` with
     `right_elbow` overridden to a y clearly above `right_shoulder`'s y (e.g. `right_shoulder`
     y=0.5, `right_elbow` y=0.6) while keeping the other conditions satisfied — assert
     `result[ServePhase.trophy_pose] is None` (no fallback frame exists in a 1-frame sequence).
   - `test_trophy_passes_when_elbow_at_or_below_shoulder`: confirm `TROPHY_KPS` itself (elbow
     y == shoulder y == 0.5) still passes — this should already hold given the existing
     `test_single_trophy_frame_detected`, but add an explicit second fixture with elbow clearly
     *below* shoulder (e.g. elbow y=0.3) to confirm the condition isn't accidentally strict.
   - `test_trophy_falls_back_to_later_frame_when_elbow_above_shoulder_first`: a 2-frame sequence
     where frame 0 satisfies every original condition but has elbow above shoulder, and frame 1
     satisfies everything including the new condition — assert `result[ServePhase.trophy_pose] is
     f1`, not `f0`.
3. Run `pytest backend/tests/test_phases.py -v` — confirm all pre-existing tests still pass
   (including the ones using `TROPHY_KPS` verbatim) and the 3 new tests pass.

## Group 2 — Contact Combined-Signal Redesign & Deterministic Tie-Breaking (surface: `backend`)

4. In `backend/app/engine/phases.py`, add two more tunable constants near
   `RACKET_DROP_RACKET_WEIGHT`:
   ```python
   CONTACT_WRIST_WEIGHT = 0.5
   CONTACT_PROXIMITY_WEIGHT = 0.5
   ```
5. Add a helper above `detect_phases`:
   ```python
   def _racket_ball_distance(dets: list[Detection]) -> float | None:
       racket = next((d for d in dets if d.label == "racket"), None)
       ball = next((d for d in dets if d.label == "ball"), None)
       if racket is None or ball is None:
           return None
       racket_center = ((racket.bbox.x_min + racket.bbox.x_max) / 2, (racket.bbox.y_min + racket.bbox.y_max) / 2)
       ball_center = ((ball.bbox.x_min + ball.bbox.x_max) / 2, (ball.bbox.y_min + ball.bbox.y_max) / 2)
       return math.hypot(racket_center[0] - ball_center[0], racket_center[1] - ball_center[1])
   ```
6. Replace the existing `# 2. Contact: ...` block with a combined-signal version, following the
   `racket_drop` pattern exactly (weighted average of whichever signals are available per frame;
   reduces to today's ranking when `detections` is `None`):
   ```python
   # 2. Contact: combined wrist-height + racket-ball-proximity signal after trophy pose (mirrors
   #    racket_drop's weighted-combination pattern). Falls back to the full sequence when no
   #    trophy is detected; falls back to wrist-height-only when no detections are available or
   #    racket+ball aren't both detected in a given frame.
   search_start = trophy_idx + 1 if trophy_idx is not None else 0

   wrist_heights: dict[int, float] = {}
   for i in range(search_start, len(frames)):
       wrist_y = keypoint_y(frames[i], f"{hitting}_wrist")
       if wrist_y is not None:
           wrist_heights[i] = wrist_y

   proximities: dict[int, float] = {}
   if detections is not None:
       for i in range(search_start, len(frames)):
           if i >= len(detections):
               continue
           distance = _racket_ball_distance(detections[i])
           if distance is not None:
               proximities[i] = -distance  # lower distance (closer) => higher score

   wrist_norm = _min_max_normalize(wrist_heights)
   proximity_norm = _min_max_normalize(proximities)

   contact_idx: int | None = None
   best_score = float("-inf")
   for i in sorted(set(wrist_norm) | set(proximity_norm)):
       parts = []
       if i in wrist_norm:
           parts.append((CONTACT_WRIST_WEIGHT, wrist_norm[i]))
       if i in proximity_norm:
           parts.append((CONTACT_PROXIMITY_WEIGHT, proximity_norm[i]))
       total_weight = sum(w for w, _ in parts)
       score = sum(w * v for w, v in parts) / total_weight if total_weight else float("-inf")
       if score > best_score:
           best_score = score
           contact_idx = i
   ```
   Note the `sorted(...)` (not raw `set(...)` iteration) — this guarantees the first frame
   achieving the max score wins ties, matching the original strict-`>` loop's semantics exactly
   (ascending index order + strict `>` comparison = first-occurrence-wins).
7. Apply the same `sorted(...)` fix to the existing `racket_drop` loop's
   `for i in set(elbow_norm) | set(racket_norm):` line — change it to
   `for i in sorted(set(elbow_norm) | set(racket_norm)):`. This closes the non-deterministic
   tie-breaking gap flagged in P4's correctness review (Python `set` iteration order over ints is
   not a language guarantee).
8. In `backend/tests/test_phases.py`, add a `# --- Combined-signal contact detection ---` section:
   - `test_contact_combines_wrist_height_and_racket_ball_proximity`: build a window (trophy, 2+
     candidate frames, no natural "end") where the frame with the highest wrist_y has no
     racket/ball detections, and a slightly-lower-wrist-y frame has a racket and ball detection
     very close together — construct weights/values so the combined score favors the
     close-proximity frame, proving proximity can outweigh a purely-wrist-height-dominant frame.
   - `test_contact_all_existing_wrist_only_tests_pass_with_no_detections`: re-run the fixture from
     `test_high_wrist_before_racket_drop_is_not_contact` (or an equivalent) with no `detections`
     argument and confirm identical results to before this phase.
   - `test_contact_falls_back_when_ball_or_racket_missing_from_frame`: `detections` includes a
     racket-only or ball-only entry (never both in the same frame) — assert the result matches
     the wrist-height-only ranking (proximity is never computed without both).
   - `test_contact_detections_shorter_than_frames`: a `detections` list shorter than `frames` —
     assert no `IndexError`.
9. Run `pytest backend/tests/test_phases.py -v` — confirm all pre-existing tests
   (including every existing `contact`/`racket_drop` test) still pass unmodified, and all new
   Group 1–2 tests pass.

## Group 3 — Denser Default Sampling (surface: `backend`)

10. In `backend/tools/segmentation_report.py`'s `main()`, change the `--stride` argument's
    default from `5` to `2`:
    ```python
    parser.add_argument("--stride", type=int, default=2, help="Sample every Nth video frame.")
    ```
    Update the module docstring's `Usage:` example (`--stride 5` → `--stride 2`) and the note that
    this default is denser than P3/P4's `--stride 5` specifically to catch fast swings that can
    otherwise fall entirely between two sampled frames (see `requirements.md` Context). Leave
    `pose_benchmark.py`'s own default unchanged (`5`) — that tool's purpose (aggregate detection
    rate/confidence/FPS baselining) doesn't need per-swing precision the way segmentation does.
11. In `backend/tests/test_segmentation_report.py`, add a small test confirming the new default:
    `test_default_stride_is_two`: parse `main`'s `argparse.ArgumentParser` with no `--stride` flag
    (reuse the same construction pattern `main()` uses, or introspect
    `parser.get_default("stride")` after building the parser in isolation) and assert it equals
    `2`. If `main()`'s parser isn't easily testable in isolation, instead refactor the
    `argparse.ArgumentParser` construction in `main()` into a small `_build_arg_parser() ->
    argparse.ArgumentParser` function and call it from `main()`, so the test can call
    `_build_arg_parser().get_default("stride") == 2` directly without invoking `main()` itself.
12. Run `pytest backend/tests/test_segmentation_report.py -v` — confirm it passes.

## Group 4 — Manual Re-Validation & Full Six-Phase Spot-Check (manual, backend-only, hard merge gate)

13. Confirm which videos are in `backend/tools/calibration_data/` (the existing 6, plus any the
    user has added for this phase) and re-run `cd backend && python tools/segmentation_report.py`
    with the new `--stride 2` default and the Group 1–2 heuristic changes.
14. Confirm `segment_serves`'s expected-vs-actual serve counts (from P4's table) still hold with
    the denser stride — re-tune `MIN_REST_SECONDS`/`LOW_MOTION_VELOCITY_THRESHOLD` if the change in
    sampling density shifts them (a finer stride changes the real-time meaning of consecutive
    "rest" frame steps only indirectly, since both constants are already time-based per P4's
    fps-invariance fix, but confirm empirically rather than assuming).
15. Specifically confirm `ag_three_serves.MOV`'s previously-`None` `racket_drop` cases: open its
    regenerated report and check whether the denser stride now provides a frame between the
    (now-corrected) `trophy_pose` and `contact` picks for `racket_drop` to select from. Record
    whether this resolved incidentally (per this phase's Key Decision) or still needs the
    structural fallback noted in `requirements.md`'s In Scope list.
16. Full visual spot-check of **all six phases across every video** (not the 2–3 sampled in P4) —
    for each video, open its `report.html`, and for `start`/`release`/`trophy_pose`/`racket_drop`/
    `contact`/`finish` confirm the frame plausibly matches its Kovacs stage. Pay particular
    attention to: whether `trophy_pose` now lands on a clearly "loaded" (not mid-Cocking) frame on
    every video including `ag_three_serves.MOV`/`vesa_slow_mo.mov`; whether `contact`'s
    racket-ball-proximity signal visibly improves precision on any video where both are reliably
    detected; whether `vesa_slow_mo.mov`'s originally-flagged "less crisp" trophy/racket_drop
    frames look better now.
17. If a heuristic is still visibly wrong after the code changes, iterate on the relevant tunable
    constant first (`MIN_REST_SECONDS`, `LOW_MOTION_VELOCITY_THRESHOLD`, `RACKET_DROP_ELBOW_WEIGHT`,
    `RACKET_DROP_RACKET_WEIGHT`, `CONTACT_WRIST_WEIGHT`, `CONTACT_PROXIMITY_WEIGHT`, or `--stride`)
    before considering a further structural change; a further structural change requires stopping
    and checking with the user, same as P4's precedent.
18. Record, in this phase's `validation.md` run notes: final tuned constant values (all six
    tunables plus the stride default), the expected-vs-actual serve-count table re-confirmed,
    the `ag_three_serves.MOV` `racket_drop` resolution outcome, and a qualitative six-phase
    assessment per video (at minimum: did anything get worse compared to P4's spot-check record).
19. **Author `backend/tools/segmentation_ground_truth.json`** (git-tracked — small metadata file,
    sibling to the gitignored `calibration_data/` it references, same pattern as P3's
    `pose_benchmark_baselines/`). For every video and every detected serve, record the real-world
    timestamp (seconds, from the final `report.html` generated in step 13) of each of the six
    phases, determined by the same visual spot-check as step 16. Schema:
    ```json
    {
      "tolerance_seconds": 0.15,
      "videos": {
        "serve_1.MOV": [
          {
            "serve_index": 1,
            "phases": {
              "start": 1.30, "release": 1.43, "trophy_pose": 1.53,
              "racket_drop": 1.57, "contact": 1.60, "finish": 2.50
            }
          }
        ],
        "ag_three_serves.MOV": [
          {"serve_index": 1, "phases": {"start": null, "...": "..."}}
        ]
      }
    }
    ```
    A phase value may be `null` if, after the code fixes above, no frame genuinely represents it
    for that serve (e.g. `racket_drop` if step 15 concludes it's still structurally unresolvable
    for a given serve) — the regression test (Group 5) must treat `null` as "expect `None`," not
    skip the check entirely, so a future regression that makes it resolve to a *wrong* frame is
    still caught.

## Group 5 — Ground-Truth Regression Test (surface: `backend`)

20. Create `backend/tests/test_segmentation_ground_truth.py`, gated exactly like
    `test_pose_model_integration.py`/`test_object_detection_integration.py`:
    ```python
    @pytest.mark.skipif(
        not os.environ.get("RUN_MODEL_INTEGRATION_TESTS"),
        reason="Requires real models + local calibration_data videos; opt-in via RUN_MODEL_INTEGRATION_TESTS=1",
    )
    ```
21. `def test_all_videos_match_ground_truth():` — loads
    `backend/tools/segmentation_ground_truth.json`; constructs real `get_pose_model()`/
    `get_object_detection_model()`; for each video in the JSON, calls `build_frame_sequence`
    (imported from `tools.segmentation_report`) at `stride=2` (the new default from Group 3),
    `segment_serves(frames)`, slices the parallel `detections` list at the same boundaries
    (identical cursor-based slicing to `run_segmentation_report`'s own logic — consider factoring
    this slicing into a small shared helper in `segmentation_report.py`, e.g.
    `def slice_detections_by_segments(detections, segments) -> list[list[list[Detection]]]`, reused
    by both `run_segmentation_report` and this test to avoid duplicating the cursor logic), then
    `detect_phases(segment_frames, segment_detections)` per serve. Asserts:
    - The detected serve count matches `len(expected_serves)` for every video.
    - For every recorded phase timestamp (including `null` ones, which must resolve to `None`),
      the detected frame is within `tolerance_seconds` of the expected timestamp (or is `None` when
      expected is `null`).
    Collect all mismatches across all videos/serves/phases into one list and `assert not failures,
    "\n".join(failures)` at the end, so a single run reports every discrepancy at once rather than
    stopping at the first.
22. Run `RUN_MODEL_INTEGRATION_TESTS=1 pytest backend/tests/test_segmentation_ground_truth.py -v`
    — confirm it passes against the ground truth authored in step 19 (first run downloads nothing
    new; weights are already cached from P1–P4).
23. Run `pytest backend/` (no env var set) — confirm the new test is skipped by default and the
    full suite (including all Group 1–3 additions) passes with zero failures.
24. Confirm no iOS files were touched at all this phase: `git diff --name-only develop...HEAD`
    contains no changes under `App/`.
