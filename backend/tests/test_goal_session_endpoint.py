from pathlib import Path

import cv2
import numpy as np
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.models import Keypoint
from app.services import goal_session_buffer
from app.services.object_detection import get_object_detection_model
from app.services.pose_model import get_pose_model
from conftest import IDLE_WRIST_Y, NECK_Y, PEAK_WRIST_Y, PELVIS_Y, kp

FPS = 30.0
GOAL_RULE_ID = "trophy_toss_arm_straight"


def _make_video(path: Path, num_frames: int) -> None:
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, FPS, (64, 64))
    for i in range(num_frames):
        writer.write(np.full((64, 64, 3), i * 4 % 256, dtype=np.uint8))
    writer.release()


class ScriptedPoseModel:
    """Returns a scripted per-call wrist height (with a constant neck/pelvis), so a test can
    place a segment's accepted peak at a chosen sample index deterministically. A fresh instance
    is created per request via the dependency override, matching the process's real per-request
    lifecycle."""

    def __init__(self, wrist_ys: list[float]):
        self._wrist_ys = wrist_ys
        self._i = 0

    def infer(self, image, person_bbox=None):
        wrist_y = self._wrist_ys[self._i] if self._i < len(self._wrist_ys) else IDLE_WRIST_Y
        self._i += 1
        return {
            "neck": Keypoint(**kp(NECK_Y)),
            "pelvis": Keypoint(**kp(PELVIS_Y)),
            "right_wrist": Keypoint(**kp(wrist_y)),
        }


class StubDetectionModel:
    def infer_with_person(self, image):
        return [], [0.0, 0.0, 10.0, 10.0]


def _wrist_ys_with_single_peak(count: int, peak_index: int) -> list[float]:
    ys = [IDLE_WRIST_Y] * count
    ys[peak_index] = PEAK_WRIST_Y
    return ys


def _override(wrist_ys: list[float]):
    app.dependency_overrides[get_pose_model] = lambda: ScriptedPoseModel(wrist_ys)
    app.dependency_overrides[get_object_detection_model] = lambda: StubDetectionModel()


@pytest.fixture(autouse=True)
def _reset_buffer():
    goal_session_buffer.clear_all()
    yield
    goal_session_buffer.clear_all()
    app.dependency_overrides.pop(get_pose_model, None)
    app.dependency_overrides.pop(get_object_detection_model, None)


@pytest.mark.asyncio
async def test_segment_confirmed_without_is_final_once_peak_clears_lag(tmp_path):
    # 30 samples spanning 2.9s (stride=3 @ 30fps), single accepted peak at sample 3 (t=0.3s) —
    # 2.6s behind the buffer's trailing edge, comfortably past CONFIRM_LAG_SECONDS (1.5s).
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=90)
    _override(_wrist_ys_with_single_peak(count=30, peak_index=3))

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            f"/v1/goal/session/chunk?session_id=s1&goal_rule_id={GOAL_RULE_ID}&stride=3",
            content=video_path.read_bytes(),
        )

    assert response.status_code == 200
    body = response.json()
    assert len(body["results"]) == 1
    assert body["results"][0]["segment_index"] == 0
    assert isinstance(body["results"][0]["goal_result"]["passed"], bool)


@pytest.mark.asyncio
async def test_segment_within_lag_window_stays_provisional(tmp_path):
    # Peak at sample 28 (t=2.8s) of 30, only 0.1s behind the trailing edge (t=2.9s) — inside
    # CONFIRM_LAG_SECONDS, so not yet safe to score.
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=90)
    _override(_wrist_ys_with_single_peak(count=30, peak_index=28))

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            f"/v1/goal/session/chunk?session_id=s2&goal_rule_id={GOAL_RULE_ID}&stride=3",
            content=video_path.read_bytes(),
        )

    assert response.status_code == 200
    assert response.json() == {"results": []}  # present and empty, not omitted


@pytest.mark.asyncio
async def test_is_final_confirms_all_remaining_segments_regardless_of_lag(tmp_path):
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=90)
    _override(_wrist_ys_with_single_peak(count=30, peak_index=28))

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            f"/v1/goal/session/chunk?session_id=s3&goal_rule_id={GOAL_RULE_ID}&stride=3&is_final=true",
            content=video_path.read_bytes(),
        )

    assert response.status_code == 200
    body = response.json()
    assert len(body["results"]) == 1
    assert body["results"][0]["segment_index"] == 0


@pytest.mark.asyncio
async def test_provisional_segment_confirmed_once_buffer_grows_past_lag_window(tmp_path):
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=90)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Chunk 1: peak at t=2.8s, buffer ends at t=2.9s -> not yet confirmed.
        _override(_wrist_ys_with_single_peak(count=30, peak_index=28))
        first = await client.post(
            f"/v1/goal/session/chunk?session_id=s4&goal_rule_id={GOAL_RULE_ID}&stride=3",
            content=video_path.read_bytes(),
        )
        assert first.json() == {"results": []}

        # Chunk 2: 20 idle samples continuing the buffer's clock (offset starts at 3.0s), pushing
        # the trailing edge to t=4.9s -> the first chunk's peak (t=2.8s) is now 2.1s old.
        idle_video_path = tmp_path / "idle.mp4"
        _make_video(idle_video_path, num_frames=60)
        _override([IDLE_WRIST_Y] * 20)
        second = await client.post(
            f"/v1/goal/session/chunk?session_id=s4&goal_rule_id={GOAL_RULE_ID}&stride=3",
            content=idle_video_path.read_bytes(),
        )

    assert second.status_code == 200
    body = second.json()
    assert len(body["results"]) == 1
    assert body["results"][0]["segment_index"] == 0


@pytest.mark.asyncio
async def test_final_chunk_evicts_buffer_so_next_chunk_starts_fresh(tmp_path):
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=90)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        _override(_wrist_ys_with_single_peak(count=30, peak_index=3))
        final_response = await client.post(
            f"/v1/goal/session/chunk?session_id=s5&goal_rule_id={GOAL_RULE_ID}&stride=3&is_final=true",
            content=video_path.read_bytes(),
        )
        assert final_response.json()["results"][0]["segment_index"] == 0

        # A follow-up chunk under the same session_id after eviction must start a fresh buffer:
        # if reported_count/offset had leaked, this segment would come back as index 1 (or be
        # skipped), not index 0 again.
        _override(_wrist_ys_with_single_peak(count=30, peak_index=3))
        followup = await client.post(
            f"/v1/goal/session/chunk?session_id=s5&goal_rule_id={GOAL_RULE_ID}&stride=3",
            content=video_path.read_bytes(),
        )

    assert followup.status_code == 200
    body = followup.json()
    assert len(body["results"]) == 1
    assert body["results"][0]["segment_index"] == 0


@pytest.mark.asyncio
async def test_unknown_goal_rule_id_returns_400_and_leaves_buffer_untouched(tmp_path):
    video_path = tmp_path / "clip.mp4"
    _make_video(video_path, num_frames=90)
    _override(_wrist_ys_with_single_peak(count=30, peak_index=3))

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        bad = await client.post(
            "/v1/goal/session/chunk?session_id=s6&goal_rule_id=not_a_real_rule&stride=3",
            content=video_path.read_bytes(),
        )
        assert bad.status_code == 400

        # If the failed call had appended anything, this otherwise-identical fresh-buffer
        # scenario would no longer resolve to segment_index 0 confirmed on its own.
        _override(_wrist_ys_with_single_peak(count=30, peak_index=3))
        valid = await client.post(
            f"/v1/goal/session/chunk?session_id=s6&goal_rule_id={GOAL_RULE_ID}&stride=3",
            content=video_path.read_bytes(),
        )

    assert valid.status_code == 200
    body = valid.json()
    assert len(body["results"]) == 1
    assert body["results"][0]["segment_index"] == 0
