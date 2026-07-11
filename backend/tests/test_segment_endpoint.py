import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.engine.phases import segment_serves, slice_detections_by_segments
from app.models import SegmentResponse
from conftest import make_frame


@pytest.fixture
def transport():
    return ASGITransport(app=app)


def _kp(x: float, y: float = 0.5, confidence: float = 0.9) -> dict:
    return {"x": x, "y": y, "confidence": confidence}


def _positioned_frame(x: float, timestamp: float) -> dict:
    frame = make_frame({"right_wrist": _kp(x)}, timestamp)
    return frame.model_dump()


def _active_burst(start_x: float, x_step: float, count: int, start_index: int, fps: float) -> list:
    return [
        _positioned_frame(start_x + x_step * i, (start_index + i) / fps)
        for i in range(count)
    ]


def _rest_burst(x: float, count: int, start_index: int, fps: float) -> list:
    return [_positioned_frame(x, (start_index + i) / fps) for i in range(count)]


def _build_two_serve_sequence(fps: float = 30.0) -> list:
    active1 = _active_burst(start_x=0.0, x_step=0.1, count=6, start_index=0, fps=fps)
    rest = _rest_burst(x=0.5, count=14, start_index=6, fps=fps)
    active2 = _active_burst(start_x=0.6, x_step=0.1, count=6, start_index=20, fps=fps)
    return active1 + rest + active2


@pytest.mark.asyncio
async def test_single_continuous_serve_returns_one_segment(transport):
    frames = _active_burst(start_x=0.0, x_step=0.1, count=10, start_index=0, fps=30.0)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/segment", json={"frames": frames})
    assert response.status_code == 200
    body = SegmentResponse.model_validate(response.json())
    assert len(body.segments) == 1
    assert len(body.segments[0].frames) == len(frames)
    assert body.segments[0].detections is None


@pytest.mark.asyncio
async def test_two_serve_sequence_returns_two_segments_with_sliced_detections(transport):
    frames = _build_two_serve_sequence()
    detections = [[] for _ in frames]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/segment", json={"frames": frames, "detections": detections}
        )
    assert response.status_code == 200
    body = SegmentResponse.model_validate(response.json())

    # Cross-check against the underlying engine functions directly rather than a hardcoded index.
    frame_objs = [make_frame(f["keypoints"], f["timestamp"]) for f in frames]
    expected_segments = segment_serves(frame_objs)
    expected_detections = slice_detections_by_segments([[] for _ in frame_objs], expected_segments)

    assert len(body.segments) == 2
    assert len(expected_segments) == 2
    for segment, expected_frames, expected_dets in zip(body.segments, expected_segments, expected_detections):
        assert len(segment.frames) == len(expected_frames)
        assert len(segment.detections) == len(expected_dets)


@pytest.mark.asyncio
async def test_empty_frames_returns_422(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/segment", json={"frames": []})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_detections_omitted_yields_none_per_segment(transport):
    frames = _build_two_serve_sequence()
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/segment", json={"frames": frames})
    assert response.status_code == 200
    body = SegmentResponse.model_validate(response.json())
    assert len(body.segments) == 2
    assert all(segment.detections is None for segment in body.segments)
