import math
import pytest
from app.models import Frame, Keypoint
from app.engine.angles import compute_angle, joint_xy, keypoint_y, MIN_CONFIDENCE
from conftest import make_frame


# --- compute_angle ---

def test_90_degree_angle():
    # right angle at origin: a=(1,0), b=(0,0), c=(0,1)
    assert compute_angle((1, 0), (0, 0), (0, 1)) == pytest.approx(90.0, abs=1e-6)


def test_180_degree_angle():
    # straight line: a=(-1,0), b=(0,0), c=(1,0)
    assert compute_angle((-1, 0), (0, 0), (1, 0)) == pytest.approx(180.0, abs=1e-6)


def test_0_degree_angle():
    # a and c on the same ray from b
    assert compute_angle((1, 0), (0, 0), (2, 0)) == pytest.approx(0.0, abs=1e-6)


def test_45_degree_angle():
    assert compute_angle((1, 0), (0, 0), (1, 1)) == pytest.approx(45.0, abs=1e-6)


def test_degenerate_zero_vector_returns_none():
    # b == a collapses one vector to zero length → None
    assert compute_angle((0, 0), (0, 0), (1, 0)) is None


# --- keypoint_y ---

def test_keypoint_y_returns_value_when_confidence_sufficient():
    frame = make_frame({"right_wrist": {"x": 0.5, "y": 0.7, "confidence": 0.9}})
    assert keypoint_y(frame, "right_wrist") == pytest.approx(0.7)


def test_keypoint_y_returns_none_below_min_confidence():
    frame = make_frame({"right_wrist": {"x": 0.5, "y": 0.7, "confidence": 0.3}})
    assert keypoint_y(frame, "right_wrist") is None


def test_keypoint_y_returns_none_for_missing_joint():
    frame = make_frame({})
    assert keypoint_y(frame, "right_wrist") is None


def test_keypoint_y_respects_custom_min_confidence():
    frame = make_frame({"right_wrist": {"x": 0.5, "y": 0.7, "confidence": 0.35}})
    assert keypoint_y(frame, "right_wrist", min_confidence=0.3) == pytest.approx(0.7)
    assert keypoint_y(frame, "right_wrist", min_confidence=0.4) is None


def test_keypoint_y_at_confidence_boundary_included():
    # confidence exactly at threshold IS included — the check is strict less-than (<), not <=
    frame = make_frame({"right_wrist": {"x": 0.5, "y": 0.7, "confidence": MIN_CONFIDENCE}})
    # MIN_CONFIDENCE < MIN_CONFIDENCE is False, so the value IS returned
    assert keypoint_y(frame, "right_wrist", min_confidence=MIN_CONFIDENCE) == pytest.approx(0.7)
