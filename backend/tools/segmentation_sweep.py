#!/usr/bin/env python3
"""Caches pose/detection inference per corpus video so parameter sweeps over the peak-counting
constants (HITTING_WRIST_FLOOR_K, MIN_PEAK_SEPARATION_SECONDS) run in seconds instead of minutes
of CPU per guess.

Usage:
    python backend/tools/segmentation_sweep.py \\
        --floor-k        0.1,0.15,0.2 \\
        --min-separation 0.4,0.6,0.8
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

from pydantic import BaseModel

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.engine.phases import segment_serves
from app.models import Detection, Frame
from app.services.object_detection import get_object_detection_model
from app.services.pose_model import get_pose_model
from tools.pose_benchmark import _TOOLS_DIR
from tools.segmentation_report import DEFAULT_SCORE_STRIDE, build_frame_sequence


class CachedVideoFrames(BaseModel):
    frames: list[Frame]
    detections: list[list[Detection]]


def cache_path_for(video_path: Path, cache_dir: Path) -> Path:
    """One JSON file per video, keyed by stem + a hash of its mtime/size so a re-recorded clip
    (different mtime/size, same filename) invalidates its stale cache automatically rather than
    silently reusing old inference."""
    stat = video_path.stat()
    digest = hashlib.sha1(f"{stat.st_mtime_ns}:{stat.st_size}".encode()).hexdigest()[:16]
    return cache_dir / f"{video_path.stem}_{digest}.json"


def load_or_build_cache(
    video_path: Path, cache_dir: Path, stride: int, pose_model, detection_model
) -> CachedVideoFrames:
    cache_dir.mkdir(parents=True, exist_ok=True)
    path = cache_path_for(video_path, cache_dir)
    if path.exists():
        return CachedVideoFrames.model_validate_json(path.read_text())

    frames, detections, _images = build_frame_sequence(video_path, stride, pose_model, detection_model)
    cached = CachedVideoFrames(frames=frames, detections=detections)
    path.write_text(cached.model_dump_json())
    return cached


def sweep(
    video_paths: list[Path],
    ground_truth: dict,
    floor_k_values: list[float],
    min_separation_values: list[float],
    cache_dir: Path,
    pose_model,
    detection_model,
) -> list[dict]:
    """Score every (floor_k, min_peak_separation_seconds) combination against non-held-out
    ground-truth entries only, using cached frames so repeated combinations cost no re-inference.
    Returns [{floor_k, min_peak_separation_seconds, matches, total}] sorted best-first."""
    scoring_videos: list[tuple[dict, CachedVideoFrames]] = []
    for video_name, entry in ground_truth["videos"].items():
        if entry.get("held_out", False):
            continue
        video_path = _TOOLS_DIR / "calibration_data" / video_name
        if video_path not in video_paths:
            continue
        cached = load_or_build_cache(video_path, cache_dir, DEFAULT_SCORE_STRIDE, pose_model, detection_model)
        scoring_videos.append((entry, cached))

    results: list[dict] = []
    for floor_k in floor_k_values:
        for min_separation in min_separation_values:
            matches = 0
            for entry, cached in scoring_videos:
                actual_count = len(
                    segment_serves(
                        cached.frames,
                        floor_k=floor_k,
                        min_peak_separation_seconds=min_separation,
                    )
                )
                if actual_count == entry["expected_count"]:
                    matches += 1
            results.append(
                {
                    "floor_k": floor_k,
                    "min_peak_separation_seconds": min_separation,
                    "matches": matches,
                    "total": len(scoring_videos),
                }
            )

    results.sort(key=lambda r: r["matches"], reverse=True)
    return results


def _parse_float_list(raw: str) -> list[float]:
    return [float(v) for v in raw.split(",")]


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Sweep segment_serves' peak-counting constants against cached corpus inference."
    )
    parser.add_argument(
        "--videos", default=None,
        help="Glob pattern for input videos (defaults to every video listed in --ground-truth).",
    )
    parser.add_argument(
        "--ground-truth", type=Path, default=_TOOLS_DIR / "segmentation_count_ground_truth.json",
        help="Path to the count ground-truth JSON.",
    )
    parser.add_argument(
        "--cache-dir", type=Path, default=_TOOLS_DIR / "calibration_data" / ".keypoint_cache",
        help="Directory for cached per-video inference results.",
    )
    parser.add_argument("--floor-k", type=str, required=True, help="Comma-separated floor_k values.")
    parser.add_argument(
        "--min-separation", type=str, required=True,
        help="Comma-separated min_peak_separation_seconds values.",
    )
    return parser


def main() -> None:
    parser = _build_arg_parser()
    args = parser.parse_args()

    ground_truth = json.loads(args.ground_truth.read_text())

    if args.videos is not None:
        from tools.pose_benchmark import _resolve_videos

        video_paths = _resolve_videos(args.videos)
    else:
        candidate_paths = [_TOOLS_DIR / "calibration_data" / name for name in ground_truth["videos"]]
        video_paths = [p for p in candidate_paths if p.exists()]

    pose_model = get_pose_model()
    detection_model = get_object_detection_model()

    results = sweep(
        video_paths,
        ground_truth,
        _parse_float_list(args.floor_k),
        _parse_float_list(args.min_separation),
        args.cache_dir,
        pose_model,
        detection_model,
    )

    print(f"{'floor_k':>10} {'min_separation':>16} {'matches':>10}")
    for r in results:
        print(f"{r['floor_k']:>10} {r['min_peak_separation_seconds']:>16} {r['matches']:>7}/{r['total']}")


if __name__ == "__main__":
    main()
