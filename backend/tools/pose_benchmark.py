#!/usr/bin/env python3
"""
pose_benchmark.py — Developer tool for CV model performance baselining.

Samples frames from real serve footage at a configurable stride, runs each frame
through the existing off-device pose model (RTMPoseModel, Phase P1) and object
detector (ObjectDetectionModel, Phase P2), and records detection-rate/confidence/
FPS statistics. Produces a gitignored HTML report with skeleton/bbox overlays for
human spot-check, plus a small git-tracked numeric summary that becomes the
reference baseline for future model or approach swaps.

Usage:
    python backend/tools/pose_benchmark.py \\
        --videos      "backend/tools/calibration_data/*.mov" \\
        --stride      5 \\
        --report-dir  backend/tools/calibration_data \\
        --baseline-dir backend/tools/pose_benchmark_baselines

Output:
    <report-dir>/<video_stem>_benchmark/report.html   — open in any browser
    <report-dir>/<video_stem>_benchmark/frames/        — annotated JPEG frames
    <baseline-dir>/<timestamp>.json                    — git-tracked numeric summary
"""

import argparse
import glob as glob_module
import json
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import cv2
import numpy as np

# Allow running from the repo root or from inside backend/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.engine.angles import MIN_CONFIDENCE
from app.models import Detection, Keypoint
from app.services.object_detection import get_object_detection_model
from app.services.pose_model import get_pose_model
from app.services.video_sampler import sample_video_frames  # noqa: F401 (re-exported)
from tools.calibration_report import _img_tag


# ---------------------------------------------------------------------------
# Overlay drawing
# ---------------------------------------------------------------------------

LIMB_PAIRS: list[tuple[str, str]] = [
    ("left_shoulder", "right_shoulder"),
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    ("left_hip", "right_hip"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_hip", "left_knee"),
    ("left_knee", "left_ankle"),
    ("right_hip", "right_knee"),
    ("right_knee", "right_ankle"),
]

_DETECTION_COLORS: dict[str, tuple[int, int, int]] = {
    "racket": (255, 128, 0),
    "ball": (0, 200, 0),
}


def _to_pixel(kp: Keypoint, width: int, height: int) -> tuple[int, int]:
    return int(kp.x * width), int((1.0 - kp.y) * height)


def draw_overlay(
    image: np.ndarray, keypoints: dict[str, Keypoint], detections: list[Detection]
) -> np.ndarray:
    """Return a copy of *image* with the pose skeleton and detection boxes drawn on top."""
    out = image.copy()
    h, w = out.shape[:2]

    visible = {
        name: kp for name, kp in keypoints.items() if kp.confidence >= MIN_CONFIDENCE
    }
    for name_a, name_b in LIMB_PAIRS:
        if name_a in visible and name_b in visible:
            pt_a = _to_pixel(visible[name_a], w, h)
            pt_b = _to_pixel(visible[name_b], w, h)
            cv2.line(out, pt_a, pt_b, (0, 255, 255), 2)
    for kp in visible.values():
        cv2.circle(out, _to_pixel(kp, w, h), 4, (0, 255, 255), -1)

    for det in detections:
        px_min = int(det.bbox.x_min * w)
        px_max = int(det.bbox.x_max * w)
        py_min = int((1.0 - det.bbox.y_max) * h)
        py_max = int((1.0 - det.bbox.y_min) * h)
        color = _DETECTION_COLORS.get(det.label, (200, 200, 200))
        cv2.rectangle(out, (px_min, py_min), (px_max, py_max), color, 2)
        cv2.putText(
            out,
            f"{det.label} {det.confidence:.2f}",
            (px_min, max(py_min - 6, 0)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.4,
            color,
            1,
            cv2.LINE_AA,
        )

    return out


# ---------------------------------------------------------------------------
# Per-frame benchmarking
# ---------------------------------------------------------------------------

@dataclass
class FrameResult:
    timestamp: float
    person_detected: bool
    keypoint_confidences: list[float]
    racket_detected: bool
    racket_confidence: float | None
    ball_detected: bool
    ball_confidence: float | None
    pose_latency_s: float
    detection_latency_s: float
    keypoints: dict[str, Keypoint]
    detections: list[Detection]


def benchmark_frame(image: np.ndarray, pose_model, detection_model) -> FrameResult:
    """Run *pose_model* and *detection_model* against a single frame and record metrics."""
    t0 = time.perf_counter()
    keypoints = pose_model.infer(image)
    pose_latency_s = time.perf_counter() - t0

    t0 = time.perf_counter()
    detections = detection_model.infer(image)
    detection_latency_s = time.perf_counter() - t0

    racket = next((d for d in detections if d.label == "racket"), None)
    ball = next((d for d in detections if d.label == "ball"), None)

    return FrameResult(
        timestamp=0.0,
        person_detected=bool(keypoints),
        keypoint_confidences=[kp.confidence for kp in keypoints.values()],
        racket_detected=racket is not None,
        racket_confidence=racket.confidence if racket else None,
        ball_detected=ball is not None,
        ball_confidence=ball.confidence if ball else None,
        pose_latency_s=pose_latency_s,
        detection_latency_s=detection_latency_s,
        keypoints=keypoints,
        detections=detections,
    )


def benchmark_video(
    video_path: Path, pose_model, detection_model, stride: int
) -> list[tuple[FrameResult, np.ndarray]]:
    """Sample frames from *video_path* and benchmark each one, pairing results with the raw frame."""
    paired: list[tuple[FrameResult, np.ndarray]] = []
    for timestamp, frame in sample_video_frames(video_path, stride):
        result = benchmark_frame(frame, pose_model, detection_model)
        result.timestamp = timestamp
        paired.append((result, frame))
    return paired


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------

def _mean(values: list[float]) -> float | None:
    return sum(values) / len(values) if values else None


def _video_stats(results: list[FrameResult]) -> dict:
    frame_count = len(results)
    if frame_count == 0:
        return {
            "frame_count": 0,
            "person_detection_rate": 0.0,
            "racket_detection_rate": 0.0,
            "ball_detection_rate": 0.0,
            "avg_keypoint_confidence": None,
            "avg_racket_confidence": None,
            "avg_ball_confidence": None,
            "avg_pose_fps": None,
            "avg_detection_fps": None,
        }

    all_keypoint_confidences = [c for r in results for c in r.keypoint_confidences]
    racket_confidences = [r.racket_confidence for r in results if r.racket_confidence is not None]
    ball_confidences = [r.ball_confidence for r in results if r.ball_confidence is not None]
    avg_pose_latency = _mean([r.pose_latency_s for r in results])
    avg_detection_latency = _mean([r.detection_latency_s for r in results])

    return {
        "frame_count": frame_count,
        "person_detection_rate": sum(r.person_detected for r in results) / frame_count,
        "racket_detection_rate": sum(r.racket_detected for r in results) / frame_count,
        "ball_detection_rate": sum(r.ball_detected for r in results) / frame_count,
        "avg_keypoint_confidence": _mean(all_keypoint_confidences),
        "avg_racket_confidence": _mean(racket_confidences),
        "avg_ball_confidence": _mean(ball_confidences),
        "avg_pose_fps": (1.0 / avg_pose_latency) if avg_pose_latency else None,
        "avg_detection_fps": (1.0 / avg_detection_latency) if avg_detection_latency else None,
    }


def aggregate_stats(per_video: dict[str, list[FrameResult]], stride: int) -> dict:
    """Compute per-video and pooled-aggregate detection-rate/confidence/FPS statistics."""
    videos = {name: _video_stats(results) for name, results in per_video.items()}
    all_results = [r for results in per_video.values() for r in results]

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "stride": stride,
        "videos": videos,
        "aggregate": _video_stats(all_results),
    }


# ---------------------------------------------------------------------------
# HTML report generation
# ---------------------------------------------------------------------------

def _caption(result: FrameResult) -> str:
    racket = f"yes ({result.racket_confidence:.2f})" if result.racket_detected else "no"
    ball = f"yes ({result.ball_confidence:.2f})" if result.ball_detected else "no"
    total_ms = (result.pose_latency_s + result.detection_latency_s) * 1000
    return (
        f"person: {'yes' if result.person_detected else 'no'} | "
        f"racket: {racket} | ball: {ball} | {total_ms:.0f}ms"
    )


def generate_benchmark_html(
    video_name: str, results: list[FrameResult], frame_paths: list[Path], output_dir: Path
) -> Path:
    """Write <output_dir>/report.html with an annotated thumbnail strip for one video."""
    thumbnails: list[str] = []
    for result, frame_path in zip(results, frame_paths):
        rel = str(frame_path.relative_to(output_dir))
        thumbnails.append(_img_tag(rel, width=160, stats=_caption(result)))
    strip_html = "".join(thumbnails) or "<em>No frames extracted.</em>"

    html = (
        "<!DOCTYPE html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '  <meta charset="utf-8">\n'
        "  <title>Pose Benchmark Report</title>\n"
        "  <style>\n"
        "    body{font-family:sans-serif;max-width:1400px;margin:0 auto;padding:16px}\n"
        "    h1{border-bottom:2px solid #333;padding-bottom:8px}\n"
        "    h2{color:#333;margin-bottom:4px}\n"
        "    small{font-weight:normal;color:#777}\n"
        "    section{margin-bottom:40px;border-bottom:1px solid #ddd;padding-bottom:24px}\n"
        "  </style>\n"
        "</head>\n"
        "<body>\n"
        "  <h1>Pose Benchmark Report</h1>\n"
        f"  <section>\n"
        f"    <h2>{video_name} <small>({len(results)} frames)</small></h2>\n"
        f"    <div style='overflow-x:auto;white-space:nowrap;padding:4px 0'>{strip_html}</div>\n"
        f"  </section>\n"
        "</body>\n"
        "</html>\n"
    )

    report_path = output_dir / "report.html"
    report_path.write_text(html, encoding="utf-8")
    return report_path


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def run_benchmark(
    video_paths: list[Path],
    stride: int,
    pose_model,
    detection_model,
    report_root: Path,
    baseline_dir: Path,
) -> Path:
    """Benchmark every video, write per-video HTML reports, and commit a baseline JSON."""
    per_video: dict[str, list[FrameResult]] = {}

    for video_path in video_paths:
        paired = benchmark_video(video_path, pose_model, detection_model, stride)
        results = [r for r, _ in paired]
        per_video[video_path.stem] = results

        video_output_dir = report_root / f"{video_path.stem}_benchmark"
        frames_dir = video_output_dir / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)

        frame_paths: list[Path] = []
        for i, (result, frame) in enumerate(paired):
            annotated = draw_overlay(frame, result.keypoints, result.detections)
            frame_path = frames_dir / f"frame{i:03d}.jpg"
            cv2.imwrite(str(frame_path), annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
            frame_paths.append(frame_path)

        generate_benchmark_html(video_path.stem, results, frame_paths, video_output_dir)

    summary = aggregate_stats(per_video, stride)

    baseline_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    baseline_path = baseline_dir / f"{timestamp}.json"
    baseline_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    return baseline_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# Resolved from this file's own location (backend/tools/) rather than the
# current working directory, so defaults work whether invoked as
# `cd backend && python tools/pose_benchmark.py` or `python backend/tools/pose_benchmark.py`.
_TOOLS_DIR = Path(__file__).resolve().parent


def _resolve_videos(pattern: str) -> list[Path]:
    """Resolve a glob pattern (absolute or relative), matching both lowercase and uppercase extensions."""
    matches = {Path(p).resolve() for p in glob_module.glob(pattern)}
    if pattern.endswith(".mov"):
        matches |= {Path(p).resolve() for p in glob_module.glob(pattern[: -len(".mov")] + ".MOV")}
    return sorted(matches)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Benchmark the off-device pose model and object detector against real footage."
    )
    parser.add_argument(
        "--videos", default=str(_TOOLS_DIR / "calibration_data" / "*.mov"),
        help="Glob pattern for input videos (matches both .mov and .MOV).",
    )
    parser.add_argument("--stride", type=int, default=5, help="Sample every Nth video frame.")
    parser.add_argument(
        "--report-dir", type=Path, default=_TOOLS_DIR / "calibration_data",
        help="Parent directory under which each <video_stem>_benchmark/ report is written.",
    )
    parser.add_argument(
        "--baseline-dir", type=Path, default=_TOOLS_DIR / "pose_benchmark_baselines",
        help="Directory to write the git-tracked timestamped baseline JSON.",
    )
    args = parser.parse_args()

    video_paths = _resolve_videos(args.videos)
    if not video_paths:
        sys.exit(f"error: no videos matched pattern: {args.videos}")

    print(f"Found {len(video_paths)} video(s): {[p.name for p in video_paths]}")

    pose_model = get_pose_model()
    detection_model = get_object_detection_model()

    baseline_path = run_benchmark(
        video_paths, args.stride, pose_model, detection_model, args.report_dir, args.baseline_dir
    )

    summary = json.loads(baseline_path.read_text())
    agg = summary["aggregate"]
    print(f"\nBaseline written to: {baseline_path}")
    print(
        f"  person: {agg['person_detection_rate']:.1%}  "
        f"racket: {agg['racket_detection_rate']:.1%}  "
        f"ball: {agg['ball_detection_rate']:.1%}"
    )
    print(
        f"  avg pose FPS: {agg['avg_pose_fps'] or 0:.1f}  "
        f"avg detection FPS: {agg['avg_detection_fps'] or 0:.1f}"
    )


if __name__ == "__main__":
    main()
