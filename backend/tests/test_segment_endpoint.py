import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.engine.phases import segment_serves, slice_detections_by_segments
from app.models import SegmentResponse
from conftest import IDLE_WRIST_Y, PEAK_WRIST_Y, make_frame
from conftest import hump as _shared_hump
from conftest import rest_burst as _shared_rest_burst


@pytest.fixture
def transport():
    return ASGITransport(app=app)


# This endpoint POSTs frames as JSON, so every fixture helper here wraps conftest's shared
# Frame-returning geometry (see conftest.py for NECK_Y/PELVIS_Y/IDLE_WRIST_Y/PEAK_WRIST_Y, shared
# with test_segment_serves.py) with a .model_dump() conversion to dicts.
def _hump(peak_y: float, count: int, start_index: int, fps: float, **kwargs) -> list:
    return [f.model_dump() for f in _shared_hump(peak_y, count, start_index, fps, **kwargs)]


def _rest_burst(wrist_y: float, count: int, start_index: int, fps: float) -> list:
    return [f.model_dump() for f in _shared_rest_burst(wrist_y, count, start_index, fps)]


def _build_two_serve_sequence(fps: float = 30.0) -> list:
    hump1 = _hump(peak_y=PEAK_WRIST_Y, count=6, start_index=0, fps=fps)
    rest = _rest_burst(wrist_y=IDLE_WRIST_Y, count=60, start_index=6, fps=fps)
    hump2 = _hump(peak_y=PEAK_WRIST_Y, count=6, start_index=66, fps=fps)
    return hump1 + rest + hump2


@pytest.mark.asyncio
async def test_single_continuous_serve_returns_one_segment(transport):
    frames = _hump(peak_y=PEAK_WRIST_Y, count=10, start_index=0, fps=30.0)
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
