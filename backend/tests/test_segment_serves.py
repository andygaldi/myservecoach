from conftest import make_frame
from app.engine.phases import _frame_velocity, segment_serves


def _kp(x: float, y: float = 0.5, confidence: float = 0.9) -> dict:
    return {"x": x, "y": y, "confidence": confidence}


def _positioned_frame(x: float, timestamp: float):
    return make_frame({"right_wrist": _kp(x)}, timestamp)


def _active_burst(start_x: float, x_step: float, count: int, start_index: int, fps: float) -> list:
    return [
        _positioned_frame(start_x + x_step * i, (start_index + i) / fps)
        for i in range(count)
    ]


def _rest_burst(x: float, count: int, start_index: int, fps: float) -> list:
    return [_positioned_frame(x, (start_index + i) / fps) for i in range(count)]


def test_empty_frames_returns_empty_list():
    assert segment_serves([]) == []


def test_single_serve_no_rest_gap_returns_one_segment():
    frames = _active_burst(start_x=0.0, x_step=0.1, count=10, start_index=0, fps=30.0)
    segments = segment_serves(frames)
    assert len(segments) == 1
    assert segments[0] == frames


def test_two_serves_separated_by_rest_gap_returns_two_segments():
    fps = 30.0
    active1 = _active_burst(start_x=0.0, x_step=0.1, count=6, start_index=0, fps=fps)  # x: 0.0..0.5
    rest = _rest_burst(x=0.5, count=14, start_index=6, fps=fps)  # indices 6..19, spans ~0.43s > MIN_REST_SECONDS
    active2 = _active_burst(start_x=0.6, x_step=0.1, count=6, start_index=20, fps=fps)
    frames = active1 + rest + active2

    segments = segment_serves(frames)

    assert len(segments) == 2
    last_of_first = frames.index(segments[0][-1])
    first_of_second = frames.index(segments[1][0])
    assert 6 <= last_of_first < first_of_second <= 19


def test_short_rest_gap_does_not_split():
    fps = 30.0
    active1 = _active_burst(start_x=0.0, x_step=0.1, count=6, start_index=0, fps=fps)  # ends x=0.5
    rest = _rest_burst(x=0.5, count=3, start_index=6, fps=fps)  # only spans 2/30s << 0.2s
    active2 = _active_burst(start_x=0.6, x_step=0.1, count=6, start_index=9, fps=fps)
    frames = active1 + rest + active2

    segments = segment_serves(frames)

    assert len(segments) == 1


def test_leading_idle_not_split_off():
    fps = 30.0
    idle = _rest_burst(x=0.2, count=14, start_index=0, fps=fps)  # spans ~0.43s > MIN_REST_SECONDS
    active = _active_burst(start_x=0.2, x_step=0.1, count=6, start_index=14, fps=fps)
    frames = idle + active

    segments = segment_serves(frames)

    assert len(segments) == 1
    assert segments[0] == frames


def test_trailing_idle_not_split_off():
    fps = 30.0
    active = _active_burst(start_x=0.0, x_step=0.1, count=6, start_index=0, fps=fps)  # ends x=0.5
    idle = _rest_burst(x=0.5, count=14, start_index=6, fps=fps)  # spans ~0.43s > MIN_REST_SECONDS
    frames = active + idle

    segments = segment_serves(frames)

    assert len(segments) == 1
    assert segments[0] == frames


def test_velocity_ignores_low_confidence_keypoints():
    a = make_frame(
        {
            "right_wrist": _kp(0.5, confidence=0.9),
            "left_wrist": _kp(0.1, confidence=0.1),
        },
        0.0,
    )
    b = make_frame(
        {
            "right_wrist": _kp(0.5, confidence=0.9),
            "left_wrist": _kp(0.9, confidence=0.1),
        },
        1 / 30.0,
    )
    assert _frame_velocity(a, b) == 0.0


def _build_two_serve_sequence(fps: float) -> list:
    """A two-burst-with-rest-gap sequence scaled to *fps*, holding real velocity constant.

    x_step is scaled by 30.0/fps so the physical velocity of the "active" bursts (units/second)
    is identical regardless of how many frames-per-second the sequence is sampled at.
    """
    x_step = 0.1 * 30.0 / fps
    active_count = round(6 * fps / 30.0)
    rest_count = max(3, round(0.5 * fps) + 1)  # spans ~0.5s of real time, safely > MIN_REST_SECONDS

    active1 = _active_burst(start_x=0.0, x_step=x_step, count=active_count, start_index=0, fps=fps)
    rest_x = active1[-1].keypoints["right_wrist"].x
    rest = _rest_burst(x=rest_x, count=rest_count, start_index=active_count, fps=fps)
    active2 = _active_burst(
        start_x=rest_x + x_step,
        x_step=x_step,
        count=active_count,
        start_index=active_count + rest_count,
        fps=fps,
    )
    return active1 + rest + active2


def test_segmentation_is_fps_invariant():
    segments_30fps = segment_serves(_build_two_serve_sequence(30.0))
    segments_58_4fps = segment_serves(_build_two_serve_sequence(58.4))

    assert len(segments_30fps) == 2
    assert len(segments_58_4fps) == 2
