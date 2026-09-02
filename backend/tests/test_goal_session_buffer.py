import pytest

from app.models import Frame
from app.services import goal_session_buffer


@pytest.fixture(autouse=True)
def _reset_buffer():
    goal_session_buffer.clear_all()
    yield
    goal_session_buffer.clear_all()


def _triple(local_ts: float) -> tuple[float, Frame, list]:
    return (local_ts, Frame(timestamp=local_ts, keypoints={}), [])


def test_append_chunk_starts_at_zero_offset():
    sampled = [_triple(0.0), _triple(1 / 30.0)]
    buffer = goal_session_buffer.append_chunk("s1", stride=1, sampled=sampled)

    assert [f.timestamp for f in buffer.frames] == pytest.approx([0.0, 1 / 30.0])


def test_second_chunk_offsets_past_first_chunks_timestamps():
    first = [_triple(0.0), _triple(1 / 30.0)]  # 2 frames, stride=2 -> duration 2*(2/30)
    goal_session_buffer.append_chunk("s1", stride=2, sampled=first)

    second = [_triple(0.0), _triple(1 / 30.0)]
    buffer = goal_session_buffer.append_chunk("s1", stride=2, sampled=second)

    expected_offset = 2 * (2 / 30.0)
    assert buffer.frames[2].timestamp == pytest.approx(expected_offset)
    assert buffer.frames[3].timestamp == pytest.approx(expected_offset + 1 / 30.0)
    assert buffer.frames[2].timestamp > buffer.frames[1].timestamp


def test_append_chunk_accumulates_detections_parallel_to_frames():
    sampled = [_triple(0.0)]
    buffer = goal_session_buffer.append_chunk("s1", stride=1, sampled=sampled)

    assert len(buffer.detections) == len(buffer.frames) == 1


def test_evict_removes_present_session():
    goal_session_buffer.append_chunk("s1", stride=1, sampled=[_triple(0.0)])
    goal_session_buffer.evict("s1")

    # A fresh append after eviction starts a new buffer at offset 0.
    buffer = goal_session_buffer.append_chunk("s1", stride=1, sampled=[_triple(0.0)])
    assert len(buffer.frames) == 1
    assert buffer.frames[0].timestamp == pytest.approx(0.0)


def test_evict_missing_session_is_a_noop():
    goal_session_buffer.evict("does-not-exist")  # must not raise


def test_clear_all_empties_module_dict():
    goal_session_buffer.append_chunk("s1", stride=1, sampled=[_triple(0.0)])
    goal_session_buffer.clear_all()

    buffer = goal_session_buffer.append_chunk("s1", stride=1, sampled=[_triple(0.0)])
    assert len(buffer.frames) == 1
