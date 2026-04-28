# Phase 3 — Backend Scaffold: Validation

## Definition of Done

Phase 3 is complete when all checks below pass. No partial credit — each check is a gate.

---

## 1. Server Starts

```bash
docker compose up
```

- Exits with no errors on startup
- Logs show uvicorn listening on `0.0.0.0:8000`
- No import errors, no missing dependency warnings

---

## 2. Valid Request → 200 + Correct Schema

```bash
curl -s -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "frames": [
      {
        "timestamp": 0.033,
        "keypoints": {
          "right_wrist": {"x": 0.52, "y": 0.34, "confidence": 0.91},
          "right_elbow": {"x": 0.48, "y": 0.50, "confidence": 0.88}
        }
      }
    ]
  }' | python3 -m json.tool
```

Expected: HTTP 200, response body is valid JSON matching:
```json
{
  "cues": [
    {
      "phase": "<one of: trophy_pose | racket_drop | contact>",
      "message": "<non-empty string>",
      "severity": "<major | minor>"
    }
  ]
}
```
At least one cue must be present. No extra top-level keys.

---

## 3. Invalid Request → 422

```bash
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d '{"frames": []}'
```
Expected: `422`

```bash
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d '{"frames": [{"timestamp": 0.1}]}'
```
Expected: `422` (missing `keypoints`)

---

## 4. Automated Tests Pass

```bash
cd backend && pytest -v
```

- All tests in `tests/test_analyze.py` pass
- No warnings treated as errors that block the run
- Exit code 0

---

## 5. iOS Reachability (Manual)

Run the backend via Docker Compose on the Mac. From the iOS Simulator (or a real device on the same network), confirm a `URLSession` POST to `http://<mac-ip>:8000/analyze` returns a 200 with the structured cues payload.

This is the final gate — it proves the contract works end-to-end before Phase 4 adds real logic and Phase 5 wires up production networking.

---

## Merge Criteria

- All 5 checks above pass
- No `TODO` or `FIXME` comments left in `backend/` code
- `docker compose up` is the single documented way to run the server locally
- `POST /analyze` schema is unchanged from what's documented in `requirements.md`
