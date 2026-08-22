"""Tests for segmentation_sweep.py using synthetic fixtures — no real model load.

Mirrors test_segmentation_report.py's pattern: a tiny generated video plus stub pose/detection
model objects, keeping the default pytest suite fast and network-independent.
"""

import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.models import BoundingBox, Detection, Keypoint
from tools.segmentation_sweep import cache_path_for, load_or_build_cache, sweep


def _make_video(path: Path, num_frames: int = 30, fps: float = 30.0) -> None:
    """Write a minimal grayscale MP4 for testing."""
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, (64, 64))
    for i in range(num_frames):
        frame = np.full((64, 64, 3), i * 4 % 256, dtype=np.uint8)
        writer.write(frame)
    writer.release()


class _CountingPoseModel:
    """Fixed one-keypoint response; tracks how many times inference actually ran."""

    def __init__(self):
        self.call_count = 0

    def infer(self, image: np.ndarray) -> dict[str, Keypoint]:
        self.call_count += 1
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


class TestLoadOrBuildCache:

    def test_second_call_reuses_cache_without_reinference(self, tmp_path):
        video_path = tmp_path / "serve_x.mov"
        _make_video(video_path)
        cache_dir = tmp_path / "cache"
        pose_model = _CountingPoseModel()

        first = load_or_build_cache(video_path, cache_dir, stride=5, pose_model=pose_model, detection_model=StubDetectionModel())
        calls_after_first = pose_model.call_count
        second = load_or_build_cache(video_path, cache_dir, stride=5, pose_model=pose_model, detection_model=StubDetectionModel())

        assert pose_model.call_count == calls_after_first
        assert len(first.frames) == len(second.frames) == calls_after_first
        assert cache_path_for(video_path, cache_dir).exists()

    def test_changed_video_invalidates_cache_and_reinfers(self, tmp_path):
        video_path = tmp_path / "serve_x.mov"
        _make_video(video_path, num_frames=30)
        cache_dir = tmp_path / "cache"
        pose_model = _CountingPoseModel()

        load_or_build_cache(video_path, cache_dir, stride=5, pose_model=pose_model, detection_model=StubDetectionModel())
        calls_after_first = pose_model.call_count

        # Re-record the clip: different content/mtime/size at the same path.
        _make_video(video_path, num_frames=45)
        load_or_build_cache(video_path, cache_dir, stride=5, pose_model=pose_model, detection_model=StubDetectionModel())

        assert pose_model.call_count > calls_after_first


class TestSweep:

    def test_results_sorted_best_first_and_held_out_excluded(self, tmp_path, monkeypatch):
        # sweep resolves each ground-truth video name against <_TOOLS_DIR>/calibration_data/<name>
        # (mirroring score_videos), so videos live under a calibration_data/ subdir of tmp_path.
        monkeypatch.setattr("tools.segmentation_sweep._TOOLS_DIR", tmp_path)
        calibration_dir = tmp_path / "calibration_data"
        calibration_dir.mkdir()

        video_a = calibration_dir / "a.mov"
        video_b = calibration_dir / "b.mov"
        video_holdout = calibration_dir / "c.mov"
        for v in (video_a, video_b, video_holdout):
            _make_video(v)

        ground_truth = {
            "videos": {
                "a.mov": {"expected_count": 2, "held_out": False},
                "b.mov": {"expected_count": 3, "held_out": False},
                "c.mov": {"expected_count": 5, "held_out": True},
            }
        }

        # Fake counting logic keyed only on floor_k, so match totals differ across the grid and
        # the held-out video's expected_count (5) never appears anywhere in the fake's outputs —
        # if it were incorrectly included in scoring, no combination could ever score a "match"
        # against it and this test's assertions on `total` below would fail.
        def fake_segment_serves(frames, floor_k, min_peak_separation_seconds):
            count = 2 if floor_k == 0.1 else 3
            return [frames] * count

        monkeypatch.setattr("tools.segmentation_sweep.segment_serves", fake_segment_serves)

        cache_dir = tmp_path / "cache"
        pose_model = _CountingPoseModel()

        results = sweep(
            [video_a, video_b, video_holdout],
            ground_truth,
            floor_k_values=[0.1, 0.2],
            min_separation_values=[0.6],
            cache_dir=cache_dir,
            pose_model=pose_model,
            detection_model=StubDetectionModel(),
        )

        assert results[0]["matches"] >= results[-1]["matches"]
        assert all(r["total"] == 2 for r in results)  # only a.mov/b.mov, never the held-out c.mov
