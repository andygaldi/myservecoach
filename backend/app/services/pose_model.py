import os
from functools import lru_cache

import cv2
import numpy as np
from rtmlib import Body

from app.models import Keypoint


def decode_image(raw: bytes) -> np.ndarray | None:
    """Decode raw JPEG/PNG bytes into a BGR image array, or None if invalid."""
    return cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)

COCO17_KEYPOINT_NAMES: list[str] = [
    "nose",
    "left_eye",
    "right_eye",
    "left_ear",
    "right_ear",
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
]

_FACE_KEYPOINTS = {"nose", "left_eye", "right_eye", "left_ear", "right_ear"}


def _midpoint_keypoint(a: Keypoint, b: Keypoint) -> Keypoint:
    return Keypoint(x=(a.x + b.x) / 2, y=(a.y + b.y) / 2, confidence=min(a.confidence, b.confidence))


def map_coco17_to_backend_schema(
    keypoints: np.ndarray, scores: np.ndarray, width: int, height: int
) -> dict[str, Keypoint]:
    """Map a single person's COCO-17 keypoints/scores to the backend keypoint schema.

    Normalizes pixel coordinates to 0-1 and derives neck/pelvis as shoulder/hip
    midpoints, since RTMPose's COCO-17 output has no equivalent to Vision's
    neck_joint/root_joint. RTMPose's pixel coordinates come from OpenCV-decoded
    images (origin top-left, y increasing downward); Vision's normalized points
    use the opposite convention (origin bottom-left, y increasing upward — see
    VNRecognizedPoint). The y-axis is flipped here so both keypoint sources agree
    on the convention angles.py/phases.py were built against.
    """
    result: dict[str, Keypoint] = {}
    for name, (x, y), score in zip(COCO17_KEYPOINT_NAMES, keypoints, scores):
        if name in _FACE_KEYPOINTS:
            continue
        result[name] = Keypoint(x=float(x) / width, y=1.0 - (float(y) / height), confidence=float(score))

    if "left_shoulder" in result and "right_shoulder" in result:
        result["neck"] = _midpoint_keypoint(result["left_shoulder"], result["right_shoulder"])
    if "left_hip" in result and "right_hip" in result:
        result["pelvis"] = _midpoint_keypoint(result["left_hip"], result["right_hip"])

    return result


class RTMPoseModel:
    """Wraps rtmlib.Body for 2D pose inference, lazily loading the ONNX model."""

    def __init__(self, device: str | None = None, backend: str = "onnxruntime"):
        self.device = device or os.environ.get("POSE_MODEL_DEVICE", "cpu")
        self.backend = backend
        self._body: Body | None = None

    def infer(self, image: np.ndarray) -> dict[str, Keypoint]:
        if self._body is None:
            self._body = Body(backend=self.backend, device=self.device)
        keypoints, scores = self._body(image)
        if len(keypoints) == 0:
            return {}
        h, w = image.shape[:2]
        return map_coco17_to_backend_schema(keypoints[0], scores[0], w, h)


@lru_cache(maxsize=1)
def get_pose_model() -> RTMPoseModel:
    return RTMPoseModel()
