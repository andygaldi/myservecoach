from pathlib import Path

import cv2
import numpy as np


def sample_video_frames(video_path: Path, stride: int) -> list[tuple[float, np.ndarray]]:
    """Read every `stride`-th frame from *video_path* as (timestamp, image) pairs."""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise ValueError(f"could not open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    sampled: list[tuple[float, np.ndarray]] = []
    idx = 0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if idx % stride == 0:
                sampled.append((idx / fps, frame.copy()))
            idx += 1
    finally:
        cap.release()

    return sampled


def video_duration_seconds(video_path: Path) -> float:
    """True wall-clock duration of *video_path* (frame_count / fps), independent of any
    stride-based sampling. A chunked session's cross-chunk clock must offset by each chunk's
    real duration, not an approximation from sampled-frame count — see
    goal_session_buffer.append_chunk.
    """
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise ValueError(f"could not open video: {video_path}")

    try:
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
        return frame_count / fps if fps else 0.0
    finally:
        cap.release()
