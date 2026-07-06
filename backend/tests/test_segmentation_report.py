"""Tests for segmentation_report.py using synthetic fixtures — no real model load.

Mirrors test_pose_benchmark.py's pattern: a tiny generated video plus stub pose/
detection model objects, keeping the default pytest suite fast and network-independent.
"""

import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

# Allow importing the tool from tests/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.models import BoundingBox, Detection, Frame, Keypoint, ServePhase
from tools.segmentation_report import (
    _PHASE_LABELS,
    build_frame_sequence,
    generate_segmentation_html,
    run_segmentation_report,
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


class _SequencedPoseModel:
    """Returns a scripted, call-count-indexed keypoint x-position (ignores image content).

    Used to simulate distinct motion bursts independent of the synthetic video's actual
    (arbitrary) pixel content, so segment_serves' velocity-based splitting can be exercised
    end-to-end.
    """

    def __init__(self, x_sequence: list[float]):
        self._x_sequence = x_sequence
        self._call_count = 0

    def infer(self, image: np.ndarray) -> dict[str, Keypoint]:
        x = self._x_sequence[min(self._call_count, len(self._x_sequence) - 1)]
        self._call_count += 1
        return {"right_wrist": Keypoint(x=x, y=0.5, confidence=0.9)}


# ---------------------------------------------------------------------------
# build_frame_sequence
# ---------------------------------------------------------------------------

class TestBuildFrameSequence:

    def test_matching_length_lists(self, tmp_path):
        video_path = tmp_path / "serve_x.mov"
        _make_video(video_path, num_frames=30, fps=30.0)

        frames, detections, images = build_frame_sequence(
            video_path, stride=5, pose_model=StubPoseModel(), detection_model=StubDetectionModel()
        )

        assert len(frames) == len(detections) == len(images) == 6  # 30 frames / stride 5


# ---------------------------------------------------------------------------
# generate_segmentation_html
# ---------------------------------------------------------------------------

class TestGenerateSegmentationHtml:

    def test_report_has_one_section_per_serve_and_all_phase_labels(self, tmp_path):
        output_dir = tmp_path / "serve_x_segmentation"
        frames_dir = output_dir / "frames"
        frames_dir.mkdir(parents=True)

        f0 = Frame(timestamp=0.0, keypoints={})
        f1 = Frame(timestamp=1.0, keypoints={})
        f2 = Frame(timestamp=2.0, keypoints={})
        f3 = Frame(timestamp=3.0, keypoints={})

        frame_paths: dict[float, Path] = {}
        for i, frame in enumerate([f0, f1, f2, f3]):
            path = frames_dir / f"frame{i:03d}.jpg"
            path.write_bytes(b"")
            frame_paths[frame.timestamp] = path

        serve_segments = [[f0, f1], [f2, f3]]
        phase_results = [
            {
                ServePhase.start: f0,
                ServePhase.release: None,
                ServePhase.trophy_pose: f1,
                ServePhase.racket_drop: None,
                ServePhase.contact: None,
                ServePhase.finish: None,
            },
            {
                ServePhase.start: None,
                ServePhase.release: None,
                ServePhase.trophy_pose: None,
                ServePhase.racket_drop: None,
                ServePhase.contact: f2,
                ServePhase.finish: f3,
            },
        ]

        report_path = generate_segmentation_html(
            "serve_x", serve_segments, phase_results, frame_paths, output_dir
        )

        html = report_path.read_text()
        assert html.count("<section>") == 2
        for label in _PHASE_LABELS.values():
            assert label in html
        assert "(not detected)" in html


# ---------------------------------------------------------------------------
# run_segmentation_report
# ---------------------------------------------------------------------------

class TestRunSegmentationReport:

    def test_two_motion_bursts_produce_two_serve_sections(self, tmp_path):
        video_path = tmp_path / "serve_x.mov"
        _make_video(video_path, num_frames=60, fps=30.0)

        x_sequence = (
            [0.1 * i for i in range(4)]           # active burst 1: 0.0..0.3
            + [0.3] * 4                             # rest (spans 3 * 5/30s ≈ 0.5s of real time)
            + [0.4 + 0.1 * i for i in range(4)]     # active burst 2: 0.4..0.7
        )
        pose_model = _SequencedPoseModel(x_sequence)
        detection_model = StubDetectionModel()

        report_root = tmp_path / "reports"
        report_paths = run_segmentation_report(
            [video_path],
            stride=5,
            pose_model=pose_model,
            detection_model=detection_model,
            report_root=report_root,
        )

        assert len(report_paths) == 1
        html = report_paths[0].read_text()
        assert html.count("<section>") == 2

        video_output_dir = report_root / "serve_x_segmentation"
        jpegs = list((video_output_dir / "frames").glob("*.jpg"))
        assert len(jpegs) == 12  # 60 frames / stride 5


def test_no_real_model_construction_in_this_file():
    """Guard against a real model ever being constructed in the default test suite."""
    source = Path(__file__).read_text()
    source_before_this_check = source.split("def test_no_real_model_construction_in_this_file")[0]
    for forbidden in ("RTMPoseModel(", "ObjectDetectionModel(", "YOLO(", "Body("):
        assert forbidden not in source_before_this_check
