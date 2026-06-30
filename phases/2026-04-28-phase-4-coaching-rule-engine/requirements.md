# Phase 4 — Coaching Rule Engine: Requirements

## Goal

Replace the hardcoded cue list in `POST /analyze` with a real rule-based coaching engine. The backend reads thresholds from `rules.json`, detects which frame in the keypoint sequence represents each serve phase, computes joint angles, evaluates rules, and returns only the cues whose conditions are violated.

## Scope

### In scope
- `rules.json` config file with threshold values (no code change needed to tune thresholds)
- Angle computation utilities (e.g., angle at a joint given three keypoints)
- Serve phase detection from a keypoint frame sequence using heuristic geometry:
  - **Trophy pose** — first frame where: toss wrist y > toss shoulder y, racket elbow flexion angle is in the 80–110° range, and both wrists are above hip level
  - **Racket drop** — frame with the minimum hitting-wrist y, searched only among frames that come after the detected trophy pose frame
  - **Contact point** — frame with the maximum hitting-wrist y; if racket drop was detected, search only frames after the racket drop frame; otherwise search the full sequence
- Rule evaluation engine: loads `rules.json`, evaluates each rule against the detected phase frame, returns `Cue` objects for violations
- `POST /analyze` wired to the real engine (hardcoded stubs removed)
- pytest unit tests with synthetic keypoint fixtures

### Out of scope
- `goal_id` filtering (Phase 10)
- LLM cue generation (Phase 13)
- iOS networking (Phase 5)
- Skeleton visualization

## Rules (3–5 core, Phase 4)

Each rule is one metric at one serve phase. A rule fires when the measured value is outside the acceptable range and produces a `Cue` with a phase, severity, and message template.

| Rule ID | Phase | Arm | Metric | Pass condition | Severity |
|---|---|---|---|---|---|
| `trophy_toss_arm_height` | trophy_pose | toss | Toss wrist y relative to toss shoulder y | Toss wrist above toss shoulder | major |
| `trophy_racket_elbow_flexion` | trophy_pose | hitting | Racket elbow angle (shoulder–elbow–wrist) | Angle in 80–110° | major |
| `racket_drop_depth` | racket_drop | hitting | Hitting wrist y relative to hitting hip y | Wrist below hip level | major |
| `contact_arm_extension` | contact | hitting | Hitting elbow angle (shoulder–elbow–wrist) | Angle ≥ 150° | major |
| `contact_wrist_height` | contact | hitting | Hitting wrist y relative to hitting shoulder y | Wrist above shoulder | minor |

**Handedness convention (MVP):** the engine assumes a right-handed player. Hitting arm = right (`right_wrist`, `right_elbow`, `right_shoulder`, `right_hip`). Toss arm = left (`left_wrist`, `left_shoulder`). Vision framework joint names match the Apple VNHumanBodyPoseObservation naming conventions.

Note: Vision framework uses a normalized coordinate system where y=0 is the **bottom** of the frame and y=1 is the **top**. "Higher" means a larger y value.

## Data contract

The request and response models are already established by Phase 3 (`app/models.py`). Phase 4 does not change the public API shape — `AnalyzeRequest` and `AnalyzeResponse` stay as-is. The `session_id` field remains optional and unused by the engine.

## Key decisions

- **Heuristic phase detection over index-based slicing**: Serves vary in tempo; geometric heuristics are more robust than assuming trophy pose always falls in the first third of frames.
- **Sequential phase search**: Trophy pose is detected first (earliest qualifying frame). Racket drop is then searched only in the sub-sequence after the trophy frame, so a low wrist position before the trophy (e.g., at address) cannot be misidentified as the racket drop. Contact is then searched only after the racket drop frame when racket drop was detected, preventing the upward swing into trophy or any pre-drop peak from being mistaken for the contact point.
- **Toss arm / hitting arm separation**: Rules reference specific arms explicitly. MVP assumes right-handed; the joint mapping is a single constant that can be swapped for left-handed support later.
- **rules.json as the single source of truth for thresholds**: Tuning thresholds for different player levels should require only a JSON edit, not a code change.
- **Synthetic fixtures for tests**: Deterministic, no external data files, easy to express "racket elbow angle outside 80–110° = rule fires".
- **Rule file loaded at startup**: `rules.json` is read once when the FastAPI app starts, not on every request.
- **Confidence filtering**: Keypoints below a minimum confidence (e.g., 0.4) are treated as missing; a rule that requires a missing keypoint is skipped (not fired as a violation).
