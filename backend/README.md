# MyServeCoach Backend

FastAPI service that receives pose keypoints from the iOS app, runs rule-based serve analysis, and returns coaching cues.

## Run with Docker Compose

```bash
docker compose up
```

The API will be available at `http://localhost:8000`.

## Sample Request

```bash
curl -X POST http://localhost:8000/analyze \
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
