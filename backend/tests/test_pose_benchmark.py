"""Tests for pose_benchmark.py using synthetic fixtures — no real model load.

Mirrors test_calibration_report.py's pattern: a tiny generated video plus stub
pose/detection model objects, keeping the default pytest suite fast and
network-independent.
"""

import json
import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

# Allow importing the tool from tests/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.models import BoundingBox, Detection, Keypoint
from tools.pose_benchmark import (
    FrameResult,
    aggregate_stats,
    benchmark_frame,
    draw_overlay,
    run_benchmark,
    sample_video_frames,
)


# ---------------------------------------------------------------------------
# Helpers / stubs
# ---------------------------------------------------------------------------

def _make_video(path: Path, num_frames: int = 60, fps: float = 30.0) -> None:
    """Write a minimal grayscale MP4 for testing."""
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, (64, 64))
    for i in range(num_frames):
        frame = np.full((64, 64, 3), i * 4 % 256, dtype=np.uint8)
        writer.write(frame)
    writer.release()


class StubPoseModel:
    """Fixed one-keypoint response; no real RTMPoseModel involved."""

    def infer(self, image: np.ndarray) -> dict[str, Keypoint]:
        return {"right_wrist": Keypoint(x=0.5, y=0.5, confidence=0.9)}


class StubDetectionModel:
    """Fixed one-racket-detection response; no real ObjectDetectionModel involved."""

    def infer(self, image: np.ndarray) -> list[Detection]:
        return [
            Detection(
                label="racket",
                confidence=0.8,
                bbox=BoundingBox(x_min=0.1, y_min=0.1, x_max=0.3, y_max=0.3),
            )
        ]


_SAMPLE_KEYPOINTS = {
    "left_shoulder": Keypoint(x=0.4, y=0.7, confidence=0.9),
    "right_shoulder": Keypoint(x=0.6, y=0.7, confidence=0.9),
}
_SAMPLE_DETECTIONS = [
    Detection(label="racket", confidence=0.8, bbox=BoundingBox(x_min=0.1, y_min=0.1, x_max=0.3, y_max=0.3))
]


# ---------------------------------------------------------------------------
# Group 1 — Frame sampling & overlay drawing
# ---------------------------------------------------------------------------

class TestSampleVideoFrames:

    def test_stride_five_on_sixty_frames(self, tmp_path):
        video_path = tmp_path / "serve.mp4"
        _make_video(video_path, num_frames=60, fps=30.0)

        sampled = sample_video_frames(video_path, stride=5)

        assert len(sampled) == 12
        expected_timestamps = [i * 5 / 30.0 for i in range(12)]
        actual_timestamps = [ts for ts, _ in sampled]
        assert actual_timestamps == pytest.approx(expected_timestamps)

    def test_stride_one_returns_all_frames(self, tmp_path):
        video_path = tmp_path / "serve.mp4"
        _make_video(video_path, num_frames=60, fps=30.0)

        sampled = sample_video_frames(video_path, stride=1)

        assert len(sampled) == 60

    def test_nonexistent_video_raises(self, tmp_path):
        with pytest.raises(ValueError):
            sample_video_frames(tmp_path / "missing.mov", stride=5)


class TestDrawOverlay:

    def test_returns_same_shape_copy(self):
        image = np.full((64, 64, 3), 128, dtype=np.uint8)
        result = draw_overlay(image, _SAMPLE_KEYPOINTS, _SAMPLE_DETECTIONS)

        assert result is not image
        assert result.shape == image.shape

    def test_annotates_frame(self):
        image = np.full((64, 64, 3), 128, dtype=np.uint8)
        result = draw_overlay(image, _SAMPLE_KEYPOINTS, _SAMPLE_DETECTIONS)

        assert not np.array_equal(result, image)

    def test_no_keypoints_or_detections_does_not_raise(self):
        image = np.full((64, 64, 3), 128, dtype=np.uint8)
        result = draw_overlay(image, {}, [])

        assert result.shape == image.shape


# ---------------------------------------------------------------------------
# Group 2 — Per-frame benchmarking & aggregation
# ---------------------------------------------------------------------------

class TestBenchmarkFrame:

    def test_detects_person_and_racket_not_ball(self):
        image = np.zeros((64, 64, 3), dtype=np.uint8)
        result = benchmark_frame(image, StubPoseModel(), StubDetectionModel())

        assert result.person_detected is True
        assert result.racket_detected is True
        assert result.ball_detected is False
        assert result.racket_confidence == pytest.approx(0.8)
        assert result.ball_confidence is None
        assert result.pose_latency_s >= 0.0
        assert result.detection_latency_s >= 0.0


class TestAggregateStats:

    def _result(self, racket_detected: bool) -> FrameResult:
        return FrameResult(
            timestamp=0.0,
            person_detected=True,
            keypoint_confidences=[0.9, 0.8],
            racket_detected=racket_detected,
            racket_confidence=0.8 if racket_detected else None,
            ball_detected=False,
            ball_confidence=None,
            pose_latency_s=0.1,
            detection_latency_s=0.05,
            keypoints={},
            detections=[],
        )

    def test_per_video_detection_rate_and_averages(self):
        per_video = {"serve_1": [self._result(True), self._result(True), self._result(False)]}

        stats = aggregate_stats(per_video, stride=5)

        video_stats = stats["videos"]["serve_1"]
        assert video_stats["racket_detection_rate"] == pytest.approx(2 / 3)
        assert video_stats["avg_keypoint_confidence"] == pytest.approx(0.85)
        assert video_stats["avg_pose_fps"] == pytest.approx(1.0 / 0.1)

    def test_aggregate_pools_multiple_videos(self):
        per_video = {
            "serve_1": [self._result(True)],
            "serve_2": [self._result(False), self._result(False)],
        }

        stats = aggregate_stats(per_video, stride=5)

        assert stats["aggregate"]["frame_count"] == 3
        assert stats["aggregate"]["racket_detection_rate"] == pytest.approx(1 / 3)

    def test_empty_frame_list_no_division_by_zero(self):
        per_video = {"serve_empty": []}

        stats = aggregate_stats(per_video, stride=5)

        video_stats = stats["videos"]["serve_empty"]
        assert video_stats["racket_detection_rate"] == 0.0
        assert video_stats["avg_keypoint_confidence"] is None


# ---------------------------------------------------------------------------
# Group 3 — HTML report & CLI orchestration
# ---------------------------------------------------------------------------

class TestRunBenchmark:

    def test_report_and_baseline_created(self, tmp_path):
        video_path = tmp_path / "serve_1.mov"
        _make_video(video_path, num_frames=30, fps=30.0)

        report_root = tmp_path / "reports"
        baseline_dir = tmp_path / "baselines"

        baseline_path = run_benchmark(
            [video_path],
            stride=5,
            pose_model=StubPoseModel(),
            detection_model=StubDetectionModel(),
            report_root=report_root,
            baseline_dir=baseline_dir,
        )

        assert baseline_path.exists()
        summary = json.loads(baseline_path.read_text())
        assert set(["generated_at", "stride", "videos", "aggregate"]).issubset(summary.keys())

        video_output_dir = report_root / "serve_1_benchmark"
        assert (video_output_dir / "report.html").exists()
        jpegs = list((video_output_dir / "frames").glob("*.jpg"))
        assert len(jpegs) == 6  # 30 frames / stride 5


def test_no_real_model_construction_in_this_file():
    """Guard against a real model ever being constructed in the default test suite."""
    source = Path(__file__).read_text()
    source_before_this_check = source.split("def test_no_real_model_construction_in_this_file")[0]
    for forbidden in ("RTMPoseModel(", "ObjectDetectionModel(", "YOLO(", "Body("):
        assert forbidden not in source_before_this_check
