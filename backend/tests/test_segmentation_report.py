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
    _build_arg_parser,
    build_frame_sequence,
    generate_segmentation_html,
    print_score_table,
    run_segmentation_report,
    score_videos,
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
    """Returns a constant neck/pelvis plus a scripted, call-count-indexed hitting-wrist height
    (ignores image content).

    Used to simulate distinct serve peaks independent of the synthetic video's actual (arbitrary)
    pixel content, so segment_serves' peak-based counting can be exercised end-to-end.
    """

    def __init__(self, y_sequence: list[float]):
        self._y_sequence = y_sequence
        self._call_count = 0

    def infer(self, image: np.ndarray) -> dict[str, Keypoint]:
        y = self._y_sequence[min(self._call_count, len(self._y_sequence) - 1)]
        self._call_count += 1
        return {
            "neck": Keypoint(x=0.5, y=0.7, confidence=0.9),
            "pelvis": Keypoint(x=0.5, y=0.4, confidence=0.9),
            "right_wrist": Keypoint(x=0.5, y=y, confidence=0.9),
        }


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
        _make_video(video_path, num_frames=90, fps=30.0)

        # Sampled at stride=5 from a 30fps video: 18 samples, dt≈0.167s apart. Two single-frame
        # peaks (well above the body-relative floor) separated by twelve idle (below-floor) samples
        # in between — a real ≈2.17s gap, comfortably clearing MIN_PEAK_SEPARATION_SECONDS.
        y_sequence = [0.5, 0.5, 0.95] + [0.5] * 12 + [0.95, 0.5, 0.5]
        pose_model = _SequencedPoseModel(y_sequence)
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
        assert len(jpegs) == 18  # 90 frames / stride 5


def test_default_stride_is_two():
    assert _build_arg_parser().get_default("stride") == 2


def test_no_real_model_construction_in_this_file():
    """Guard against a real model ever being constructed in the default test suite."""
    source = Path(__file__).read_text()
    source_before_this_check = source.split("def test_no_real_model_construction_in_this_file")[0]
    for forbidden in ("RTMPoseModel(", "ObjectDetectionModel(", "YOLO(", "Body("):
        assert forbidden not in source_before_this_check


# ---------------------------------------------------------------------------
# score_videos / print_score_table
# ---------------------------------------------------------------------------

class TestScoreVideos:
    """score_videos resolves each ground-truth video name against
    <_TOOLS_DIR>/calibration_data/<name>, so these tests monkeypatch _TOOLS_DIR to tmp_path
    and lay out a calibration_data/ subdirectory there rather than passing arbitrary paths.
    """

    def _calibration_dir(self, tmp_path, monkeypatch):
        monkeypatch.setattr("tools.segmentation_report._TOOLS_DIR", tmp_path)
        calibration_dir = tmp_path / "calibration_data"
        calibration_dir.mkdir()
        return calibration_dir

    def test_pass_when_actual_matches_expected(self, tmp_path, monkeypatch):
        # StubPoseModel emits a single fixed right_wrist keypoint with no motion and no
        # neck/pelvis — segment_serves detects zero serves under either the old velocity-based
        # or the new peak-based counting algorithm, so this fixture stays valid across Group 4's
        # rewrite.
        calibration_dir = self._calibration_dir(tmp_path, monkeypatch)
        video_path = calibration_dir / "serve_x.mov"
        _make_video(video_path, num_frames=30, fps=30.0)
        ground_truth = {"videos": {"serve_x.mov": {"expected_count": 0}}}

        results = score_videos([video_path], ground_truth, StubPoseModel(), StubDetectionModel())

        assert len(results) == 1
        assert results[0]["status"] == "PASS"
        assert results[0]["actual_count"] == 0
        assert results[0]["blocking"] is True
        assert results[0]["held_out"] is False

    def test_fail_when_actual_does_not_match_expected(self, tmp_path, monkeypatch):
        calibration_dir = self._calibration_dir(tmp_path, monkeypatch)
        video_path = calibration_dir / "serve_x.mov"
        _make_video(video_path, num_frames=30, fps=30.0)
        ground_truth = {"videos": {"serve_x.mov": {"expected_count": 2}}}

        results = score_videos([video_path], ground_truth, StubPoseModel(), StubDetectionModel())

        assert results[0]["status"] == "FAIL"
        assert results[0]["actual_count"] == 0

    def test_missing_video_reports_missing_status_not_exception(self, tmp_path, monkeypatch):
        self._calibration_dir(tmp_path, monkeypatch)
        ground_truth = {"videos": {"nonexistent.mov": {"expected_count": 1}}}

        results = score_videos([], ground_truth, StubPoseModel(), StubDetectionModel())

        assert results[0]["status"] == "MISSING"
        assert results[0]["actual_count"] is None

    def test_blocking_defaults_to_true_when_omitted(self, tmp_path, monkeypatch):
        calibration_dir = self._calibration_dir(tmp_path, monkeypatch)
        video_path = calibration_dir / "serve_x.mov"
        _make_video(video_path, num_frames=30, fps=30.0)
        ground_truth = {"videos": {"serve_x.mov": {"expected_count": 0}}}

        results = score_videos([video_path], ground_truth, StubPoseModel(), StubDetectionModel())

        assert results[0]["blocking"] is True


class TestPrintScoreTable:

    def test_held_out_and_known_limitation_markers(self, capsys):
        results = [
            {
                "video_name": "held_out.mov", "expected_count": 3, "actual_count": 3,
                "held_out": True, "blocking": True, "status": "PASS",
            },
            {
                "video_name": "limitation.mov", "expected_count": 2, "actual_count": 4,
                "held_out": False, "blocking": False, "status": "FAIL",
            },
        ]

        print_score_table(results)

        out = capsys.readouterr().out
        assert "[HELD OUT]" in out
        assert "[KNOWN LIMITATION]" in out
