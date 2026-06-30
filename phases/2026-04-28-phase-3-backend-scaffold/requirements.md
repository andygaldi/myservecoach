# Phase 3 — Backend Scaffold: Requirements

## Goal

Stand up a FastAPI project at `backend/` that proves the iOS ↔ backend contract before any real coaching logic is written. The endpoint accepts a single serve's keypoint JSON and returns a hardcoded list of structured coaching cues.

## Scope

**In scope:**
- FastAPI project scaffold at `backend/` in the monorepo root
- `POST /analyze` endpoint: accepts keypoint JSON, returns hardcoded structured cues
- Pydantic request model that validates the incoming keypoint payload — fails fast with 422 if iOS sends malformed data
- Docker Compose for local development (`docker compose up` starts the server)
- pytest setup with at minimum one contract test (valid payload → 200, invalid → 422)

**Out of scope:**
- Real coaching logic, angle computation, or rule evaluation (Phase 4)
- `GET /health` endpoint (deferred — not needed to prove the contract)
- `goal_id` / `goal_result` support (Phase 10)
- Cloud deployment or environment-specific config beyond local dev

## Response Contract

Hardcoded response shape (locked in for Phases 4–12 to build on):

```json
{
  "cues": [
    {
      "phase": "trophy_pose",
      "message": "Bend your knees more at trophy pose",
      "severity": "major"
    },
    {
      "phase": "contact",
      "message": "Pronate through contact",
      "severity": "minor"
    }
  ]
}
```

`phase` values will be drawn from a fixed enum: `trophy_pose`, `racket_drop`, `contact`. `severity` values: `major`, `minor`.

## Request Contract

The iOS client POSTs one serve's worth of keypoint data — a list of per-frame observations, each containing named joint positions with confidence scores. Exact field names mirror `VNHumanBodyPoseObservation` joint keys.

```json
{
  "frames": [
    {
      "timestamp": 0.033,
      "keypoints": {
        "right_wrist": {"x": 0.52, "y": 0.34, "confidence": 0.91},
        "right_elbow": {"x": 0.48, "y": 0.50, "confidence": 0.88}
      }
    }
  ]
}
```

Pydantic validates that `frames` is a non-empty list and each keypoint has `x`, `y`, and `confidence` as floats.

## Key Decisions

| Decision | Choice | Reason |
|---|---|---|
| Cue format | Structured objects (`phase`, `message`, `severity`) | Phase 4 rule engine maps directly to these fields; avoids a breaking schema change later |
| Request validation | Pydantic models | Fail fast on iOS contract mismatches; errors are visible in development before real data flows |
| Local dev | Docker Compose | Matches a realistic future cloud target; removes Python version/virtualenv setup friction |
| Hosting | Local only | MVP; cloud target TBD after Phase 5 iOS integration is validated |

## Context

This is the bridge phase between on-device work (Phases 1–2) and backend intelligence (Phase 4). Nothing here does real analysis — the value is locking the JSON contract so iOS networking (Phase 5) can be built against a stable target. The hardcoded cues are placeholders; the schema is not.
