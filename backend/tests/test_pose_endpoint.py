import io

import cv2
import numpy as np
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.models import Keypoint
from app.services.pose_model import get_pose_model


class StubPoseModel:
    def infer(self, image):
        return {"right_wrist": Keypoint(x=0.5, y=0.5, confidence=0.9)}


@pytest.fixture
def transport():
    app.dependency_overrides[get_pose_model] = lambda: StubPoseModel()
    yield ASGITransport(app=app)
    app.dependency_overrides.pop(get_pose_model, None)


def _synthetic_jpeg_bytes() -> bytes:
    ok, buf = cv2.imencode(".jpg", np.zeros((64, 64, 3), dtype=np.uint8))
    assert ok
    return buf.tobytes()


@pytest.mark.asyncio
async def test_valid_request_returns_200_with_correct_frames(transport):
    jpeg = _synthetic_jpeg_bytes()
    files = [
        ("frames", ("frame0.jpg", io.BytesIO(jpeg), "image/jpeg")),
        ("frames", ("frame1.jpg", io.BytesIO(jpeg), "image/jpeg")),
    ]
    data = {"timestamps": ["0.1", "0.5"]}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/pose", files=files, data=data)

    assert response.status_code == 200
    body = response.json()
    assert len(body["frames"]) == 2
    assert [f["timestamp"] for f in body["frames"]] == [0.1, 0.5]
    assert body["frames"][0]["keypoints"]["right_wrist"]["x"] == 0.5


@pytest.mark.asyncio
async def test_mismatched_lengths_returns_400(transport):
    jpeg = _synthetic_jpeg_bytes()
    files = [("frames", ("frame0.jpg", io.BytesIO(jpeg), "image/jpeg"))]
    data = {"timestamps": ["0.1", "0.5"]}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/pose", files=files, data=data)

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_corrupt_image_bytes_returns_400(transport):
    files = [("frames", ("frame0.jpg", io.BytesIO(b"not-a-jpeg"), "image/jpeg"))]
    data = {"timestamps": ["0.1"]}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/pose", files=files, data=data)

    assert response.status_code == 400
