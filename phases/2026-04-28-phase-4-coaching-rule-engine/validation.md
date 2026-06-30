# Phase 4 — Coaching Rule Engine: Validation

Phase 4 is complete and mergeable when all of the following pass.

---

## 1. Automated tests

```bash
cd backend
pytest
```

All tests pass. Coverage includes:
- `test_angles.py` — known-geometry inputs return correct degree values; low-confidence keypoints return `None`
- `test_phases.py` — synthetic frame sequences resolve to correct trophy/drop/contact frames; a low hitting-wrist frame before the trophy pose is not misidentified as racket drop; a high hitting-wrist peak before the racket drop is not misidentified as contact; sequences with no qualifying frames return `None` for that phase
- `test_rules.py` — a "clean serve" fixture fires zero cues; fixtures with each rule violation fire exactly the expected cue
- `test_analyze.py` — integration test: POST with a frame sequence where the racket elbow angle is outside 80–110° returns a `trophy_racket_elbow_flexion` cue; POST with a clean sequence returns zero violation cues (or the informational fallback)

---

## 2. No hardcoded cues

```bash
grep -r "Raise your tossing arm" backend/app
grep -r "Extend fully through contact" backend/app
```

Both return empty (the Phase 3 stubs are gone).

---

## 3. Threshold tuning requires no code change

Edit a threshold value in `rules.json` (e.g., change `contact_arm_extension` threshold from 150 to 160), restart the server, re-run the affected test — the new threshold takes effect without touching any `.py` file.

---

## 4. Sequential phase detection is order-safe

Two regression cases confirmed by `test_phases.py`:

1. A hitting-wrist low point that occurs before the trophy pose is not misidentified as racket drop — only frames after the trophy frame are searched.
2. A hitting-wrist high point that occurs before the racket drop (e.g., the wrist peaks during the trophy/wind-up phase) is not misidentified as contact — when racket drop is detected, only frames after the racket drop frame are searched for contact.

---

## 5. Confidence filtering works

A test fixture where a required keypoint has `confidence: 0.1` (below the minimum) results in that rule being skipped, not fired. The other rules in the same request still evaluate normally.

---

## 6. Manual smoke test

```bash
cd backend
uvicorn app.main:app --reload
```

Send two requests with `curl` or the FastAPI `/docs` UI:

**Bad serve (racket elbow too straight at trophy — angle ~170°, outside 80–110°):**
```json
{
  "frames": [
    {
      "timestamp": 0.1,
      "keypoints": {
        "right_shoulder": {"x": 0.5,  "y": 0.65, "confidence": 0.95},
        "right_elbow":    {"x": 0.5,  "y": 0.50, "confidence": 0.95},
        "right_wrist":    {"x": 0.5,  "y": 0.35, "confidence": 0.95},
        "right_hip":      {"x": 0.5,  "y": 0.30, "confidence": 0.95},
        "left_shoulder":  {"x": 0.45, "y": 0.65, "confidence": 0.95},
        "left_wrist":     {"x": 0.45, "y": 0.80, "confidence": 0.95},
        "left_hip":       {"x": 0.45, "y": 0.30, "confidence": 0.95}
      }
    }
  ]
}
```

Expected: response contains a cue with `phase: "trophy_pose"`, `rule_id: "trophy_racket_elbow_flexion"`, and `severity: "major"`.

**Clean serve (all joints in correct positions):**  
Send a frame sequence where every joint satisfies every rule threshold.  
Expected: response contains no violation cues (or only the informational fallback cue).

---

## 7. Merge checklist

- [ ] `pytest` green with no skips
- [ ] `rules.json` committed at `backend/rules.json`
- [ ] `backend/app/engine/` directory with `angles.py`, `phases.py`, `rules.py`
- [ ] No hardcoded cue strings remaining in `app/routers/analyze.py`
- [ ] PR description includes the two smoke-test curl examples above
