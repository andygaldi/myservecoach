#!/usr/bin/env python3
"""
segmentation_report.py — Developer tool for six-frame serve-phase segmentation validation.

Runs the real off-device pose model (RTMPoseModel, Phase P1) and object detector
(ObjectDetectionModel, Phase P2) directly against real serve footage, splits the
resulting frame/detection sequence into individual serves (segment_serves, Phase P4),
runs the six-frame Kovacs phase-detection heuristic (detect_phases, Phase P4) on each
detected serve, and writes a gitignored HTML report — one section per detected serve,
each showing all six phase frames — for visual spot-check and heuristic-constant tuning.

Usage:
    python backend/tools/segmentation_report.py \\
        --videos     "backend/tools/calibration_data/*.mov" \\
        --stride     5 \\
        --report-dir backend/tools/calibration_data

Output:
    <report-dir>/<video_stem>_segmentation/report.html   — open in any browser
    <report-dir>/<video_stem>_segmentation/frames/         — raw JPEG frames
"""

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np

# Allow running from the repo root or from inside backend/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.engine.phases import detect_phases, segment_serves
from app.models import Detection, Frame, ServePhase
from app.services.object_detection import get_object_detection_model
from app.services.pose_model import get_pose_model
from tools.calibration_report import _img_tag
from tools.pose_benchmark import _resolve_videos, _TOOLS_DIR, sample_video_frames


_PHASE_LABELS: dict[str, str] = {
    "start": "Start",
    "release": "Release (Toss)",
    "trophy_pose": "Loading (Trophy Pose)",
    "racket_drop": "Cocking (Racket Drop)",
    "contact": "Contact",
    "finish": "Finish",
}


def build_frame_sequence(
    video_path: Path, stride: int, pose_model, detection_model
) -> tuple[list[Frame], list[list[Detection]], list[np.ndarray]]:
    """Sample *video_path* and run the pose/detection models over every sampled frame."""
    frames: list[Frame] = []
    detections: list[list[Detection]] = []
    images: list[np.ndarray] = []

    for timestamp, image in sample_video_frames(video_path, stride):
        keypoints = pose_model.infer(image)
        frames.append(Frame(timestamp=timestamp, keypoints=keypoints))
        detections.append(detection_model.infer(image))
        images.append(image)

    return frames, detections, images


def generate_segmentation_html(
    video_name: str,
    serve_segments: list[list[Frame]],
    phase_results: list[dict[ServePhase, Frame | None]],
    frame_paths: dict[float, Path],
    output_dir: Path,
) -> Path:
    """Write <output_dir>/report.html: one section per detected serve segment."""
    sections: list[str] = []

    for serve_num, (segment_frames, phases) in enumerate(zip(serve_segments, phase_results), start=1):
        phase_timestamps = {frame.timestamp for frame in phases.values() if frame is not None}

        strip_parts: list[str] = []
        for frame in segment_frames:
            frame_path = frame_paths.get(frame.timestamp)
            if frame_path is None:
                continue
            rel = str(frame_path.relative_to(output_dir))
            border = "#f90" if frame.timestamp in phase_timestamps else ""
            strip_parts.append(_img_tag(rel, width=100, border_color=border))
        strip_html = "".join(strip_parts) or "<em>No frames extracted.</em>"

        highlight_parts: list[str] = []
        for phase_key, label in _PHASE_LABELS.items():
            frame = phases.get(ServePhase(phase_key))
            frame_path = frame_paths.get(frame.timestamp) if frame is not None else None
            if frame_path is not None:
                rel = str(frame_path.relative_to(output_dir))
                highlight_parts.append(_img_tag(rel, width=200, border_color="#e44", label=label))
            else:
                highlight_parts.append(
                    f"<div style='display:inline-block;width:200px;margin:4px;"
                    f"text-align:center;color:#999;vertical-align:top'>"
                    f"<div style='height:112px;background:#f4f4f4;line-height:112px'>"
                    f"(not detected)</div>"
                    f"<div style='font-size:11px;font-weight:bold'>{label}</div></div>"
                )
        highlight_html = "".join(highlight_parts)

        sections.append(
            f"<section>\n"
            f"  <h2>Serve {serve_num} <small>({len(segment_frames)} frames)</small></h2>\n"
            f"  <h3>All Frames</h3>\n"
            f"  <div style='overflow-x:auto;white-space:nowrap;padding:4px 0'>{strip_html}</div>\n"
            f"  <h3>Phase Frames</h3>\n"
            f"  <div style='white-space:nowrap'>{highlight_html}</div>\n"
            f"</section>\n"
        )

    body = "\n".join(sections) or "<p>No serves detected.</p>"

    html = (
        "<!DOCTYPE html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '  <meta charset="utf-8">\n'
        "  <title>Segmentation Report</title>\n"
        "  <style>\n"
        "    body{font-family:sans-serif;max-width:1400px;margin:0 auto;padding:16px}\n"
        "    h1{border-bottom:2px solid #333;padding-bottom:8px}\n"
        "    h2{color:#333;margin-bottom:4px}\n"
        "    small{font-weight:normal;color:#777}\n"
        "    h3{color:#666;font-size:13px;margin:12px 0 4px}\n"
        "    section{margin-bottom:40px;border-bottom:1px solid #ddd;padding-bottom:24px}\n"
        "  </style>\n"
        "</head>\n"
        "<body>\n"
        f"  <h1>{video_name} — Segmentation Report</h1>\n"
        f"{body}"
        "</body>\n"
        "</html>\n"
    )

    report_path = output_dir / "report.html"
    report_path.write_text(html, encoding="utf-8")
    return report_path


def run_segmentation_report(
    video_paths: list[Path], stride: int, pose_model, detection_model, report_root: Path
) -> list[Path]:
    """Run the full pipeline against every video and write one segmentation report each."""
    report_paths: list[Path] = []

    for video_path in video_paths:
        frames, detections, images = build_frame_sequence(video_path, stride, pose_model, detection_model)

        video_output_dir = report_root / f"{video_path.stem}_segmentation"
        frames_dir = video_output_dir / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)

        frame_paths: dict[float, Path] = {}
        for i, (frame, image) in enumerate(zip(frames, images)):
            frame_path = frames_dir / f"frame{i:03d}.jpg"
            cv2.imwrite(str(frame_path), image, [cv2.IMWRITE_JPEG_QUALITY, 85])
            frame_paths[frame.timestamp] = frame_path

        serve_segments = segment_serves(frames)

        # Slice the parallel detections list at the same boundaries segment_serves used for frames.
        serve_detections: list[list[list[Detection]]] = []
        cursor = 0
        for segment in serve_segments:
            serve_detections.append(detections[cursor : cursor + len(segment)])
            cursor += len(segment)

        phase_results = [
            detect_phases(segment, segment_dets)
            for segment, segment_dets in zip(serve_segments, serve_detections)
        ]

        report_path = generate_segmentation_html(
            video_path.stem, serve_segments, phase_results, frame_paths, video_output_dir
        )
        report_paths.append(report_path)
        print(f"  {video_path.name}: {len(serve_segments)} serve(s) detected -> {report_path}")

    return report_paths


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# _TOOLS_DIR and _resolve_videos are reused verbatim from pose_benchmark.py (both
# tools resolve videos from backend/tools/, matching both .mov and .MOV).


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run off-device serve segmentation + six-frame phase detection against real footage."
    )
    parser.add_argument(
        "--videos", default=str(_TOOLS_DIR / "calibration_data" / "*.mov"),
        help="Glob pattern for input videos (matches both .mov and .MOV).",
    )
    parser.add_argument("--stride", type=int, default=5, help="Sample every Nth video frame.")
    parser.add_argument(
        "--report-dir", type=Path, default=_TOOLS_DIR / "calibration_data",
        help="Parent directory under which each <video_stem>_segmentation/ report is written.",
    )
    args = parser.parse_args()

    video_paths = _resolve_videos(args.videos)
    if not video_paths:
        sys.exit(f"error: no videos matched pattern: {args.videos}")

    print(f"Found {len(video_paths)} video(s): {[p.name for p in video_paths]}")

    pose_model = get_pose_model()
    detection_model = get_object_detection_model()

    report_paths = run_segmentation_report(
        video_paths, args.stride, pose_model, detection_model, args.report_dir
    )

    print(f"\n{len(report_paths)} report(s) written under: {args.report_dir}")


if __name__ == "__main__":
    main()
