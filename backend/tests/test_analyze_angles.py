"""Tests for analyze_angles.py using synthetic fixtures — no real model load.

Mirrors test_segmentation_report.py's pattern: a tiny generated video plus stub pose/
detection model objects, keeping the default pytest suite fast and network-independent.
"""

import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

# Allow importing the tool from tests/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.models import BoundingBox, Detection, Frame, Keypoint
from tools.analyze_angles import measure_video, nearest_frame, print_report


# ---------------------------------------------------------------------------
# Helpers / stubs
# ---------------------------------------------------------------------------

def _make_video(path: Path, num_frames: int = 20, fps: float = 10.0) -> None:
    """Write a minimal grayscale MP4 for testing."""
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, (64, 64))
    for i in range(num_frames):
        frame = np.full((64, 64, 3), i * 4 % 256, dtype=np.uint8)
        writer.write(frame)
    writer.release()


class StubPoseModel:
    """Fixed keypoint response for the joints this phase's candidate metrics read."""

    def infer(self, image: np.ndarray) -> dict[str, Keypoint]:
        return {
            "left_shoulder": Keypoint(x=0.4, y=0.6, confidence=0.9),
            "left_elbow": Keypoint(x=0.4, y=0.4, confidence=0.9),
            "left_wrist": Keypoint(x=0.4, y=0.2, confidence=0.9),
            "right_shoulder": Keypoint(x=0.6, y=0.6, confidence=0.9),
        }


class NoBallDetectionModel:
    """Never detects a ball — used to exercise ball_offset_* metrics' skip behavior."""

    def infer(self, image: np.ndarray) -> list[Detection]:
        return []


class BallDetectionModel:
    """Always detects a ball at a fixed bbox."""

    def infer(self, image: np.ndarray) -> list[Detection]:
        return [Detection(label="ball", confidence=0.9, bbox=BoundingBox(x_min=0.35, y_min=0.75, x_max=0.45, y_max=0.85))]


# ---------------------------------------------------------------------------
# nearest_frame
# ---------------------------------------------------------------------------

def test_nearest_frame_picks_closest_timestamp():
    frames = [
        Frame(timestamp=0.0, keypoints={}),
        Frame(timestamp=1.0, keypoints={}),
        Frame(timestamp=2.0, keypoints={}),
    ]
    assert nearest_frame(frames, 1.3).timestamp == pytest.approx(1.0)
    assert nearest_frame(frames, 1.6).timestamp == pytest.approx(2.0)


# ---------------------------------------------------------------------------
# measure_video
# ---------------------------------------------------------------------------

class TestMeasureVideo:

    def test_skips_metric_when_value_is_none(self, tmp_path):
        video_path = tmp_path / "serve_2.mov"
        _make_video(video_path)
        ground_truth = {
            "videos": {
                "serve_2.mov": [{"serve_index": 1, "phases": {"racket_drop": 0.5}}],
            }
        }
        results = measure_video(video_path, ground_truth, StubPoseModel(), NoBallDetectionModel(), stride=2)
        # ball_offset_y/x need a ball detection, which NoBallDetectionModel never provides.
        assert results["racket_drop_ball_height"] == {}
        assert results["racket_drop_ball_front"] == {}

    def test_computes_expected_value_for_known_frame(self, tmp_path):
        video_path = tmp_path / "serve_2.mov"
        _make_video(video_path)
        ground_truth = {
            "videos": {
                "serve_2.mov": [{"serve_index": 1, "phases": {"trophy_pose": 0.0}}],
            }
        }
        results = measure_video(video_path, ground_truth, StubPoseModel(), NoBallDetectionModel(), stride=2)
        # trophy_toss_arm_straight: angle(left_shoulder, left_elbow, left_wrist), a straight
        # vertical line (0.4,0.6)->(0.4,0.4)->(0.4,0.2) -> 180 degrees.
        assert results["trophy_toss_arm_straight"]["serve_2#1"] == pytest.approx(180.0, abs=1e-6)

    def test_ball_offset_computed_when_ball_detected(self, tmp_path):
        video_path = tmp_path / "serve_2.mov"
        _make_video(video_path)
        ground_truth = {
            "videos": {
                "serve_2.mov": [{"serve_index": 1, "phases": {"racket_drop": 0.0}}],
            }
        }
        results = measure_video(video_path, ground_truth, StubPoseModel(), BallDetectionModel(), stride=2)
        # ball bbox center = (0.4, 0.8); left_shoulder = (0.4, 0.6) -> offset_y = 0.2, offset_x = 0.0
        assert results["racket_drop_ball_height"]["serve_2#1"] == pytest.approx(0.2)
        assert results["racket_drop_ball_front"]["serve_2#1"] == pytest.approx(0.0)

    def test_returns_empty_when_video_has_no_ground_truth_entry(self, tmp_path):
        video_path = tmp_path / "unknown.mov"
        _make_video(video_path)
        results = measure_video(video_path, {"videos": {}}, StubPoseModel(), NoBallDetectionModel(), stride=2)
        assert results == {}


# ---------------------------------------------------------------------------
# print_report
# ---------------------------------------------------------------------------

def test_print_report_handles_single_value(capsys):
    results = {"trophy_toss_arm_straight": {"serve_2#1": 178.5}}
    print_report(results)
    captured = capsys.readouterr()
    assert "178.5000" in captured.out
    assert "stdev=0.0000" in captured.out


def test_print_report_handles_no_values(capsys):
    print_report({})
    captured = capsys.readouterr()
    assert "no values measured" in captured.out


def test_no_real_model_construction_in_this_file():
    """Guard against a real model ever being constructed in the default test suite."""
    source = Path(__file__).read_text()
    source_before_this_check = source.split("def test_no_real_model_construction_in_this_file")[0]
    for forbidden in ("RTMPoseModel(", "ObjectDetectionModel(", "YOLO(", "Body("):
        assert forbidden not in source_before_this_check
