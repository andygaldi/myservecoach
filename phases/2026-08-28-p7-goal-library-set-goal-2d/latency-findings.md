# P7 — Live-Feedback Latency Findings & Remaining Work

Pre-implementation review of this phase's `plan.md`, asking whether Set Goal can speak a pass/fail
cue within a few seconds of each serve. Answer as planned: **no**. Two blockers were found and
investigated with measurements; one code change has already landed. This file records the evidence
and what is left, so `/phase` can be run on P7 without re-deriving any of it.

## Status summary

| Item | State |
|---|---|
| Latency probe tool written + run | Done — `backend/tools/goal_latency_probe.py` (untracked) |
| `MIN_PEAK_SCORE` margin added to segmentation | Done — `backend/app/engine/phases.py` (modified, uncommitted) |
| `scripts/verify.sh backend` | Green — 202 passed, 3 skipped |
| 20-clip fused-vs-rtmlib count comparison **with** the margin | Done — passed, 0 disagreements |
| Group 0 production wiring (fused pipeline into services) | Not started, deliberately |
| Amendments to `plan.md` groups 2/4/6/8 | Not started |

Nothing is committed. Working tree: `backend/app/engine/phases.py` modified,
`backend/tools/goal_latency_probe.py` untracked.

## Blocker A — segment confirmation waits for the *next* serve (design, unfixed)

`plan.md:160` confirms segment N only once segment N+1's peak exists:
`confirmed_count = len(segments) if is_final else max(0, len(segments) - 1)`.

So the player hears serve N's verdict **after hitting serve N+1** — one inter-serve interval late
(~10–30s in a real drill), and the last serve gets no live cue until Stop.

The plan chose this because `_find_serve_peaks` treats the final plateau as a local max when
`next_score is None`, so the buffer's trailing edge can register a spurious peak mid-serve.

**Fix to apply in Group 2:** confirm a segment once its peak is far enough behind the buffer's
trailing edge to no longer be an edge artifact:

```python
CONFIRM_LAG_SECONDS = MIN_PEAK_SEPARATION_SECONDS  # 1.5, phases.py
buffer_end = buffer.frames[-1].timestamp
confirmed_count = len(segments) if is_final else sum(
    1 for seg in segments if _peak_timestamp(seg) <= buffer_end - CONFIRM_LAG_SECONDS
)
```

`segment_serves` returns segments, not peaks, so `phases.py` needs an additive way to get accepted
peak timestamps (e.g. `segment_serves_with_peaks`) rather than re-deriving them in the router.
1.5s is already the algorithm's own "two peaks this close are the same serve" distance. This turns
the latency floor from one inter-serve interval into 1.5s.

**Document as a known limitation:** `_min_max_normalize` makes peak scores relative to the whole
buffer and acceptance is greedy over globally-sorted scores, so segment *i*'s extent is not
guaranteed stable as the buffer grows, while `reported_count` indexing assumes it is. Consequence
is a re-cut segment being re-scored but never re-spoken.

## Blocker B — pose throughput was 4x slower than realtime (measured, solved)

Measured with `backend/tools/goal_latency_probe.py` on the M3 Max, `ag_three_serves.MOV`
(720x1280@30). Realtime factor = chunk seconds / seconds to process; >1.0 means no backlog.

| pipeline | device | chunk | stride | pose | detect | total | realtime |
|---|---|---|---|---|---|---|---|
| rtmlib | cpu | 2s | 2 | 4.00s | 0.58s | 4.58s | **0.44x** |
| rtmlib | cpu | 4s | 2 | 7.98s | 1.14s | 9.12s | **0.44x** |
| rtmlib | mps | — | — | — | — | — | **unsupported** |
| fused | cpu | 2s | 2 | 0.29s | 0.58s | 0.88s | **2.28x** |
| fused | cpu | 4s | 2 | 0.62s | 1.17s | 1.79s | **2.24x** |
| fused | mps | 2s | 2 | 0.14s | 0.46s | 0.60s | **3.33x** |
| fused | mps | 4s | 2 | 0.23s | 0.84s | 1.07s | **3.72x** |

`segment_serves` + `detect_phases` + `evaluate_rules` are <1ms in every config — all cost is inference.

**`POSE_MODEL_DEVICE=mps` alone does not work.** CoreML EP is present (ORT 1.27) and rtmlib maps
`device="mps"` to it, but rtmlib's YOLOX-m detector fails under it:
`CoreML static output shape ({1,1,1,8400,8400}) and inferred shape ({1,8400}) have different ranks`.

**Where the time actually goes** — splitting `rtmlib.Body` over 30 frames:

| Component | 30 frames | FPS |
|---|---|---|
| YOLOX-m person detector (inside `Body`) | 3.41s | 8.8 |
| RTMPose-m (the pose model itself) | 0.29s | 104.4 |

92% of pose cost is a **redundant** person detector. `ObjectDetectionModel` (YOLO11n) already runs
on every frame for racket/ball, is full COCO, and detects class 0 `person` — which
`map_yolo_results_to_detections` filters out and discards. Person found in 30/30 frames.

### The `fused` design (to be wired in Group 0)

Run YOLO11n once per frame; use its output for both racket/ball detections *and* the person bbox
fed directly to a standalone `RTMPose` (same ONNX checkpoint `Body` loads, so the keypoint model is
unchanged — only the crop box's source differs). Drop YOLOX-m entirely.

**Subject selection matters:** pick the **largest-area** person box, mirroring
`select_primary_person` (`pose_model.py:57-65`). Picking highest-confidence instead lets a crisp
background figure win and swaps the tracked subject mid-clip. `goal_latency_probe.py`'s
`FusedPipeline` already does this correctly — copy that logic, don't re-derive it.

The bbox handed to RTMPose must be **pixel xyxy, unflipped and unnormalized** — the y-flip in
`map_yolo_results_to_detections` is for the backend's own coordinate convention and must not be
applied here.

## The `MIN_PEAK_SCORE` margin — already applied

The first 20-clip corpus comparison (fused vs rtmlib, `segment_serves` counts) came back **19/20
identical and matching ground truth**, with one disagreement:
`open_right_flat_5serve_30fps_720x1280_galdi.MOV` — truth 5, rtmlib 5, fused 6.

It was **not** a fused defect. All five real serves were found identically by both pipelines
(t = 7.4/7.47, 15.34, 25.07, 35.28, 46.81). The spurious 6th was a bump at t=50.08 where the wrist
hovers exactly at the body-relative floor: rtmlib scored it **−0.0005** (rejected), fused **+0.0038**
(accepted). `_find_serve_peaks` accepted on `score > 0` with no margin, so a ~0.004 difference
(≈3px at 720p, inside the pipelines' 0.0026 mean keypoint delta) flipped the serve count.

An earlier hypothesis — fused picking highest-confidence where `select_primary_person` picks
largest-area — was **tested and ruled out**; matching the area rule left the count at 6. (The
area-based selection is still correct and stays.)

Peak-score separation across the whole corpus is large: real serve peaks score **0.0705–0.2233**,
the artifact **0.0038**. Margin sweep, clips matching ground truth:

| margin | matches |
|---|---|
| `score > 0` (old) | 18/20 |
| `score > 0.005` | 19/20 |
| `score > 0.02` | 19/20 |
| `score > 0.05` | 19/20 |

(The remaining 1 is `shadowswing`, which no margin fixes and which the ground-truth file already
documents as non-blocking.) User chose to add the margin.

**Change made in `backend/app/engine/phases.py`:**
- new `MIN_PEAK_SCORE = 0.02` constant with the evidence in a comment
- `_find_serve_peaks(..., min_peak_score: float = MIN_PEAK_SCORE)`; acceptance is now
  `if score <= min_peak_score: continue`
- threaded through `segment_serves` as a keyword param alongside `floor_k` /
  `min_peak_separation_seconds`, so `segmentation_sweep.py` can grid it
- updated the stale comment claiming only positive-score plateaus are accepted

**Verification done:** `scripts/verify.sh backend` green (202 passed, 3 skipped);
`test_segment_serves.py` 15/15 including the `_find_serve_peaks` unit tests.

## Pre-existing failure, NOT caused by this work

`backend/tests/test_segmentation_ground_truth.py` is **already red on `develop`**. Six
phase-timestamp failures, identical set and identical deltas with and without the margin (verified
by stashing the change and re-running; the two failure lists diff clean):

```
serve_2.mov serve 1 trophy_pose: expected t=1.127, got t=0.922 (delta=0.205 > tolerance=0.13)
vesa_slow_mo.mov serve 1 contact: expected t=4.723, got t=4.586 (delta=0.137 > tolerance=0.075)
alcaraz_serve_1.mov serve 1 start: expected t=4.907, got t=2.904 (delta=2.003 > tolerance=0.2)
alcaraz_serve_1.mov serve 1 release: expected t=6.710, got t=6.376 (delta=0.334 > tolerance=0.075)
alcaraz_serve_1.mov serve 1 racket_drop: expected t=9.748, got t=9.581 (delta=0.167 > tolerance=0.13)
alcaraz_serve_1.mov serve 1 finish: expected t=11.484, got t=10.115 (delta=1.369 > tolerance=0.2)
```

These are phase *timing* deltas; no serve-count assertion fires in either run. Invisible in normal
runs because the test is opt-in behind `RUN_MODEL_INTEGRATION_TESTS=1`, which `scripts/verify.sh`
does not set. Worth its own fix; out of scope for P7.

## Corpus re-check with the margin applied — PASSED

Re-ran the full 20-clip comparison with `MIN_PEAK_SCORE = 0.02` in place, both pipelines:

- **`pipelines disagree on 0 video(s)`** — fused and rtmlib now return identical counts on all 20.
- **19/20 match ground truth.** The sole miss is `shadowswing` (expected 2, both return 3) — the
  limitation already documented in `tools/segmentation_count_ground_truth.json`, unchanged by both
  the margin and the pipeline swap.
- **rtmlib counts are unchanged by the margin** — clip-for-clip identical to the pre-margin run,
  including `open_right_flat_5serve_30fps_720x1280_galdi.MOV` (still 5). The margin only removed
  fused's spurious 6th peak, exactly as the epsilon sweep predicted.
- Per-keypoint deltas corpus-wide: mean 0.0020–0.0071, p95 0.0043–0.0112.

Both accuracy gates on the fused swap are now clear. Group 0 is unblocked.

## Remaining step 1 — Group 0: wire the fused pipeline (surface: `backend`)

1. Keep `backend/tools/goal_latency_probe.py` as a committed sibling to `pose_benchmark.py` — it is
   the reproducible evidence and the regression check if the pipeline changes again.
2. `backend/app/services/pose_model.py`: add a person-bbox-accepting path to `RTMPoseModel` —
   `infer(image, person_bbox=None)`, loading a standalone `rtmlib.RTMPose` (same checkpoint and
   input size `Body` uses) and skipping YOLOX when a bbox is supplied. `Body` stays as the no-bbox
   fallback so `POST /v1/pose` and all existing callers are untouched.
3. `backend/app/services/object_detection.py`: expose the already-computed person box, e.g.
   `infer_with_person(image) -> tuple[list[Detection], list[float] | None]` returning the
   largest-area class-0 box in pixel xyxy. `DETECTION_CLASS_MAP` and the existing `infer` are
   unchanged, so racket/ball output stays bit-identical.
4. Only the new Set Goal chunk endpoint uses the fused path this phase. `/v1/analyze` and
   `/v1/segment/video` keep current behavior — switching Assessment over is a follow-on with its
   own P5 revalidation, not a silent P7 side effect.
5. Mention `DETECTION_MODEL_DEVICE=mps` in dev-run docs as an optional speedup; do **not** hard-code
   it. `fused/cpu` clears the gate at 2.24x, so nothing depends on CoreML/MPS — which matters for
   P17's Jetson migration.

New unit coverage needed: `infer_with_person` returns pixel xyxy (unflipped, unnormalized), returns
`None` when no person clears threshold, and `RTMPoseModel.infer` with no bbox still routes through
`Body` unchanged.

## Remaining step 2 — amend `plan.md`'s existing groups

- **Group 2** (`plan.md:138-164`): make the chunk handler `def` (or wrap inference in
  `run_in_threadpool`) — as specified it is `async def` with synchronous CPU-bound inference in the
  body, which stalls the event loop for every concurrent request including the queued
  `is_final=true` chunk. Apply Blocker A's `confirmed_count` rule. Update
  `test_goal_session_endpoint.py`: a single detected segment whose peak is ≥1.5s from the buffer end
  **is** confirmed without `is_final` — the behavior most worth a direct test.
- **`phases.py`**: additive helper exposing accepted peak timestamps (see Blocker A).
- **Group 6** (`plan.md:466`): `chunkDuration: 2` instead of 4 — halves the 0–4s quantization term.
  Add a backlog guard in `handleChunk`: beyond a small bound of outstanding uploads, drop the oldest
  rather than queueing unboundedly, so latency degrades by losing a serve instead of drifting.
- **Group 8 / `validation.md`**: add a measured check — on the real-device run, record wall-clock
  seconds from each serve's contact to its spoken cue, with a stated bar (e.g. median ≤5s, max ≤8s).
  Today's `validation.md` only asks that cues are "spoken audibly between serves," which the
  as-planned design would satisfy while being one full serve behind.

## Resulting latency budget

| Term | Value |
|---|---|
| confirmation lag after peak | 1.5s |
| chunk quantization (2s chunks) | 0–2s |
| upload (2s of 720x1280 over LAN) | ~0.3s |
| backend inference (`fused/mps`, 2s chunk, stride 2 — measured) | ~0.6s |
| **total** | **~2.4–4.4s** |

Meets the few-seconds requirement at full stride-2 fidelity, with ~3x throughput headroom so it
does not degrade over a long session.
