import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.engine.phases import segment_serves, slice_detections_by_segments
from app.models import SegmentResponse
from conftest import make_frame


@pytest.fixture
def transport():
    return ASGITransport(app=app)


# Fixed body-relative geometry: a constant neck/pelvis pair sets a constant floor (see
# _hitting_wrist_floor_score in app.engine.phases), and only the hitting wrist's height varies.
NECK_Y = 0.7
PELVIS_Y = 0.4
IDLE_WRIST_Y = 0.5  # well below the floor — resting arm height, never a peak candidate
PEAK_WRIST_Y = 0.95  # well above the floor — a genuine serve's contact-height wrist


def _kp(y: float, x: float = 0.5, confidence: float = 0.9) -> dict:
    return {"x": x, "y": y, "confidence": confidence}


def _positioned_frame(wrist_y: float, timestamp: float) -> dict:
    frame = make_frame(
        {"neck": _kp(NECK_Y), "pelvis": _kp(PELVIS_Y), "right_wrist": _kp(wrist_y)}, timestamp
    )
    return frame.model_dump()


def _hump(peak_y: float, count: int, start_index: int, fps: float, base_y: float = IDLE_WRIST_Y) -> list:
    """`count` frames rising linearly to `peak_y` at the midpoint, then falling back to `base_y`."""
    frames = []
    for i in range(count):
        progress = i / (count - 1) if count > 1 else 1.0
        triangle = 1 - abs(2 * progress - 1)  # 0 -> 1 -> 0
        wrist_y = base_y + (peak_y - base_y) * triangle
        frames.append(_positioned_frame(wrist_y, (start_index + i) / fps))
    return frames


def _rest_burst(wrist_y: float, count: int, start_index: int, fps: float) -> list:
    return [_positioned_frame(wrist_y, (start_index + i) / fps) for i in range(count)]


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
