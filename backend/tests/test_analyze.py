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


@pytest.fixture
def transport():
    return ASGITransport(app=app)


@pytest.mark.asyncio
async def test_valid_payload_returns_200(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/analyze", json={"frames": [VALID_FRAME]})
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert len(body.cues) > 0


@pytest.mark.asyncio
async def test_empty_frames_returns_422(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/analyze", json={"frames": []})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_missing_keypoints_returns_422(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/analyze", json={"frames": [{"timestamp": 0.0}]})
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
        response = await client.post("/analyze", json={"frames": [frame]})
    assert response.status_code == 200
