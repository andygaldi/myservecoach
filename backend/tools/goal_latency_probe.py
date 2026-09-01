#!/usr/bin/env python3
"""
goal_latency_probe.py — Developer tool for Set Goal (P7) live-feedback latency.

Set Goal speaks a pass/fail cue while the player is still on court, so the backend must
consume short recorded chunks at least as fast as the camera produces them. This tool
measures the per-chunk cost of the full live path — sample -> pose -> detect ->
segment_serves -> phase detection + rule evaluation — across sampling strides, inference
devices, and two pose pipelines, and reports each configuration's realtime factor.

A realtime factor above 1.0 means the backend finishes a chunk faster than the camera
records it (no backlog). Below 1.0 the session falls further behind with every chunk and
live feedback is impossible regardless of segment-confirmation policy.

Two pipelines are compared:

  rtmlib  The pipeline as of P1/P2: rtmlib's Body() runs its own YOLOX-m person detector
          per frame and feeds RTMPose, while ObjectDetectionModel separately runs YOLO11n
          for racket/ball. Two detectors per frame.
  fused   YOLO11n runs once per frame and supplies both the racket/ball detections and the
          person bbox that RTMPose is fed directly, dropping YOLOX entirely. One detector
          per frame.

Usage:
    python backend/tools/goal_latency_probe.py \\
        --video   backend/tools/calibration_data/ag_three_serves.MOV \\
        --chunk-seconds 2 4 --strides 2 4 8 --devices cpu mps --pipelines rtmlib fused

Output:
    A per-configuration table on stdout, plus a JSON summary when --json is given.
"""

import argparse
import json
import sys
import time
from pathlib import Path

import cv2

# Allow running from the repo root or from inside backend/.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.engine.phases import detect_phases, segment_serves, slice_detections_by_segments
from app.engine.rules import evaluate_rules
from app.models import Frame
from app.services.object_detection import ObjectDetectionModel, map_yolo_results_to_detections
from app.services.pose_model import RTMPoseModel, map_coco17_to_backend_schema, select_primary_person

PERSON_CLASS_ID = 0  # COCO "person" — already computed by YOLO11n and discarded today.
GATE_REALTIME_FACTOR = 1.5


class RtmlibPipeline:
    """P1/P2's pipeline: rtmlib Body (YOLOX-m det + RTMPose) plus a separate YOLO11n pass."""

    name = "rtmlib"

    def __init__(self, device: str):
        self.pose_model = RTMPoseModel(device=device)
        self.detection_model = ObjectDetectionModel(device=device)

    def run(self, images: list) -> tuple[list[dict], list[list], float, float]:
        t0 = time.perf_counter()
        keypoints = [self.pose_model.infer(img) for img in images]
        t_pose = time.perf_counter() - t0

        t0 = time.perf_counter()
        detections = [self.detection_model.infer(img) for img in images]
        t_detect = time.perf_counter() - t0
        return keypoints, detections, t_pose, t_detect


class FusedPipeline:
    """One YOLO11n pass per frame supplies racket/ball detections *and* RTMPose's person bbox.

    RTMPose is loaded standalone (same ONNX checkpoint rtmlib.Body would have used) and fed
    the highest-confidence person box, so the model producing keypoints is unchanged — only
    the bounding box that crops the frame for it comes from a different detector.
    """

    name = "fused"

    def __init__(self, device: str):
        from rtmlib import RTMPose
        from rtmlib.tools.solution.body import Body

        # Resolve the exact pose checkpoint/input size Body would use, without paying for its
        # YOLOX detector at inference time.
        reference = Body(backend="onnxruntime", device="cpu")
        self.pose = RTMPose(
            onnx_model=reference.pose_model.onnx_model,
            model_input_size=reference.pose_model.model_input_size,
            backend="onnxruntime",
            device=device,
        )
        self.detection_model = ObjectDetectionModel(device=device)
        self.device = device

    def run(self, images: list) -> tuple[list[dict], list[list], float, float]:
        if self.detection_model._model is None:
            from ultralytics import YOLO

            self.detection_model._model = YOLO(self.detection_model.weights)
        model = self.detection_model._model

        t0 = time.perf_counter()
        raw = [
            model.predict(img, device=self.device, conf=self.detection_model.confidence_threshold, verbose=False)[0].boxes
            for img in images
        ]
        detections = []
        person_boxes = []
        for boxes, img in zip(raw, images):
            h, w = img.shape[:2]
            detections.append(
                map_yolo_results_to_detections(boxes, w, h, self.detection_model.confidence_threshold)
            )
            # Largest-area person, not highest-confidence — this must mirror
            # select_primary_person's "the server fills the frame, bystanders don't" rule
            # (pose_model.py:43-65). Picking by confidence instead lets a crisp background
            # figure win and silently swaps the tracked subject mid-clip.
            people = [
                [float(v) for v in xyxy]
                for cls, xyxy in zip(boxes.cls, boxes.xyxy)
                if int(cls) == PERSON_CLASS_ID
            ]
            best = max(people, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), default=None)
            person_boxes.append([best] if best is not None else [])
        t_detect = time.perf_counter() - t0

        t0 = time.perf_counter()
        keypoints = []
        for img, bbox in zip(images, person_boxes):
            h, w = img.shape[:2]
            if not bbox:
                keypoints.append({})
                continue
            kps, scores = self.pose(img, bboxes=bbox)
            if len(kps) == 0:
                keypoints.append({})
                continue
            primary = select_primary_person(kps, scores)
            keypoints.append(map_coco17_to_backend_schema(kps[primary], scores[primary], w, h))
        t_pose = time.perf_counter() - t0
        return keypoints, detections, t_pose, t_detect


PIPELINES = {"rtmlib": RtmlibPipeline, "fused": FusedPipeline}


def probe_chunk(frames_bgr: list, fps: float, stride: int, pipeline) -> dict:
    """Time one chunk's worth of the live Set Goal path at a given stride.

    Sampling happens here rather than via sample_video_frames so every configuration
    processes identical pixels and only the measured work differs.
    """
    sampled = [(i / fps, img) for i, img in enumerate(frames_bgr) if i % stride == 0]
    images = [img for _, img in sampled]

    keypoints, detections, t_pose, t_detect = pipeline.run(images)
    frames = [Frame(timestamp=ts, keypoints=kp) for (ts, _), kp in zip(sampled, keypoints)]

    t0 = time.perf_counter()
    segments = segment_serves(frames)
    seg_detections = slice_detections_by_segments(detections, segments)
    t_segment = time.perf_counter() - t0

    # Scoring is charged for one segment — the chunk endpoint scores only newly-confirmed
    # segments, which is zero or one per chunk in practice.
    t0 = time.perf_counter()
    if segments:
        phase_frames = detect_phases(segments[0], seg_detections[0])
        id_to_detections = {id(f): d for f, d in zip(segments[0], seg_detections[0] or [])}
        phase_detections = {
            phase: id_to_detections.get(id(frame))
            for phase, frame in phase_frames.items()
            if frame is not None
        }
        evaluate_rules(phase_frames, phase_detections)
    t_score = time.perf_counter() - t0

    total = t_pose + t_detect + t_segment + t_score
    return {
        "sampled_frames": len(sampled),
        "pose_seconds": t_pose,
        "detect_seconds": t_detect,
        "segment_seconds": t_segment,
        "score_seconds": t_score,
        "total_seconds": total,
    }


def decode_chunk(video_path: Path, chunk_seconds: float) -> tuple[list, float]:
    """Decode the first `chunk_seconds` of *video_path* into a list of BGR frames."""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise ValueError(f"could not open video: {video_path}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    wanted = int(round(fps * chunk_seconds))
    frames = []
    try:
        while len(frames) < wanted:
            ok, frame = cap.read()
            if not ok:
                break
            frames.append(frame.copy())
    finally:
        cap.release()
    return frames, fps


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--video", default="tools/calibration_data/ag_three_serves.MOV")
    parser.add_argument("--chunk-seconds", type=float, nargs="+", default=[2.0, 4.0])
    parser.add_argument("--strides", type=int, nargs="+", default=[2, 4])
    parser.add_argument("--devices", nargs="+", default=["cpu", "mps"])
    parser.add_argument("--pipelines", nargs="+", default=["rtmlib", "fused"], choices=list(PIPELINES))
    parser.add_argument("--warmup", type=int, default=3, help="warm-up inferences per config before timing")
    parser.add_argument("--json", type=Path, default=None)
    args = parser.parse_args()

    video_path = Path(args.video)
    if not video_path.exists():
        parser.error(f"video not found: {video_path}")

    chunks = {}
    fps = 30.0
    for seconds in args.chunk_seconds:
        frames, fps = decode_chunk(video_path, seconds)
        chunks[seconds] = frames
        print(f"decoded {len(frames)} frames for a {seconds:g}s chunk ({fps:.1f} fps source)")

    rows = []
    for pipeline_name in args.pipelines:
        for device in args.devices:
            label = f"{pipeline_name}/{device}"
            try:
                pipeline = PIPELINES[pipeline_name](device)
                warm = chunks[args.chunk_seconds[0]][: args.warmup]
                pipeline.run(warm)
            except Exception as exc:  # noqa: BLE001 — an unsupported EP is a result, not a crash
                print(f"\n=== {label}: UNSUPPORTED — {type(exc).__name__}: {str(exc)[:140]}")
                rows.append({"pipeline": pipeline_name, "device": device, "error": str(exc)[:200]})
                continue

            print(f"\n=== {label} ===", flush=True)
            for seconds in args.chunk_seconds:
                for stride in args.strides:
                    result = probe_chunk(chunks[seconds], fps, stride, pipeline)
                    result.update(pipeline=pipeline_name, device=device, chunk_seconds=seconds, stride=stride)
                    result["realtime_factor"] = seconds / result["total_seconds"]
                    rows.append(result)
                    print(
                        f"chunk={seconds:g}s stride={stride} frames={result['sampled_frames']:3d} "
                        f"pose={result['pose_seconds']:6.2f}s detect={result['detect_seconds']:5.2f}s "
                        f"segment={result['segment_seconds']:.3f}s score={result['score_seconds']:.3f}s "
                        f"total={result['total_seconds']:6.2f}s  realtime={result['realtime_factor']:6.2f}x "
                        f"{'OK' if result['realtime_factor'] >= GATE_REALTIME_FACTOR else 'TOO SLOW'}",
                        flush=True,
                    )

    print(f"\n--- summary (realtime factor; >= {GATE_REALTIME_FACTOR}x clears the P7 live-feedback gate) ---")
    print(f"{'pipeline':9}{'device':7}{'chunk':>6}{'stride':>7}{'total':>9}{'realtime':>10}")
    for row in rows:
        if "error" in row:
            print(f"{row['pipeline']:9}{row['device']:7}{'—':>6}{'—':>7}{'unsupported':>9}")
            continue
        print(
            f"{row['pipeline']:9}{row['device']:7}{row['chunk_seconds']:5g}s{row['stride']:7d}"
            f"{row['total_seconds']:8.2f}s{row['realtime_factor']:9.2f}x"
        )

    if args.json:
        args.json.write_text(json.dumps(rows, indent=2))
        print(f"\nwrote {args.json}")


if __name__ == "__main__":
    main()
