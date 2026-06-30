# Phase 4 — Coaching Rule Engine: Plan

Each task group is independently committable and testable before moving to the next.

---

## Task Group 1 — rules.json schema and initial rules

- Define the JSON schema for a rule entry: `id`, `phase`, `metric`, `threshold`, `comparison` (`gte`/`lte`), `severity`, `message`
- Write `backend/rules.json` with the 5 core rules from requirements
- No Python code yet; this is a pure config artifact

**Done when:** `rules.json` is valid JSON, passes a schema sanity check (`python -c "import json; json.load(open('rules.json'))"`), and contains all 5 rules.

---

## Task Group 2 — Angle computation utilities

- Create `backend/app/engine/angles.py`
- Implement `compute_angle(a, b, c) -> float`: angle in degrees at joint `b` given three `(x, y)` points
- Implement `keypoint_y(frame, joint_name, min_confidence) -> float | None`: returns the normalized y-coordinate of a joint in a frame, or `None` if confidence is below threshold
- Unit tests in `backend/tests/test_angles.py` with synthetic coordinate tuples

**Done when:** `pytest tests/test_angles.py` passes; known 90° and 180° inputs return correct values.

---

## Task Group 3 — Serve phase detection

- Create `backend/app/engine/phases.py`
- Define a `HANDEDNESS` constant that maps `"hitting"` and `"toss"` to left/right joint name prefixes (e.g., `{"hitting": "right", "toss": "left"}` for the right-handed MVP default)
- Implement `detect_phases(frames: list[Frame]) -> dict[ServePhase, Frame | None]` with a sequential search:
  1. **Trophy pose**: scan from frame 0; first frame satisfying all three conditions: toss wrist y > toss shoulder y, racket elbow angle in 80–110°, and both wrists y > hip y. Record its index.
  2. **Racket drop**: scan only frames after the trophy frame index; return the frame with the minimum hitting-wrist y.
  3. **Contact**: if racket drop was detected, scan only frames after the racket drop frame index; otherwise scan the full sequence. Return the frame with the maximum hitting-wrist y in that window.
- Return `None` for any phase that cannot be detected (insufficient confidence or no qualifying frame)
- Unit tests in `backend/tests/test_phases.py` with synthetic frame sequences

**Done when:** `pytest tests/test_phases.py` passes; a sequence with a low-wrist frame before the trophy frame does not misidentify it as racket drop; a sequence with a high-wrist peak before the racket drop does not misidentify it as contact; trophy, drop, and contact resolve to the expected frames.

---

## Task Group 4 — Rule evaluation engine

- Create `backend/app/engine/rules.py`
- Load `rules.json` once at module import time
- Implement `evaluate_rules(phase_frames: dict[ServePhase, Frame | None]) -> list[Cue]`
  - For each rule, look up the corresponding phase frame
  - Skip the rule if the frame is `None` or required keypoints are below confidence threshold
  - Compute the metric (y-position comparison or angle)
  - If the pass condition is violated, produce a `Cue`
- Rules are evaluated in `rules.json` order; no deduplication needed
- Unit tests in `backend/tests/test_rules.py` using synthetic phase frames

**Done when:** `pytest tests/test_rules.py` passes; a "perfect" frame set fires zero cues; a deliberately bad frame set fires the expected cues.

---

## Task Group 5 — Wire engine into POST /analyze

- Update `backend/app/routers/analyze.py` to call `detect_phases()` then `evaluate_rules()` instead of returning hardcoded cues
- If no cues are produced (clean serve), return a single informational cue: `"No major issues detected — good serve!"`
- Remove the hardcoded stub entirely
- Update the existing integration test in `backend/tests/test_analyze.py` to send a frame sequence that will produce at least one known cue

**Done when:** `pytest` (full suite) passes; the endpoint no longer contains any hardcoded strings; sending a frame sequence where the racket elbow angle is outside 80–110° returns a `trophy_racket_elbow_flexion` cue.
