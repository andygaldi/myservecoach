# MyServeCoach Backend

FastAPI service that receives pose keypoints from the iOS app, runs rule-based serve analysis, and returns coaching cues.

## Run with Docker Compose

```bash
docker compose up
```

The API will be available at `http://localhost:8000`.

## Sample Request

```bash
curl -X POST http://localhost:8000/v1/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "frames": [
      {
        "timestamp": 0.033,
        "keypoints": {
          "right_wrist": { "x": 0.52, "y": 0.31, "confidence": 0.93 },
          "right_elbow": { "x": 0.48, "y": 0.45, "confidence": 0.91 },
          "right_shoulder": { "x": 0.44, "y": 0.55, "confidence": 0.95 }
        }
      }
    ]
  }'
```

Expected response:

```json
{
  "cues": [
    {
      "phase": "trophy_pose",
      "message": "Raise your tossing arm higher at trophy pose — elbow should be at shoulder height.",
      "severity": "major"
    },
    {
      "phase": "contact",
      "message": "Extend fully through contact — you're cutting the swing short slightly.",
      "severity": "minor"
    }
  ]
}
```

## Run Tests Locally

```bash
cd backend
python -m pytest tests/ -v
```

## Local Development

`POSE_MODEL_DEVICE` / `DETECTION_MODEL_DEVICE` select the ONNX Runtime device for pose/object
detection inference (`cpu` by default). On Apple Silicon, `DETECTION_MODEL_DEVICE=mps` is an
optional speedup for the object detector — not required: the Set Goal chunk endpoint's fused
pipeline (`fused/cpu`, see `phases/2026-08-28-p7-goal-library-set-goal-2d/latency-findings.md`)
already clears its live-feedback latency budget without it. Do not set `POSE_MODEL_DEVICE=mps`:
rtmlib's bundled YOLOX-m detector fails under CoreML (`Body`'s no-bbox fallback path only).
