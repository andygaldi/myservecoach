import pytest
from app.models import BoundingBox, Detection, Frame, Keypoint, ServePhase
from app.engine.phases import _min_max_normalize, detect_phases
from conftest import make_frame


def _ball_detection(center_y: float, confidence: float = 0.9) -> Detection:
    return Detection(
        label="ball",
        confidence=confidence,
        bbox=BoundingBox(x_min=0.4, x_max=0.42, y_min=center_y - 0.01, y_max=center_y + 0.01),
    )


def _racket_detection(center_y: float, confidence: float = 0.9) -> Detection:
    return Detection(
        label="racket",
        confidence=confidence,
        bbox=BoundingBox(x_min=0.4, x_max=0.42, y_min=center_y - 0.01, y_max=center_y + 0.01),
    )


# Canonical trophy-pose keypoints for a right-handed player:
#   left_wrist y=0.8 > left_shoulder y=0.65  → toss wrist above shoulder
#   right_wrist y=0.7 > right_hip y=0.3  → hitting wrist above hip
#   shoulder(0.6,0.5)→elbow(0.4,0.5)→wrist(0.4,0.7): vectors (0.2,0) ⊥ (0,0.2) → 90° ∈ [70°,110°]
TROPHY_KPS = {
    "right_shoulder": {"x": 0.6, "y": 0.5,  "confidence": 0.9},
    "right_elbow":    {"x": 0.4, "y": 0.5,  "confidence": 0.9},
    "right_wrist":    {"x": 0.4, "y": 0.7,  "confidence": 0.9},  # wrist above elbow (y 0.7 > 0.5)
    "right_hip":      {"x": 0.5, "y": 0.3,  "confidence": 0.9},
    "left_wrist":     {"x": 0.3, "y": 0.8,  "confidence": 0.9},
    "left_shoulder":  {"x": 0.4, "y": 0.65, "confidence": 0.9},
}


# --- Trophy pose detection ---

def test_single_trophy_frame_detected():
    f = make_frame(TROPHY_KPS, 0.0)
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is f


def test_trophy_is_first_qualifying_frame():
    f0 = make_frame(TROPHY_KPS, 0.0)
    f1 = make_frame(TROPHY_KPS, 1.0)
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is f0


def test_non_trophy_frame_before_trophy_is_skipped():
    f0 = make_frame({**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9}}, 0.0)  # toss wrist below shoulder
    f1 = make_frame(TROPHY_KPS, 1.0)
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is f1


def test_trophy_wrists_not_above_hip_rejected():
    # right_wrist y=0.2 < right_hip y=0.3 → fails "both wrists above hip"
    f = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.2, "confidence": 0.9}}, 0.0)
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is None


def test_toss_wrist_below_hip_rejected():
    # Toss wrist (left_wrist) is above toss shoulder but at or below hitting hip y.
    # left_wrist y=0.3 ≤ right_hip y=0.3 → fails the "both wrists above hip" guard.
    kps = {
        **TROPHY_KPS,
        "left_wrist": {"x": 0.3, "y": 0.3, "confidence": 0.9},  # at hip level, not above
        "right_hip":  {"x": 0.5, "y": 0.3, "confidence": 0.9},
    }
    f = make_frame(kps, 0.0)
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is None


def test_low_confidence_keypoints_block_trophy():
    low_conf = {k: {**v, "confidence": 0.1} for k, v in TROPHY_KPS.items()}
    result = detect_phases([make_frame(low_conf, 0.0)])
    assert result[ServePhase.trophy_pose] is None


# --- Racket drop detection ---

def test_low_wrist_before_trophy_is_not_racket_drop():
    # Frame 0 has the lowest wrist in the sequence but precedes trophy → must not be racket drop
    f0 = make_frame({**TROPHY_KPS,
                     "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},   # fails trophy
                     "right_wrist": {"x": 0.8, "y": 0.02, "confidence": 0.9}}, 0.0)  # lowest wrist
    f1 = make_frame(TROPHY_KPS, 1.0)  # trophy; right_wrist y=0.5
    f2 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9}}, 2.0)  # drop (post-trophy minimum, wrist left of hip)
    f3 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.9, "confidence": 0.9}}, 3.0)  # contact

    result = detect_phases([f0, f1, f2, f3])
    assert result[ServePhase.racket_drop] is f2  # not f0
    assert result[ServePhase.contact] is f3


def test_no_trophy_means_no_racket_drop():
    f0 = make_frame({**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9}}, 0.0)
    f1 = make_frame({**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9}}, 1.0)
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is None
    assert result[ServePhase.racket_drop] is None


def test_no_frames_after_trophy_gives_no_racket_drop():
    f0 = make_frame(TROPHY_KPS, 0.0)
    result = detect_phases([f0])
    assert result[ServePhase.racket_drop] is None


# --- Contact detection ---

def test_high_wrist_before_racket_drop_is_not_contact():
    # Frame 2 has a high wrist but precedes the racket drop → must not be contact.
    # Drop = f3: elbow dips on f2 then rises sharply on f3 (biggest rise).
    f0 = make_frame({**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9}}, 0.0)
    f1 = make_frame(TROPHY_KPS, 1.0)  # trophy; right_elbow y=0.5
    f2 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.85, "confidence": 0.9},
                     "right_elbow": {"x": 0.4, "y": 0.4, "confidence": 0.9}}, 2.0)  # elbow dips (delta -0.1)
    f3 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.3, "y": 0.05, "confidence": 0.9},
                     "right_elbow": {"x": 0.4, "y": 0.7, "confidence": 0.9}}, 3.0)  # racket drop: biggest elbow rise (+0.3)
    f4 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}, 4.0)  # contact

    result = detect_phases([f0, f1, f2, f3, f4])
    assert result[ServePhase.racket_drop] is f3
    assert result[ServePhase.contact] is f4  # not f2


def test_no_racket_drop_contact_searches_full_sequence():
    # No trophy → no racket drop → contact falls back to full-sequence search
    f0 = make_frame({**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                     "right_wrist": {"x": 0.8, "y": 0.6, "confidence": 0.9}}, 0.0)
    f1 = make_frame({**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9},
                     "right_wrist": {"x": 0.8, "y": 0.9, "confidence": 0.9}}, 1.0)  # highest wrist

    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is None
    assert result[ServePhase.racket_drop] is None
    assert result[ServePhase.contact] is f1


def test_no_frames_between_trophy_and_contact_gives_no_racket_drop():
    # trophy at 0, contact immediately at 1 — no frames between them to search for drop
    f0 = make_frame(TROPHY_KPS, 0.0)  # trophy
    f1 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 1.0)  # contact
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is f0
    assert result[ServePhase.contact] is f1
    assert result[ServePhase.racket_drop] is None


# --- Full sequence integration ---

def test_full_sequence_resolves_all_three_phases():
    f0 = make_frame({**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9}}, 0.0)  # pre-serve
    f1 = make_frame(TROPHY_KPS, 1.0)                                                                # trophy
    f2 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.3, "y": 0.05, "confidence": 0.9}}, 2.0) # racket drop (only candidate between trophy and contact)
    f3 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}, 3.0) # contact

    result = detect_phases([f0, f1, f2, f3])
    assert result[ServePhase.trophy_pose] is f1
    assert result[ServePhase.racket_drop] is f2
    assert result[ServePhase.contact] is f3


# --- New constraints from calibration against real footage ---

def test_trophy_rejected_when_hitting_wrist_below_elbow():
    # Elbow y=0.5, wrist y=0.4 → wrist below elbow → not a valid trophy pose
    f = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.4, "confidence": 0.9}}, 0.0)
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is None


def test_trophy_passes_without_elbow_data():
    # No elbow keypoint — constraint is skipped, frame qualifies on other criteria
    kps = {k: v for k, v in TROPHY_KPS.items() if k != "right_elbow"}
    f = make_frame(kps, 0.0)
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is f


def test_racket_drop_is_frame_with_largest_elbow_rise():
    # f1 elbow dips, f2 has the biggest rise → f2 is drop
    f0 = make_frame(TROPHY_KPS, 0.0)  # trophy; right_elbow y=0.5
    f1 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.4, "confidence": 0.9}}, 1.0)  # elbow dips (delta -0.1)
    f2 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.8, "confidence": 0.9}}, 2.0)  # biggest rise (+0.4) ← drop
    f3 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 3.0)  # contact

    result = detect_phases([f0, f1, f2, f3])
    assert result[ServePhase.racket_drop] is f2


def test_racket_drop_none_when_no_elbow_data_in_range():
    # Frame between trophy and contact has no elbow data → rise cannot be computed → drop is None
    kps_no_elbow = {k: v for k, v in TROPHY_KPS.items() if k != "right_elbow"}
    f0 = make_frame(TROPHY_KPS, 0.0)  # trophy
    f1 = make_frame({**kps_no_elbow, "right_wrist": {"x": 0.4, "y": 0.2, "confidence": 0.9}}, 1.0)  # no elbow
    f2 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 2.0)  # contact

    result = detect_phases([f0, f1, f2])
    assert result[ServePhase.racket_drop] is None


# --- Release detection ---

def test_release_ball_primary_when_ball_ever_detected():
    # Toss wrist never rises above the shoulder in f0 (fallback would pick f1), but a ball is
    # detected above the toss hand in f0 — the ball-primary path must take priority.
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)
    detections = [[_ball_detection(0.9)], []]

    result = detect_phases([f0, f1], detections)
    assert result[ServePhase.release] is f0


def test_release_falls_back_to_toss_wrist_when_ball_never_detected():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)
    detections = [[_racket_detection(0.9)], []]  # racket only, no ball anywhere

    result = detect_phases([f0, f1], detections)
    assert result[ServePhase.release] is f1


def test_release_falls_back_when_detections_is_none():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)

    result = detect_phases([f0, f1])
    assert result[ServePhase.release] is f1


def test_release_none_when_toss_never_rises_and_no_ball():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)

    result = detect_phases([f0])
    assert result[ServePhase.release] is None


# --- Start detection ---

def test_start_is_lowest_toss_wrist_before_release():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.3, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9},  # lowest toss wrist
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)
    f2 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},  # release
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 2.0)

    result = detect_phases([f0, f1, f2])
    assert result[ServePhase.release] is f2
    assert result[ServePhase.start] is f1


def test_start_falls_back_to_trophy_bound_when_no_release():
    # Ball is detected but never rises above the toss hand, so release stays None (ball-primary
    # path is active and never satisfied) even though a trophy pose still resolves from pose data.
    f0 = make_frame({**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9}}, 0.0)  # low toss wrist
    f1 = make_frame(TROPHY_KPS, 1.0)  # trophy
    detections = [[_ball_detection(0.05)], [_ball_detection(0.05)]]  # ball always low

    result = detect_phases([f0, f1], detections)
    assert result[ServePhase.release] is None
    assert result[ServePhase.trophy_pose] is f1
    assert result[ServePhase.start] is f0


def test_start_none_when_neither_release_nor_trophy_resolve():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)

    result = detect_phases([f0])
    assert result[ServePhase.release] is None
    assert result[ServePhase.trophy_pose] is None
    assert result[ServePhase.start] is None


# --- Finish detection ---

def test_finish_is_lowest_front_foot_after_contact():
    f0 = make_frame(TROPHY_KPS, 0.0)  # trophy
    f1 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}, 1.0)  # contact
    f2 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.5, "confidence": 0.9},
                      "left_ankle": {"x": 0.4, "y": 0.2, "confidence": 0.9}}, 2.0)  # lowest front foot
    f3 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.3, "confidence": 0.9},
                      "left_ankle": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 3.0)

    result = detect_phases([f0, f1, f2, f3])
    assert result[ServePhase.contact] is f1
    assert result[ServePhase.finish] is f2


def test_finish_falls_back_to_last_frame_when_no_ankle_data_after_contact():
    f0 = make_frame(TROPHY_KPS, 0.0)  # trophy
    f1 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}, 1.0)  # contact
    f2 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.5, "confidence": 0.9}}, 2.0)  # no ankle data

    result = detect_phases([f0, f1, f2])
    assert result[ServePhase.contact] is f1
    assert result[ServePhase.finish] is f2


def test_finish_falls_back_to_last_frame_when_no_contact():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.05, "confidence": 0.9}}, 1.0)

    result = detect_phases([f0, f1])
    assert result[ServePhase.contact] is None
    assert result[ServePhase.finish] is f1


# --- Combined-signal racket-drop detection ---

def test_racket_drop_combines_elbow_and_racket_signals():
    # frame1: strongest elbow rise (+0.4), no racket detection
    # frame2: weaker elbow rise (+0.1), best (lowest) racket signal
    # frame3: weakest elbow rise (+0.05), mid racket signal
    # Elbow-only ranking would pick frame1; the weighted combination must pick frame2 instead.
    f0 = make_frame(TROPHY_KPS, 0.0)  # trophy; right_elbow y=0.5
    f1 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.9, "confidence": 0.9}}, 1.0)
    f2 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 1.0, "confidence": 0.9}}, 2.0)
    f3 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 1.05, "confidence": 0.9}}, 3.0)
    f4 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.4, "y": 1.5, "confidence": 0.9}}, 4.0)  # contact

    detections = [
        [],
        [_racket_detection(0.9)],   # frame1: racket not dropped
        [_racket_detection(0.05)],  # frame2: racket most dropped
        [_racket_detection(0.5)],   # frame3: racket mid-dropped
        [],
    ]

    result = detect_phases([f0, f1, f2, f3, f4], detections)
    assert result[ServePhase.contact] is f4
    assert result[ServePhase.racket_drop] is f2


def test_racket_drop_all_existing_elbow_only_tests_pass_with_no_detections():
    # Re-exercises the fixture from test_racket_drop_is_frame_with_largest_elbow_rise with the
    # extended detect_phases signature (detections omitted) — confirms the combined-signal
    # rewrite reduces to the original elbow-only ranking when no detections are supplied.
    f0 = make_frame(TROPHY_KPS, 0.0)
    f1 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.4, "confidence": 0.9}}, 1.0)
    f2 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.8, "confidence": 0.9}}, 2.0)
    f3 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 3.0)

    result = detect_phases([f0, f1, f2, f3])
    assert result[ServePhase.racket_drop] is f2


def test_racket_drop_ignores_ball_detections():
    f0 = make_frame(TROPHY_KPS, 0.0)
    f1 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.4, "confidence": 0.9}}, 1.0)  # elbow dips
    f2 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.8, "confidence": 0.9}}, 2.0)  # biggest rise
    f3 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 3.0)  # contact

    detections = [
        [],
        [_ball_detection(0.02)],  # ball at its lowest point on frame1 — must not influence racket_drop
        [],
        [],
    ]

    result = detect_phases([f0, f1, f2, f3], detections)
    assert result[ServePhase.racket_drop] is f2  # unchanged from the elbow-only ranking


def test_racket_drop_detections_shorter_than_frames():
    f0 = make_frame(TROPHY_KPS, 0.0)
    f1 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.4, "confidence": 0.9}}, 1.0)
    f2 = make_frame({**TROPHY_KPS, "right_elbow": {"x": 0.4, "y": 0.8, "confidence": 0.9}}, 2.0)
    f3 = make_frame({**TROPHY_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 3.0)

    detections = [[]]  # shorter than frames — must not raise IndexError

    result = detect_phases([f0, f1, f2, f3], detections)
    assert result[ServePhase.racket_drop] is f2


def test_min_max_normalize_handles_equal_values():
    assert _min_max_normalize({1: 5.0, 2: 5.0, 3: 5.0}) == {1: 1.0, 2: 1.0, 3: 1.0}
    assert _min_max_normalize({7: 3.0}) == {7: 1.0}
    assert _min_max_normalize({}) == {}
