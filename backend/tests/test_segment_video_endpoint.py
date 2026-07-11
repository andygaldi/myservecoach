from pathlib import Path

import cv2
import numpy as np
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.models import BoundingBox, Detection, Keypoint, SegmentResponse
from app.services.object_detection import get_object_detection_model
from app.services.pose_model import get_pose_model


def _make_video(path: Path, num_frames: int = 60, fps: float = 30.0) -> None:
    """Write a minimal grayscale MP4 for testing — mirrors test_pose_benchmark.py's helper."""
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, (64, 64))
    for i in range(num_frames):
        frame = np.full((64, 64, 3), i * 4 % 256, dtype=np.uint8)
        writer.write(frame)
    writer.release()


class StubPoseModel:
    def infer(self, image):
        return {"right_wrist": Keypoint(x=0.5, y=0.5, confidence=0.9)}


class StubDetectionModel:
    def infer(self, image):
        return [
            Detection(
                label="racket",
                confidence=0.9,
                bbox=BoundingBox(x_min=0.1, y_min=0.1, x_max=0.3, y_max=0.3),
            )
        ]


@pytest.fixture
def transport():
    app.dependency_overrides[get_pose_model] = lambda: StubPoseModel()
    app.dependency_overrides[get_object_detection_model] = lambda: StubDetectionModel()
    yield ASGITransport(app=app)
    app.dependency_overrides.pop(get_pose_model, None)
    app.dependency_overrides.pop(get_object_detection_model, None)


@pytest.mark.asyncio
async def test_video_returns_segmentresponse_with_expected_frame_count(transport, tmp_path):
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=60, fps=30.0)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/segment/video?stride=2",
            content=video_path.read_bytes(),
            headers={"Content-Type": "video/quicktime"},
        )

    assert response.status_code == 200
    body = SegmentResponse.model_validate(response.json())
    total_frames = sum(len(seg.frames) for seg in body.segments)
    assert total_frames == 30  # 60 frames at stride 2


@pytest.mark.asyncio
async def test_stride_param_respected(transport, tmp_path):
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=60, fps=30.0)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response_stride1 = await client.post(
            "/v1/segment/video?stride=1", content=video_path.read_bytes()
        )
        response_stride5 = await client.post(
            "/v1/segment/video?stride=5", content=video_path.read_bytes()
        )

    body1 = SegmentResponse.model_validate(response_stride1.json())
    body5 = SegmentResponse.model_validate(response_stride5.json())
    total1 = sum(len(seg.frames) for seg in body1.segments)
    total5 = sum(len(seg.frames) for seg in body5.segments)
    assert total1 == 60
    assert total5 == 12


@pytest.mark.asyncio
async def test_detections_sliced_parallel_to_frames(transport, tmp_path):
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=30, fps=30.0)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/segment/video?stride=2", content=video_path.read_bytes())

    body = SegmentResponse.model_validate(response.json())
    assert len(body.segments) >= 1
    for segment in body.segments:
        assert segment.detections is not None
        assert len(segment.detections) == len(segment.frames)


@pytest.mark.asyncio
async def test_invalid_video_bytes_returns_400(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/segment/video", content=b"not a video file")

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_empty_body_returns_400(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/segment/video", content=b"")

    assert response.status_code == 400
