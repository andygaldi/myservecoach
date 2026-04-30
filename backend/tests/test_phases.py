import pytest
from app.models import Frame, Keypoint, ServePhase
from app.engine.phases import detect_phases


def make_frame(timestamp: float, keypoints: dict) -> Frame:
    return Frame(timestamp=timestamp, keypoints={k: Keypoint(**v) for k, v in keypoints.items()})


# Canonical trophy-pose keypoints for a right-handed player:
#   right_shoulder=(0.6,0.7), right_elbow=(0.6,0.5), right_wrist=(0.8,0.5) → 90° at elbow (in 80–110°)
#   left_wrist y=0.8 > left_shoulder y=0.65  → toss wrist above shoulder
#   right_hip y=0.3;  left_wrist y=0.8 > 0.3, right_wrist y=0.5 > 0.3  → both wrists above hip
TROPHY_KPS = {
    "right_shoulder": {"x": 0.6, "y": 0.7, "confidence": 0.9},
    "right_elbow":    {"x": 0.6, "y": 0.5, "confidence": 0.9},
    "right_wrist":    {"x": 0.8, "y": 0.5, "confidence": 0.9},
    "right_hip":      {"x": 0.5, "y": 0.3, "confidence": 0.9},
    "left_wrist":     {"x": 0.3, "y": 0.8, "confidence": 0.9},
    "left_shoulder":  {"x": 0.4, "y": 0.65, "confidence": 0.9},
}


# --- Trophy pose detection ---

def test_single_trophy_frame_detected():
    f = make_frame(0.0, TROPHY_KPS)
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is f


def test_trophy_is_first_qualifying_frame():
    f0 = make_frame(0.0, TROPHY_KPS)
    f1 = make_frame(1.0, TROPHY_KPS)
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is f0


def test_non_trophy_frame_before_trophy_is_skipped():
    f0 = make_frame(0.0, {**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9}})  # toss wrist below shoulder
    f1 = make_frame(1.0, TROPHY_KPS)
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is f1


def test_trophy_elbow_angle_outside_range_rejected():
    # Horizontal straight arm → 180°, outside 80–110°
    f = make_frame(0.0, {
        **TROPHY_KPS,
        "right_shoulder": {"x": 0.3, "y": 0.5, "confidence": 0.9},
        "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.7, "y": 0.5, "confidence": 0.9},
    })
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is None


def test_trophy_wrists_not_above_hip_rejected():
    # right_wrist y=0.2 < right_hip y=0.3 → fails "both wrists above hip"
    f = make_frame(0.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.2, "confidence": 0.9}})
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is None


def test_low_confidence_keypoints_block_trophy():
    low_conf = {k: {**v, "confidence": 0.1} for k, v in TROPHY_KPS.items()}
    result = detect_phases([make_frame(0.0, low_conf)])
    assert result[ServePhase.trophy_pose] is None


# --- Racket drop detection ---

def test_low_wrist_before_trophy_is_not_racket_drop():
    # Frame 0 has the lowest wrist in the sequence but precedes trophy → must not be racket drop
    f0 = make_frame(0.0, {**TROPHY_KPS,
                          "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},   # fails trophy
                          "right_wrist": {"x": 0.8, "y": 0.02, "confidence": 0.9}})  # lowest wrist
    f1 = make_frame(1.0, TROPHY_KPS)  # trophy; right_wrist y=0.5
    f2 = make_frame(2.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.1, "confidence": 0.9}})  # drop (post-trophy minimum)
    f3 = make_frame(3.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.9, "confidence": 0.9}})  # contact

    result = detect_phases([f0, f1, f2, f3])
    assert result[ServePhase.racket_drop] is f2  # not f0


def test_no_trophy_means_no_racket_drop():
    f0 = make_frame(0.0, {**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9}})
    f1 = make_frame(1.0, {**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9}})
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is None
    assert result[ServePhase.racket_drop] is None


def test_no_frames_after_trophy_gives_no_racket_drop():
    f0 = make_frame(0.0, TROPHY_KPS)
    result = detect_phases([f0])
    assert result[ServePhase.racket_drop] is None


# --- Contact detection ---

def test_high_wrist_before_racket_drop_is_not_contact():
    # Frame 2 has a high wrist but precedes the racket drop → must not be contact
    f0 = make_frame(0.0, {**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9}})
    f1 = make_frame(1.0, TROPHY_KPS)  # trophy
    f2 = make_frame(2.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.85, "confidence": 0.9}})  # high wrist pre-drop
    f3 = make_frame(3.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.05, "confidence": 0.9}})  # racket drop
    f4 = make_frame(4.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}})  # contact

    result = detect_phases([f0, f1, f2, f3, f4])
    assert result[ServePhase.racket_drop] is f3
    assert result[ServePhase.contact] is f4  # not f2


def test_no_racket_drop_contact_searches_full_sequence():
    # No trophy → no racket drop → contact falls back to full-sequence search
    f0 = make_frame(0.0, {**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                          "right_wrist": {"x": 0.8, "y": 0.6, "confidence": 0.9}})
    f1 = make_frame(1.0, {**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9},
                          "right_wrist": {"x": 0.8, "y": 0.9, "confidence": 0.9}})  # highest wrist

    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is None
    assert result[ServePhase.racket_drop] is None
    assert result[ServePhase.contact] is f1


def test_no_frames_after_racket_drop_gives_no_contact():
    f0 = make_frame(0.0, TROPHY_KPS)  # trophy
    f1 = make_frame(1.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.05, "confidence": 0.9}})  # drop (last frame)
    result = detect_phases([f0, f1])
    assert result[ServePhase.racket_drop] is f1
    assert result[ServePhase.contact] is None


# --- Full sequence integration ---

def test_full_sequence_resolves_all_three_phases():
    f0 = make_frame(0.0, {**TROPHY_KPS, "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9}})  # pre-serve
    f1 = make_frame(1.0, TROPHY_KPS)                                                                # trophy
    f2 = make_frame(2.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.05, "confidence": 0.9}}) # racket drop
    f3 = make_frame(3.0, {**TROPHY_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}) # contact

    result = detect_phases([f0, f1, f2, f3])
    assert result[ServePhase.trophy_pose] is f1
    assert result[ServePhase.racket_drop] is f2
    assert result[ServePhase.contact] is f3
