import numpy as np
import pytest

from app.services.pose_model import COCO17_KEYPOINT_NAMES, map_coco17_to_backend_schema

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


def test_face_keypoints_dropped():
    keypoints, scores = _make_coco17_arrays()
    result = map_coco17_to_backend_schema(keypoints, scores, WIDTH, HEIGHT)

    for name in ["nose", "left_eye", "right_eye", "left_ear", "right_ear"]:
        assert name not in result


def test_all_zero_confidence_still_produces_well_formed_output():
    keypoints, _ = _make_coco17_arrays()
    scores = np.zeros(17)
    result = map_coco17_to_backend_schema(keypoints, scores, WIDTH, HEIGHT)

    assert result["right_wrist"].confidence == 0.0
    assert result["neck"].confidence == 0.0
    assert result["pelvis"].confidence == 0.0
