from conftest import IDLE_WRIST_Y, NECK_Y, PEAK_WRIST_Y, PELVIS_Y, make_frame
from conftest import hump as _hump
from conftest import kp as _kp
from conftest import rest_burst as _rest_burst
from app.engine.phases import (
    HITTING_WRIST_FLOOR_K,
    MIN_PEAK_SEPARATION_SECONDS,
    _find_serve_peaks,
    _frame_velocity,
    segment_serves,
    segment_serves_with_peaks,
)

# FLOOR_Y/BOUNCE_WRIST_Y are specific to this file's fixtures — see conftest.py for the
# NECK_Y/PELVIS_Y/IDLE_WRIST_Y/PEAK_WRIST_Y geometry shared with test_segment_endpoint.py.
FLOOR_Y = NECK_Y + HITTING_WRIST_FLOOR_K * abs(NECK_Y - PELVIS_Y)
BOUNCE_WRIST_Y = 0.6  # a shallow bump that still stays below FLOOR_Y — e.g. a ball bounce


def test_empty_frames_returns_empty_list():
    assert segment_serves([]) == []


def test_single_serve_no_rest_gap_returns_one_segment():
    frames = _hump(peak_y=PEAK_WRIST_Y, count=10, start_index=0, fps=30.0)
    segments = segment_serves(frames)
    assert len(segments) == 1
    assert segments[0] == frames


def test_all_idle_frames_returns_empty_list():
    # The hitting wrist never clears the body-relative floor anywhere in the clip — pure
    # idle/noise, no genuine serve motion — should be rejected outright rather than falling
    # through as one bogus segment.
    frames = _rest_burst(IDLE_WRIST_Y, count=20, start_index=0, fps=30.0)
    assert segment_serves(frames) == []


def test_two_serves_separated_by_rest_gap_returns_two_segments():
    fps = 30.0
    hump1 = _hump(peak_y=PEAK_WRIST_Y, count=10, start_index=0, fps=fps)  # apex ~ t=0.15s
    rest = _rest_burst(IDLE_WRIST_Y, count=55, start_index=10, fps=fps)  # indices 10..64, ~1.83s
    hump2 = _hump(peak_y=PEAK_WRIST_Y, count=10, start_index=65, fps=fps)  # apex ~ t=2.32s
    frames = hump1 + rest + hump2

    segments = segment_serves(frames)

    assert len(segments) == 2
    last_of_first = frames.index(segments[0][-1])
    first_of_second = frames.index(segments[1][0])
    assert 10 <= last_of_first < first_of_second <= 64


def test_short_rest_gap_does_not_split():
    # Two humps whose peaks fall closer together than MIN_PEAK_SEPARATION_SECONDS collapse to a
    # single accepted peak via greedy NMS — the peak-based analogue of "a short pause between
    # bursts of the same swing doesn't count as two serves".
    fps = 30.0
    hump1 = _hump(peak_y=PEAK_WRIST_Y, count=6, start_index=0, fps=fps)  # apex ~ t=0.083s
    gap = _rest_burst(IDLE_WRIST_Y, count=3, start_index=6, fps=fps)
    hump2 = _hump(peak_y=PEAK_WRIST_Y, count=6, start_index=9, fps=fps)  # apex ~ t=0.383s
    frames = hump1 + gap + hump2

    segments = segment_serves(frames)

    assert len(segments) == 1


def test_leading_idle_not_split_off():
    fps = 30.0
    idle = _rest_burst(IDLE_WRIST_Y, count=14, start_index=0, fps=fps)
    active = _hump(peak_y=PEAK_WRIST_Y, count=6, start_index=14, fps=fps)
    frames = idle + active

    segments = segment_serves(frames)

    assert len(segments) == 1
    assert segments[0] == frames


def test_trailing_idle_not_split_off():
    fps = 30.0
    active = _hump(peak_y=PEAK_WRIST_Y, count=6, start_index=0, fps=fps)
    idle = _rest_burst(IDLE_WRIST_Y, count=14, start_index=6, fps=fps)
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
    """A two-hump-with-rest-gap sequence scaled to *fps*, holding real timing constant.

    Frame counts are scaled by fps (rather than kept fixed) so both the hump width and the rest
    span cover the same real-time duration regardless of sampling rate — the peak separation
    this produces stays comfortably above MIN_PEAK_SEPARATION_SECONDS at any fps.
    """
    hump_count = max(4, round(0.2 * fps))
    rest_count = max(3, round(1.8 * fps))

    hump1 = _hump(peak_y=PEAK_WRIST_Y, count=hump_count, start_index=0, fps=fps)
    rest = _rest_burst(IDLE_WRIST_Y, count=rest_count, start_index=hump_count, fps=fps)
    hump2 = _hump(
        peak_y=PEAK_WRIST_Y, count=hump_count, start_index=hump_count + rest_count, fps=fps
    )
    return hump1 + rest + hump2


def test_segmentation_is_fps_invariant():
    segments_30fps = segment_serves(_build_two_serve_sequence(30.0))
    segments_58_4fps = segment_serves(_build_two_serve_sequence(58.4))

    assert len(segments_30fps) == 2
    assert len(segments_58_4fps) == 2


def _serve_with_mid_routine_pause(fps: float = 30.0) -> list:
    """One real serve with an elaborate pre-serve routine embedded: a brief ball bounce (a wrist
    bump that never clears the body-relative floor, so it's never a peak candidate at all — a
    physically accurate rejection, since a ball bounce doesn't raise the hitting wrist above head
    height), a mid-routine pause, the real swing (a hump crossing the floor), then a real
    trailing rest.
    """
    bounce = _hump(peak_y=BOUNCE_WRIST_Y, count=3, start_index=0, fps=fps)
    pause = _rest_burst(IDLE_WRIST_Y, count=16, start_index=3, fps=fps)  # spans 0.5s
    swing = _hump(peak_y=PEAK_WRIST_Y, count=12, start_index=19, fps=fps)  # spans ~0.37s
    trailing_rest = _rest_burst(IDLE_WRIST_Y, count=16, start_index=31, fps=fps)
    return bounce + pause + swing + trailing_rest


def test_mid_routine_pause_does_not_false_split():
    frames = _serve_with_mid_routine_pause()

    segments = segment_serves(frames)

    assert len(segments) == 1
    assert segments[0] == frames


def test_mid_routine_pause_on_second_serve_does_not_false_split():
    # Regression coverage: a bounce/pause/swing pattern embedded in the *second* serve of a
    # two-serve clip must still resolve to exactly two accepted peaks (serve1's hump, serve2's
    # swing hump) — the bounce never clears the floor, so it contributes nothing on its own.
    fps = 30.0
    serve1 = _hump(peak_y=PEAK_WRIST_Y, count=12, start_index=0, fps=fps)
    real_rest = _rest_burst(IDLE_WRIST_Y, count=31, start_index=len(serve1), fps=fps)  # ~1.0s
    serve2_start = len(serve1) + len(real_rest)
    bounce = _hump(peak_y=BOUNCE_WRIST_Y, count=3, start_index=serve2_start, fps=fps)
    pause = _rest_burst(IDLE_WRIST_Y, count=16, start_index=serve2_start + 3, fps=fps)
    swing = _hump(peak_y=PEAK_WRIST_Y, count=12, start_index=serve2_start + 19, fps=fps)
    frames = serve1 + real_rest + bounce + pause + swing

    segments = segment_serves(frames)

    assert len(segments) == 2


def test_mid_routine_pause_still_allows_correct_split_before_next_serve():
    fps = 30.0
    serve1 = _serve_with_mid_routine_pause(fps=fps)
    real_rest = _rest_burst(IDLE_WRIST_Y, count=31, start_index=len(serve1), fps=fps)  # ~1.0s
    serve2 = _hump(peak_y=PEAK_WRIST_Y, count=10, start_index=len(serve1) + len(real_rest), fps=fps)
    frames = serve1 + real_rest + serve2

    segments = segment_serves(frames)

    assert len(segments) == 2
    # The boundary lands after serve1's real swing (bounce(3) + pause(16) + swing(12) = indices
    # 0..30), not after the mid-routine bounce.
    swing_end_index = 30
    assert frames.index(segments[0][-1]) >= swing_end_index
    assert frames.index(segments[1][0]) > swing_end_index


# ---------------------------------------------------------------------------
# _find_serve_peaks / NMS primitives
# ---------------------------------------------------------------------------

def test_toss_and_catch_shape_yields_zero_peaks():
    # The toss arm rises but the hitting arm stays down throughout — the hitting-wrist-only
    # restriction rejects this outright, independent of segment_serves' boundary logic.
    fps = 30.0
    frames = [
        make_frame(
            {
                "neck": _kp(NECK_Y),
                "pelvis": _kp(PELVIS_Y),
                "right_wrist": _kp(IDLE_WRIST_Y),
                "left_wrist": _kp(0.5 + 0.4 * (1 - abs(2 * (i / 9) - 1))),
            },
            i / fps,
        )
        for i in range(10)
    ]
    assert _find_serve_peaks(frames, hitting="right", floor_k=HITTING_WRIST_FLOOR_K, min_peak_separation_seconds=MIN_PEAK_SEPARATION_SECONDS) == []


def test_two_close_peaks_collapse_to_one():
    fps = 30.0
    hump1 = _hump(peak_y=PEAK_WRIST_Y, count=6, start_index=0, fps=fps)
    hump2 = _hump(peak_y=PEAK_WRIST_Y, count=6, start_index=6, fps=fps)  # apex well under MIN_PEAK_SEPARATION_SECONDS away
    frames = hump1 + hump2

    peaks = _find_serve_peaks(
        frames, hitting="right", floor_k=HITTING_WRIST_FLOOR_K,
        min_peak_separation_seconds=MIN_PEAK_SEPARATION_SECONDS,
    )

    assert len(peaks) == 1


def test_missing_neck_or_pelvis_excludes_frame_without_crashing():
    fps = 30.0
    frames = [
        make_frame({"right_wrist": _kp(PEAK_WRIST_Y)}, 0 / fps),  # no neck/pelvis at all
        make_frame({"neck": _kp(NECK_Y), "right_wrist": _kp(PEAK_WRIST_Y)}, 1 / fps),  # no pelvis
        make_frame(
            {"neck": _kp(NECK_Y), "pelvis": _kp(PELVIS_Y), "right_wrist": _kp(PEAK_WRIST_Y)},
            2 / fps,
        ),
    ]

    peaks = _find_serve_peaks(
        frames, hitting="right", floor_k=HITTING_WRIST_FLOOR_K,
        min_peak_separation_seconds=MIN_PEAK_SEPARATION_SECONDS,
    )

    assert peaks == [2]


# ---------------------------------------------------------------------------
# segment_serves_with_peaks (P7 Set Goal chunk-confirmation support)
# ---------------------------------------------------------------------------

def test_with_peaks_empty_frames_returns_empty_list():
    assert segment_serves_with_peaks([]) == []


def test_with_peaks_matches_segment_serves_segments():
    frames = _build_two_serve_sequence(30.0)
    plain = segment_serves(frames)
    with_peaks = segment_serves_with_peaks(frames)

    assert [segment for segment, _ in with_peaks] == plain


def test_with_peaks_reports_each_segments_accepted_peak_timestamp():
    fps = 30.0
    hump1 = _hump(peak_y=PEAK_WRIST_Y, count=10, start_index=0, fps=fps)  # apex ~ t=0.15s
    rest = _rest_burst(IDLE_WRIST_Y, count=55, start_index=10, fps=fps)
    hump2 = _hump(peak_y=PEAK_WRIST_Y, count=10, start_index=65, fps=fps)  # apex ~ t=2.32s
    frames = hump1 + rest + hump2

    with_peaks = segment_serves_with_peaks(frames)

    assert len(with_peaks) == 2
    for segment, peak_ts in with_peaks:
        first_ts, last_ts = segment[0].timestamp, segment[-1].timestamp
        assert first_ts <= peak_ts <= last_ts


def test_with_peaks_single_serve_reports_peak_timestamp():
    frames = _hump(peak_y=PEAK_WRIST_Y, count=10, start_index=0, fps=30.0)
    with_peaks = segment_serves_with_peaks(frames)

    assert len(with_peaks) == 1
    segment, peak_ts = with_peaks[0]
    assert segment == frames
    assert segment[0].timestamp <= peak_ts <= segment[-1].timestamp
