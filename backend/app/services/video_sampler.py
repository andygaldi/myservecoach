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
