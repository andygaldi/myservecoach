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


def test_all_idle_frames_returns_empty_list():
    # Velocity never crosses the threshold anywhere in the clip — pure idle/noise, no genuine
    # serve motion — should be rejected outright rather than falling through as one bogus segment.
    frames = _rest_burst(x=0.3, count=20, start_index=0, fps=30.0)
    assert segment_serves(frames) == []


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


def _serve_with_mid_routine_pause(fps: float = 30.0) -> list:
    """One serve with an elaborate-pre-serve-routine pattern embedded: a brief bounce (short
    active burst), a mid-routine pause long enough to clear MIN_REST_SECONDS on its own
    (0.5s — deliberately longer than any MIN_REST_SECONDS value the existing
    test_two_serves_separated_by_rest_gap_returns_two_segments fixture would tolerate raising
    to, so retuning that constant alone could never fix this), then the real swing (a long
    active burst), then a real trailing rest.

    Without MIN_ACTIVE_RUN_SECONDS, this used to false-split into 2 segments at the mid-routine
    pause, because the pause alone already exceeds MIN_REST_SECONDS.
    """
    bounce = _active_burst(start_x=0.0, x_step=0.1, count=3, start_index=0, fps=fps)  # ~0.067s active
    pause = _rest_burst(x=0.3, count=16, start_index=3, fps=fps)  # spans 0.5s > MIN_REST_SECONDS
    swing = _active_burst(start_x=0.3, x_step=0.1, count=12, start_index=19, fps=fps)  # ~0.37s active
    trailing_rest = _rest_burst(x=swing[-1].keypoints["right_wrist"].x, count=16, start_index=31, fps=fps)
    return bounce + pause + swing + trailing_rest


def test_mid_routine_pause_does_not_false_split():
    frames = _serve_with_mid_routine_pause()

    segments = segment_serves(frames)

    assert len(segments) == 1
    assert segments[0] == frames


def test_mid_routine_pause_on_second_serve_does_not_false_split():
    # Regression test: an active-run-duration measurement that (incorrectly) started counting
    # from the previous boundary's rest-gap *midpoint*, rather than the true start of the new
    # active run, would silently credit part of serve1's own trailing rest as "active" time
    # toward serve2's embedded mid-routine pause — letting the false-split bug reappear from the
    # second serve onward even though test_mid_routine_pause_does_not_false_split (serve 1 only)
    # passes. Reproduces the bug directly by placing the same bounce/pause/swing pattern on serve
    # 2 of a two-serve clip.
    fps = 30.0
    serve1 = _active_burst(start_x=0.0, x_step=0.1, count=12, start_index=0, fps=fps)  # ~0.37s active
    real_rest = _rest_burst(
        x=serve1[-1].keypoints["right_wrist"].x, count=31, start_index=len(serve1), fps=fps
    )  # ~1.0s real between-serve rest
    serve2_start = len(serve1) + len(real_rest)
    bounce = _active_burst(start_x=0.0, x_step=0.1, count=3, start_index=serve2_start, fps=fps)
    pause = _rest_burst(x=0.3, count=16, start_index=serve2_start + 3, fps=fps)  # 0.5s pause
    swing = _active_burst(start_x=0.3, x_step=0.1, count=12, start_index=serve2_start + 19, fps=fps)
    frames = serve1 + real_rest + bounce + pause + swing

    segments = segment_serves(frames)

    assert len(segments) == 2


def test_mid_routine_pause_still_allows_correct_split_before_next_serve():
    fps = 30.0
    serve1 = _serve_with_mid_routine_pause(fps=fps)
    # A real between-serve rest (~1.0s) after serve1's real swing, then a second serve.
    real_rest = _rest_burst(
        x=serve1[-1].keypoints["right_wrist"].x, count=31, start_index=len(serve1), fps=fps
    )
    serve2 = _active_burst(
        start_x=0.0, x_step=0.1, count=10, start_index=len(serve1) + len(real_rest), fps=fps
    )
    frames = serve1 + real_rest + serve2

    segments = segment_serves(frames)

    assert len(segments) == 2
    # The boundary lands after serve1's real swing, not after the mid-routine bounce — serve1's
    # swing frames (indices 19..30 of serve1, i.e. the last 12 frames before real_rest) must all
    # be in the first segment.
    swing_end_index = 30
    assert frames.index(segments[0][-1]) >= swing_end_index
    assert frames.index(segments[1][0]) > swing_end_index
