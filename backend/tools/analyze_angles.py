#!/usr/bin/env python3
"""
analyze_angles.py — Developer tool for rule-threshold calibration (Phase P5).

Samples each of the 5 reference-serve videos, runs the real off-device pose model
(RTMPoseModel, Phase P1) and object detector (ObjectDetectionModel, Phase P2), locates the
sampled frame nearest each hand-labeled ground-truth timestamp
(backend/tools/segmentation_ground_truth.json), and computes every candidate rule metric
(app.engine.rules.compute_metric_value) at that frame. Prints a per-serve table plus
aggregate min/max/mean/stdev per metric — the basis for setting backend/rules.json's
thresholds by hand. Margins are chosen by inspection, not computed here — see
phases/2026-07-09-p5-rule-calibration-2d/requirements.md's Key Decisions.

Usage:
    python backend/tools/analyze_angles.py
    python backend/tools/analyze_angles.py --videos serve_2.mov serve_3.mov
"""

import argparse
import json
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path

# Allow running from the repo root or from inside backend/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.engine.rules import compute_metric_value
from app.models import Frame
from app.services.object_detection import get_object_detection_model
from app.services.pose_model import get_pose_model
from tools.pose_benchmark import _TOOLS_DIR
from tools.segmentation_report import build_frame_sequence


_DEFAULT_VIDEOS: list[str] = [
    "serve_2.mov",
    "serve_3.mov",
    "serve_4.mov",
    "vesa_slow_mo.mov",
    "alcaraz_serve_1.mov",
]

_DEFAULT_GROUND_TRUTH = _TOOLS_DIR / "segmentation_ground_truth.json"
_DEFAULT_CALIBRATION_DIR = _TOOLS_DIR / "calibration_data"

@dataclass(frozen=True)
class CandidateMetric:
    id: str
    phase: str
    metric: str
    joints: list[str]
    shape: str  # eventual comparison direction ("gte"/"lte"/"range") — a print_report hint only,
                # not used for computation.


# One entry per rule this phase calibrates — mirrors
# phases/2026-07-09-p5-rule-calibration-2d/requirements.md's rule table exactly.
_CANDIDATE_METRICS: list[CandidateMetric] = [
    CandidateMetric("release_toss_arm_straight", "release", "angle",
                     ["left_shoulder", "left_elbow", "left_wrist"], "gte"),
    CandidateMetric("release_toss_hand_eye_height", "release", "y_diff",
                     ["left_wrist", "nose"], "range"),
    CandidateMetric("trophy_hitting_elbow_shoulder_line", "trophy_pose", "angle",
                     ["left_shoulder", "right_shoulder", "right_elbow"], "range"),
    CandidateMetric("trophy_toss_arm_straight", "trophy_pose", "angle",
                     ["left_shoulder", "left_elbow", "left_wrist"], "gte"),
    CandidateMetric("trophy_toss_arm_vertical", "trophy_pose", "angle_from_vertical",
                     ["left_shoulder", "left_wrist"], "lte"),
    CandidateMetric("racket_drop_ball_height", "racket_drop", "ball_offset_y",
                     ["left_shoulder"], "range"),
    CandidateMetric("racket_drop_ball_front", "racket_drop", "ball_offset_x",
                     ["left_shoulder"], "range"),
    CandidateMetric("contact_left_hip_angle", "contact", "angle",
                     ["left_shoulder", "left_hip", "left_knee"], "range"),
    CandidateMetric("contact_shoulders_stacked", "contact", "x_diff",
                     ["right_shoulder", "left_shoulder"], "range"),
]


def nearest_frame(frames: list[Frame], target_ts: float) -> Frame:
    """The sampled frame whose timestamp is closest to `target_ts`."""
    return min(frames, key=lambda f: abs(f.timestamp - target_ts))


def measure_video(
    video_path: Path, ground_truth: dict, pose_model, detection_model, stride: int = 2
) -> dict[str, dict[str, float]]:
    """Sample `video_path`, run pose+detection, and measure every candidate metric at the
    sampled frame nearest each hand-labeled phase timestamp.

    Returns `{metric_id: {serve_label: value}}`, skipping a metric/serve pair when the value
    can't be computed (e.g. no ball detected in the nearest frame) rather than raising.
    """
    video_entries = ground_truth.get("videos", {}).get(video_path.name, [])
    if not video_entries:
        return {}

    frames, detections, _images = build_frame_sequence(video_path, stride, pose_model, detection_model)
    detections_by_ts = {frame.timestamp: dets for frame, dets in zip(frames, detections)}

    results: dict[str, dict[str, float]] = {metric.id: {} for metric in _CANDIDATE_METRICS}
    for serve_entry in video_entries:
        serve_label = f"{video_path.stem}#{serve_entry['serve_index']}"
        phases = serve_entry.get("phases", {})
        for metric in _CANDIDATE_METRICS:
            target_ts = phases.get(metric.phase)
            if target_ts is None:
                continue
            frame = nearest_frame(frames, target_ts)
            frame_detections = detections_by_ts.get(frame.timestamp)
            value = compute_metric_value(frame, metric.metric, metric.joints, frame_detections)
            if value is None:
                continue
            results[metric.id][serve_label] = value

    return results


def _merge_results(
    a: dict[str, dict[str, float]], b: dict[str, dict[str, float]]
) -> dict[str, dict[str, float]]:
    merged = {metric.id: dict(a.get(metric.id, {})) for metric in _CANDIDATE_METRICS}
    for metric_id, values in b.items():
        merged.setdefault(metric_id, {}).update(values)
    return merged


def print_report(results: dict[str, dict[str, float]]) -> None:
    """Print every serve's raw signed value per metric, plus aggregate stats and a
    suggested-threshold hint. Margins are chosen by inspection, not computed here.
    """
    for metric in _CANDIDATE_METRICS:
        values = results.get(metric.id, {})
        print(f"\n{metric.id} ({metric.metric}, phase={metric.phase})")
        if not values:
            print("  no values measured")
            continue
        for serve_label, value in values.items():
            print(f"  {serve_label}: {value:.4f}")
        raw = list(values.values())
        lo, hi = min(raw), max(raw)
        mean = statistics.mean(raw)
        spread = statistics.pstdev(raw)  # defined for n=1 (0.0), unlike statistics.stdev
        print(f"  min={lo:.4f} max={hi:.4f} mean={mean:.4f} stdev={spread:.4f}")
        if metric.shape == "gte":
            print(f"  suggested: gte, threshold <= {lo:.4f} (subtract your chosen margin)")
        elif metric.shape == "lte":
            print(f"  suggested: lte, threshold >= {hi:.4f} (add your chosen margin)")
        else:
            print(f"  suggested: range, [{lo:.4f}, {hi:.4f}] (widen by your chosen margin)")


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Measure candidate rule metrics against hand-labeled reference-serve phase frames."
    )
    parser.add_argument(
        "--videos", nargs="+", default=_DEFAULT_VIDEOS,
        help="Reference-serve video filenames (resolved under --calibration-dir).",
    )
    parser.add_argument(
        "--calibration-dir", type=Path, default=_DEFAULT_CALIBRATION_DIR,
        help="Directory containing the reference-serve video files.",
    )
    parser.add_argument(
        "--ground-truth", type=Path, default=_DEFAULT_GROUND_TRUTH,
        help="Path to segmentation_ground_truth.json.",
    )
    parser.add_argument("--stride", type=int, default=2, help="Sample every Nth video frame.")
    return parser


def main() -> None:
    parser = _build_arg_parser()
    args = parser.parse_args()

    ground_truth = json.loads(args.ground_truth.read_text())
    pose_model = get_pose_model()
    detection_model = get_object_detection_model()

    results: dict[str, dict[str, float]] = {}
    for video_name in args.videos:
        video_path = args.calibration_dir / video_name
        print(f"Measuring {video_path.name}...")
        video_results = measure_video(video_path, ground_truth, pose_model, detection_model, args.stride)
        results = _merge_results(results, video_results)

    print_report(results)


if __name__ == "__main__":
    main()
