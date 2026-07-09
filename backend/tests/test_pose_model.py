import numpy as np
import pytest

from app.services.pose_model import COCO17_KEYPOINT_NAMES, map_coco17_to_backend_schema, select_primary_person

WIDTH = 100
HEIGHT = 200

_DIRECT_MAPPED_JOINTS = [
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
]


def _make_coco17_arrays():
    keypoints = np.array([[i * 10.0, i * 20.0] for i in range(17)])
    scores = np.array([round(0.5 + i * 0.01, 3) for i in range(17)])
    return keypoints, scores


def test_direct_mapped_joints_present_with_correct_values():
    keypoints, scores = _make_coco17_arrays()
    result = map_coco17_to_backend_schema(keypoints, scores, WIDTH, HEIGHT)

    for name in _DIRECT_MAPPED_JOINTS:
        idx = COCO17_KEYPOINT_NAMES.index(name)
        kp = result[name]
        assert kp.x == pytest.approx(keypoints[idx][0] / WIDTH)
        assert kp.y == pytest.approx(1.0 - keypoints[idx][1] / HEIGHT)
        assert kp.confidence == pytest.approx(scores[idx])


def test_y_axis_flipped_to_match_vision_convention():
    # A point at the top of the image in OpenCV pixel space (small y) must map to
    # a y close to 1.0 in the Vision-derived convention (origin bottom-left, y-up)
    # that phases.py/angles.py were built against — not close to 0.
    keypoints = np.zeros((17, 2))
    keypoints[COCO17_KEYPOINT_NAMES.index("right_wrist")] = [50.0, 0.0]  # top of frame
    keypoints[COCO17_KEYPOINT_NAMES.index("left_wrist")] = [50.0, HEIGHT]  # bottom of frame
    scores = np.ones(17)

    result = map_coco17_to_backend_schema(keypoints, scores, WIDTH, HEIGHT)

    assert result["right_wrist"].y == pytest.approx(1.0)
    assert result["left_wrist"].y == pytest.approx(0.0)


def test_neck_derived_as_shoulder_midpoint():
    keypoints, scores = _make_coco17_arrays()
    result = map_coco17_to_backend_schema(keypoints, scores, WIDTH, HEIGHT)

    left = result["left_shoulder"]
    right = result["right_shoulder"]
    neck = result["neck"]
    assert neck.x == pytest.approx((left.x + right.x) / 2)
    assert neck.y == pytest.approx((left.y + right.y) / 2)
    assert neck.confidence == pytest.approx(min(left.confidence, right.confidence))


def test_pelvis_derived_as_hip_midpoint():
    keypoints, scores = _make_coco17_arrays()
    result = map_coco17_to_backend_schema(keypoints, scores, WIDTH, HEIGHT)

    left = result["left_hip"]
    right = result["right_hip"]
    pelvis = result["pelvis"]
    assert pelvis.x == pytest.approx((left.x + right.x) / 2)
    assert pelvis.y == pytest.approx((left.y + right.y) / 2)
    assert pelvis.confidence == pytest.approx(min(left.confidence, right.confidence))


def test_eyes_and_ears_dropped_but_nose_retained():
    keypoints, scores = _make_coco17_arrays()
    result = map_coco17_to_backend_schema(keypoints, scores, WIDTH, HEIGHT)

    for name in ["left_eye", "right_eye", "left_ear", "right_ear"]:
        assert name not in result

    idx = COCO17_KEYPOINT_NAMES.index("nose")
    nose = result["nose"]
    assert nose.x == pytest.approx(keypoints[idx][0] / WIDTH)
    assert nose.y == pytest.approx(1.0 - keypoints[idx][1] / HEIGHT)
    assert nose.confidence == pytest.approx(scores[idx])


def test_all_zero_confidence_still_produces_well_formed_output():
    keypoints, _ = _make_coco17_arrays()
    scores = np.zeros(17)
    result = map_coco17_to_backend_schema(keypoints, scores, WIDTH, HEIGHT)

    assert result["right_wrist"].confidence == 0.0
    assert result["neck"].confidence == 0.0
    assert result["pelvis"].confidence == 0.0


# --- Primary-person selection (multi-person crowd scenes) ---

def _person(spread: float, confidence: float, n_keypoints: int = 17) -> tuple[np.ndarray, np.ndarray]:
    """A synthetic person's (keypoints, scores) with all keypoints confidently spread
    over an area of side length `spread` pixels, centered arbitrarily."""
    keypoints = np.array([[i * (spread / n_keypoints), i * (spread / n_keypoints)] for i in range(n_keypoints)])
    scores = np.full(n_keypoints, confidence)
    return keypoints, scores


def test_select_primary_person_picks_largest_bbox_area():
    # A small, tight crowd-member cluster at index 0; a much larger foreground-player spread at
    # index 1 — the largest-area person must win even though it isn't index 0.
    crowd_kp, crowd_sc = _person(spread=20.0, confidence=0.9)
    player_kp, player_sc = _person(spread=400.0, confidence=0.7)
    keypoints = np.array([crowd_kp, player_kp])
    scores = np.array([crowd_sc, player_sc])

    assert select_primary_person(keypoints, scores) == 1


def test_select_primary_person_ignores_low_confidence_keypoints_when_computing_area():
    # Index 0: a tiny confident cluster plus a handful of far-flung low-confidence noise
    # keypoints. If the noise were wrongly counted, index 0's apparent bbox (spanning 0..900)
    # would dwarf index 1's — the noise must be excluded so index 1 (modest but fully
    # confident, and genuinely larger once noise is correctly ignored) wins instead.
    tight_kp = np.array([[0.0, 0.0]] * 12 + [[900.0, 900.0]] * 5)
    tight_sc = np.array([0.9] * 12 + [0.1] * 5)  # noise points below MIN_CONFIDENCE (0.4)
    modest_kp, modest_sc = _person(spread=50.0, confidence=0.9)

    keypoints = np.array([tight_kp, modest_kp])
    scores = np.array([tight_sc, modest_sc])

    assert select_primary_person(keypoints, scores) == 1


def test_select_primary_person_defaults_to_first_when_no_confident_keypoints():
    low_kp, low_sc = _person(spread=500.0, confidence=0.1)  # all below MIN_CONFIDENCE
    other_low_kp, other_low_sc = _person(spread=10.0, confidence=0.2)
    keypoints = np.array([low_kp, other_low_kp])
    scores = np.array([low_sc, other_low_sc])

    assert select_primary_person(keypoints, scores) == 0


def test_select_primary_person_single_person_returns_zero():
    kp, sc = _person(spread=100.0, confidence=0.9)
    keypoints = np.array([kp])
    scores = np.array([sc])

    assert select_primary_person(keypoints, scores) == 0
