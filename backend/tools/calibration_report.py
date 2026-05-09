#!/usr/bin/env python3
"""
calibration_report.py — Developer tool for visual phase-detection calibration.

Parses the keypoint JSON logged to the Xcode console by PoseAnalysisPipeline,
extracts the corresponding frames from the video file, runs phase detection, and
writes a static HTML report so you can visually verify that trophy pose, racket
drop, and contact point land on the correct frames.

Usage:
    python backend/tools/calibration_report.py \\
        --keypoints path/to/console_output.txt \\
        --video     path/to/serve_clip.mov \\
        --output    path/to/report_dir

The report directory is created if it does not exist.  Output:
    <output>/report.html          — open in any browser
    <output>/frames/              — extracted JPEG frames
"""

import argparse
import json
import re
import sys
from pathlib import Path

import cv2

# Allow running from the repo root or from inside backend/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.engine.phases import detect_phases
from app.models import Frame, Keypoint


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

_SERVE_HEADER = re.compile(r"\[MyServeCoach\] Serve \d+/\d+ .* frames")


def parse_console_log(path: Path) -> list[list[dict]]:
    """Parse Xcode console output into a list of serves, each a list of frame dicts.

    The log format produced by PoseAnalysisPipeline.logSegments() is:
        [MyServeCoach] Serve 1/2 — 45 frames
        { "joints": { ... }, "timestamp": 0.0 }
        ...
        [MyServeCoach] Serve 2/2 — 38 frames
        ...
    """
    text = path.read_text(encoding="utf-8")
    serves: list[list[dict]] = []
    current: str | None = None

    for line in text.splitlines():
        if _SERVE_HEADER.search(line):
            if current is not None:
                serves.append(_extract_json_objects(current))
            current = ""
        elif current is not None:
            current += line + "\n"

    if current:
        serves.append(_extract_json_objects(current))

    return [s for s in serves if s]  # drop empty segments


def _extract_json_objects(text: str) -> list[dict]:
    """Extract all top-level JSON objects from a block of text that may contain non-JSON lines."""
    objects: list[dict] = []
    depth = 0
    start: int | None = None
    in_string = False
    escape_next = False

    for i, ch in enumerate(text):
        if escape_next:
            escape_next = False
            continue
        if ch == "\\" and in_string:
            escape_next = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    objects.append(json.loads(text[start : i + 1]))
                except json.JSONDecodeError:
                    pass
                start = None

    return objects


# ---------------------------------------------------------------------------
# Joint name translation
# ---------------------------------------------------------------------------

def _normalize_joint_name(vision_name: str) -> str:
    """Translate a Vision framework joint name to the backend's simplified name.

    Examples:
        "left_wrist_joint"      → "left_wrist"
        "left_shoulder_1_joint" → "left_shoulder"
        "left_elbow_1_joint"    → "left_elbow"
        "left_upLeg_joint"      → "left_hip"
        "right_upLeg_joint"     → "right_hip"
    """
    name = vision_name
    name = re.sub(r"_1_joint$", "", name)   # shoulder_1_joint, elbow_1_joint, neck_1_joint
    name = re.sub(r"_joint$", "", name)      # wrist_joint, knee_joint, etc.
    name = name.replace("upLeg", "hip")      # upLeg → hip
    return name


def normalize_joints(ios_joints: dict) -> dict:
    """Remap a PoseFrame 'joints' dict (Vision names) to backend keypoint names."""
    return {_normalize_joint_name(k): v for k, v in ios_joints.items()}


# ---------------------------------------------------------------------------
# Model conversion
# ---------------------------------------------------------------------------

def to_backend_frame(frame_dict: dict) -> Frame:
    """Convert an iOS PoseFrame dict to a backend Frame model."""
    normalized = normalize_joints(frame_dict["joints"])
    keypoints = {
        name: Keypoint(x=jt["x"], y=jt["y"], confidence=jt["confidence"])
        for name, jt in normalized.items()
    }
    return Frame(timestamp=frame_dict["timestamp"], keypoints=keypoints)


# ---------------------------------------------------------------------------
# Video frame extraction
# ---------------------------------------------------------------------------

def extract_video_frame(
    cap: cv2.VideoCapture, fps: float, timestamp: float, out_path: Path
) -> bool:
    """Seek to *timestamp* seconds and write a JPEG.  Returns True on success."""
    frame_idx = int(round(timestamp * fps))
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ok, img = cap.read()
    if not ok:
        return False
    cv2.imwrite(str(out_path), img, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return True


# ---------------------------------------------------------------------------
# HTML generation
# ---------------------------------------------------------------------------

_PHASE_LABELS = {
    "trophy_pose": "Trophy Pose",
    "racket_drop": "Racket Drop",
    "contact": "Contact Point",
}

_PHASE_BORDER = "#e44"
_STRIP_HIGHLIGHT_BORDER = "#f90"


def _img_tag(rel_path: str, width: int, border_color: str = "", label: str = "") -> str:
    style = f"width:{width}px;margin:4px;"
    if border_color:
        style += f"border:3px solid {border_color};box-sizing:border-box;"
    caption = (
        f"<div style='font-size:11px;font-weight:bold;text-align:center;"
        f"color:{border_color or '#555'}'>{label}</div>"
        if label
        else ""
    )
    return (
        f"<div style='display:inline-block;vertical-align:top;text-align:center'>"
        f"<img src='{rel_path}' style='{style}'>{caption}</div>"
    )


def generate_html(
    serves: list[list[dict]],
    phase_frame_indices: list[dict[str, int | None]],
    frames_dir: Path,
    output_dir: Path,
) -> Path:
    """Write report.html and return its path."""
    sections: list[str] = []

    for i, (serve_dicts, phases) in enumerate(zip(serves, phase_frame_indices)):
        serve_num = i + 1
        phase_idx_set = {v for v in phases.values() if v is not None}

        # All-frames thumbnail strip
        strip_parts: list[str] = []
        for j in range(len(serve_dicts)):
            img_path = frames_dir / f"serve{serve_num}_frame{j:03d}.jpg"
            if img_path.exists():
                rel = str(img_path.relative_to(output_dir))
                border = _STRIP_HIGHLIGHT_BORDER if j in phase_idx_set else ""
                strip_parts.append(_img_tag(rel, width=100, border_color=border))
        strip_html = "".join(strip_parts) or "<em>No frames extracted.</em>"

        # Phase highlight row
        highlight_parts: list[str] = []
        for key, label in _PHASE_LABELS.items():
            idx = phases.get(key)
            if idx is not None:
                img_path = frames_dir / f"serve{serve_num}_frame{idx:03d}.jpg"
                rel = str(img_path.relative_to(output_dir))
                highlight_parts.append(
                    _img_tag(rel, width=240, border_color=_PHASE_BORDER, label=label)
                )
            else:
                highlight_parts.append(
                    f"<div style='display:inline-block;width:240px;margin:4px;"
                    f"text-align:center;color:#999;vertical-align:top'>"
                    f"<div style='height:135px;background:#f4f4f4;line-height:135px'>"
                    f"(not detected)</div>"
                    f"<div style='font-size:11px;font-weight:bold'>{label}</div></div>"
                )
        highlight_html = "".join(highlight_parts)

        sections.append(
            f"<section>\n"
            f"  <h2>Serve {serve_num} <small>({len(serve_dicts)} frames)</small></h2>\n"
            f"  <h3>All Frames</h3>\n"
            f"  <div style='overflow-x:auto;white-space:nowrap;padding:4px 0'>{strip_html}</div>\n"
            f"  <h3>Phase Frames</h3>\n"
            f"  <div style='white-space:nowrap'>{highlight_html}</div>\n"
            f"</section>\n"
        )

    body = "\n".join(sections) or "<p>No serves found.</p>"

    html = (
        "<!DOCTYPE html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '  <meta charset="utf-8">\n'
        "  <title>Serve Calibration Report</title>\n"
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
        "  <h1>Serve Calibration Report</h1>\n"
        f"{body}"
        "</body>\n"
        "</html>\n"
    )

    report_path = output_dir / "report.html"
    report_path.write_text(html, encoding="utf-8")
    return report_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a calibration report from a keypoint log and video file."
    )
    parser.add_argument("--keypoints", required=True, type=Path,
                        help="Path to Xcode console output containing keypoint JSON.")
    parser.add_argument("--video", required=True, type=Path,
                        help="Path to the serve video file.")
    parser.add_argument("--output", required=True, type=Path,
                        help="Directory to write report.html and frames/.")
    args = parser.parse_args()

    if not args.keypoints.exists():
        sys.exit(f"error: keypoints file not found: {args.keypoints}")
    if not args.video.exists():
        sys.exit(f"error: video file not found: {args.video}")

    args.output.mkdir(parents=True, exist_ok=True)
    frames_dir = args.output / "frames"
    frames_dir.mkdir(exist_ok=True)

    print(f"Parsing {args.keypoints} …")
    serves = parse_console_log(args.keypoints)
    if not serves:
        sys.exit("error: no serves found in keypoint log.")
    print(f"Found {len(serves)} serve(s).")

    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        sys.exit(f"error: could not open video: {args.video}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"Video: {fps:.2f} fps, {total_frames} total frames")

    phase_frame_indices: list[dict[str, int | None]] = []

    for i, serve_dicts in enumerate(serves):
        serve_num = i + 1
        print(f"  Serve {serve_num}/{len(serves)}: {len(serve_dicts)} frames …")

        # Detect phases using backend logic.
        backend_frames = [to_backend_frame(d) for d in serve_dicts]
        phases = detect_phases(backend_frames)

        # Map each detected phase Frame back to its index within this serve.
        phase_idxs: dict[str, int | None] = {}
        for phase, frame in phases.items():
            if frame is None:
                phase_idxs[phase.value] = None
                continue
            matches = [
                j for j, d in enumerate(serve_dicts)
                if abs(d["timestamp"] - frame.timestamp) < 1e-9
            ]
            phase_idxs[phase.value] = matches[0] if matches else None

        phase_frame_indices.append(phase_idxs)

        # Extract one JPEG per sampled frame.
        for j, frame_dict in enumerate(serve_dicts):
            out_path = frames_dir / f"serve{serve_num}_frame{j:03d}.jpg"
            ts = frame_dict["timestamp"]
            if not extract_video_frame(cap, fps, ts, out_path):
                print(f"    warning: could not extract frame at t={ts:.3f}s")

        detected = [k for k, v in phase_idxs.items() if v is not None]
        print(f"    phases detected: {detected or ['none']}")

    cap.release()

    report_path = generate_html(serves, phase_frame_indices, frames_dir, args.output)
    print(f"\nReport written to: {report_path}")


if __name__ == "__main__":
    main()
