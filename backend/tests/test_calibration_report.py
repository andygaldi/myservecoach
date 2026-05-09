"""Smoke test for calibration_report.py.

Creates a synthetic keypoint log and a small generated video, runs the tool,
and verifies that the expected output files are produced.
"""

import json
import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

# Allow importing the tool from tests/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.calibration_report import (
    generate_html,
    normalize_joints,
    parse_console_log,
    to_backend_frame,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_video(path: Path, num_frames: int = 60, fps: float = 30.0) -> None:
    """Write a minimal grayscale MP4 for testing."""
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, (64, 64))
    for i in range(num_frames):
        frame = np.full((64, 64, 3), i * 4 % 256, dtype=np.uint8)
        writer.write(frame)
    writer.release()


def _make_keypoints_log(serves: list[list[dict]]) -> str:
    """Render a list of serves into the Xcode console format."""
    lines: list[str] = []
    total = len(serves)
    for idx, frames in enumerate(serves, 1):
        lines.append(f"[MyServeCoach] Serve {idx}/{total} — {len(frames)} frames")
        for frame in frames:
            lines.append(json.dumps(frame, indent=2))
    return "\n".join(lines) + "\n"


# Canonical serve sequence that triggers all three phase detections.
# Joint names are Vision-style (what the iOS app logs).
# Timestamps map to video frames at 30 fps (frame 0 = t=0.0, frame 1 = t=0.033, …).
_T = [i / 30.0 for i in range(10)]

def _j(lw_y, ls_y, rw_y, rh_y, conf=0.9):
    """Build a joints dict for a single frame."""
    return {
        "left_wrist_joint":       {"x": 0.3, "y": lw_y, "confidence": conf},
        "left_shoulder_1_joint":  {"x": 0.4, "y": ls_y, "confidence": conf},
        "right_wrist_joint":      {"x": 0.7, "y": rw_y, "confidence": conf},
        "right_upLeg_joint":      {"x": 0.5, "y": rh_y, "confidence": conf},
    }

# Frame-by-frame serve:
#   t0: pre-serve (toss wrist below shoulder)
#   t1: trophy pose  – lw_y=0.80 > ls_y=0.65; rw_y=0.50 > rh_y=0.30
#   t2-t3: racket drops – rw_y falling
#   t4: racket drop  – rw_y=0.05 (minimum)
#   t5-t8: wrist rises
#   t9: contact      – rw_y=0.95 (maximum)
_SERVE_FRAMES = [
    {"timestamp": _T[0], "joints": _j(lw_y=0.20, ls_y=0.65, rw_y=0.50, rh_y=0.30)},  # pre-serve
    {"timestamp": _T[1], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.50, rh_y=0.30)},  # trophy (idx 1)
    {"timestamp": _T[2], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.30, rh_y=0.30)},
    {"timestamp": _T[3], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.15, rh_y=0.30)},
    {"timestamp": _T[4], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.05, rh_y=0.30)},  # drop (idx 4)
    {"timestamp": _T[5], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.30, rh_y=0.30)},
    {"timestamp": _T[6], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.55, rh_y=0.30)},
    {"timestamp": _T[7], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.70, rh_y=0.30)},
    {"timestamp": _T[8], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.85, rh_y=0.30)},
    {"timestamp": _T[9], "joints": _j(lw_y=0.80, ls_y=0.65, rw_y=0.95, rh_y=0.30)},  # contact (idx 9)
]


# ---------------------------------------------------------------------------
# Unit tests for parsing helpers
# ---------------------------------------------------------------------------

class TestParseConsoleLog:

    def test_single_serve_parsed(self, tmp_path):
        log = _make_keypoints_log([_SERVE_FRAMES])
        log_file = tmp_path / "log.txt"
        log_file.write_text(log)

        serves = parse_console_log(log_file)
        assert len(serves) == 1
        assert len(serves[0]) == len(_SERVE_FRAMES)

    def test_two_serves_parsed(self, tmp_path):
        log = _make_keypoints_log([_SERVE_FRAMES, _SERVE_FRAMES])
        log_file = tmp_path / "log.txt"
        log_file.write_text(log)

        serves = parse_console_log(log_file)
        assert len(serves) == 2

    def test_timestamps_preserved(self, tmp_path):
        log = _make_keypoints_log([_SERVE_FRAMES])
        log_file = tmp_path / "log.txt"
        log_file.write_text(log)

        serves = parse_console_log(log_file)
        parsed_ts = [f["timestamp"] for f in serves[0]]
        expected_ts = [f["timestamp"] for f in _SERVE_FRAMES]
        assert parsed_ts == pytest.approx(expected_ts)

    def test_extra_console_noise_is_ignored(self, tmp_path):
        noisy = (
            "Some other app log line\n"
            + _make_keypoints_log([_SERVE_FRAMES])
            + "Another noise line\n"
        )
        log_file = tmp_path / "log.txt"
        log_file.write_text(noisy)

        serves = parse_console_log(log_file)
        assert len(serves) == 1
        assert len(serves[0]) == len(_SERVE_FRAMES)


class TestNormalizeJoints:

    def test_wrist_joint_stripped(self):
        result = normalize_joints({"left_wrist_joint": {"x": 0.1, "y": 0.2, "confidence": 0.9}})
        assert "left_wrist" in result
        assert "left_wrist_joint" not in result

    def test_shoulder_1_joint_stripped(self):
        result = normalize_joints({"left_shoulder_1_joint": {"x": 0.1, "y": 0.2, "confidence": 0.9}})
        assert "left_shoulder" in result

    def test_upLeg_becomes_hip(self):
        result = normalize_joints({"right_upLeg_joint": {"x": 0.5, "y": 0.3, "confidence": 0.9}})
        assert "right_hip" in result

    def test_values_preserved(self):
        joints = {"left_wrist_joint": {"x": 0.3, "y": 0.7, "confidence": 0.9}}
        result = normalize_joints(joints)
        assert result["left_wrist"] == joints["left_wrist_joint"]


# ---------------------------------------------------------------------------
# Phase detection integration
# ---------------------------------------------------------------------------

class TestPhaseDetection:

    def test_all_three_phases_detected_from_ios_frames(self):
        from app.engine.phases import detect_phases
        from app.models import ServePhase

        backend_frames = [to_backend_frame(d) for d in _SERVE_FRAMES]
        phases = detect_phases(backend_frames)

        assert phases[ServePhase.trophy_pose] is not None
        assert phases[ServePhase.racket_drop] is not None
        assert phases[ServePhase.contact] is not None

    def test_trophy_at_expected_index(self):
        from app.engine.phases import detect_phases
        from app.models import ServePhase

        backend_frames = [to_backend_frame(d) for d in _SERVE_FRAMES]
        phases = detect_phases(backend_frames)

        assert phases[ServePhase.trophy_pose].timestamp == pytest.approx(_T[1])

    def test_racket_drop_at_expected_index(self):
        from app.engine.phases import detect_phases
        from app.models import ServePhase

        backend_frames = [to_backend_frame(d) for d in _SERVE_FRAMES]
        phases = detect_phases(backend_frames)

        assert phases[ServePhase.racket_drop].timestamp == pytest.approx(_T[4])

    def test_contact_at_expected_index(self):
        from app.engine.phases import detect_phases
        from app.models import ServePhase

        backend_frames = [to_backend_frame(d) for d in _SERVE_FRAMES]
        phases = detect_phases(backend_frames)

        assert phases[ServePhase.contact].timestamp == pytest.approx(_T[9])


# ---------------------------------------------------------------------------
# End-to-end smoke test
# ---------------------------------------------------------------------------

class TestEndToEnd:

    def test_report_and_frames_created(self, tmp_path):
        """Full pipeline: log → video → report.html + frames/*.jpg."""
        video_path = tmp_path / "serve.mp4"
        _make_video(video_path, num_frames=60, fps=30.0)

        log_path = tmp_path / "log.txt"
        log_path.write_text(_make_keypoints_log([_SERVE_FRAMES]))

        output_dir = tmp_path / "report"

        # Import and run main() with patched sys.argv.
        import sys
        old_argv = sys.argv
        sys.argv = [
            "calibration_report.py",
            "--keypoints", str(log_path),
            "--video", str(video_path),
            "--output", str(output_dir),
        ]
        try:
            from tools.calibration_report import main
            main()
        finally:
            sys.argv = old_argv

        assert (output_dir / "report.html").exists()
        frames_dir = output_dir / "frames"
        assert frames_dir.is_dir()
        jpegs = list(frames_dir.glob("*.jpg"))
        assert len(jpegs) == len(_SERVE_FRAMES)

    def test_report_html_contains_serve_section(self, tmp_path):
        video_path = tmp_path / "serve.mp4"
        _make_video(video_path, num_frames=60, fps=30.0)

        log_path = tmp_path / "log.txt"
        log_path.write_text(_make_keypoints_log([_SERVE_FRAMES]))

        output_dir = tmp_path / "report"

        import sys
        old_argv = sys.argv
        sys.argv = [
            "calibration_report.py",
            "--keypoints", str(log_path),
            "--video", str(video_path),
            "--output", str(output_dir),
        ]
        try:
            from tools.calibration_report import main
            main()
        finally:
            sys.argv = old_argv

        html = (output_dir / "report.html").read_text()
        assert "Serve 1" in html
        assert "Trophy Pose" in html
        assert "Racket Drop" in html
        assert "Contact Point" in html
