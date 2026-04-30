import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.models import AnalyzeResponse

VALID_FRAME = {
    "timestamp": 0.0,
    "keypoints": {
        "right_wrist": {"x": 0.5, "y": 0.3, "confidence": 0.9},
    },
}

# Trophy pose frame with a straight (180°) hitting arm — elbow outside 80–110°.
# Phase detection finds trophy (toss wrist above shoulder, wrists above hip).
# Rule trophy_racket_elbow_flexion then fires because 180° is outside [80, 110].
BAD_ELBOW_FRAME = {
    "timestamp": 0.0,
    "keypoints": {
        "right_shoulder": {"x": 0.3, "y": 0.5, "confidence": 0.9},
        "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.7, "y": 0.5, "confidence": 0.9},
        "right_hip":      {"x": 0.5, "y": 0.3, "confidence": 0.9},
        "left_wrist":     {"x": 0.3, "y": 0.8, "confidence": 0.9},
        "left_shoulder":  {"x": 0.4, "y": 0.65, "confidence": 0.9},
    },
}


@pytest.fixture
def transport():
    return ASGITransport(app=app)


@pytest.mark.asyncio
async def test_valid_payload_returns_200(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [VALID_FRAME]})
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert len(body.cues) > 0


@pytest.mark.asyncio
async def test_empty_frames_returns_422(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": []})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_missing_keypoints_returns_422(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [{"timestamp": 0.0}]})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_extra_keypoint_fields_ignored(transport):
    frame = {
        "timestamp": 0.0,
        "keypoints": {
            "right_wrist": {"x": 0.5, "y": 0.3, "confidence": 0.9, "unknown_field": "ignored"},
        },
    }
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [frame]})
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_no_detected_phases_returns_clean_serve_cue(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [VALID_FRAME]})
    body = AnalyzeResponse.model_validate(response.json())
    assert len(body.cues) == 1
    assert "good serve" in body.cues[0].message.lower()


@pytest.mark.asyncio
async def test_bad_elbow_angle_returns_trophy_racket_elbow_flexion_cue(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [BAD_ELBOW_FRAME]})
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert len(body.cues) == 1
    assert body.cues[0].phase == "trophy_pose"
    assert body.cues[0].severity == "major"
    assert "racket arm" in body.cues[0].message
