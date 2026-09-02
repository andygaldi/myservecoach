import os
from functools import lru_cache

import cv2
import numpy as np
from rtmlib import Body

from app.engine.angles import MIN_CONFIDENCE
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

_FACE_KEYPOINTS = {"left_eye", "right_eye", "left_ear", "right_ear"}


def _midpoint_keypoint(a: Keypoint, b: Keypoint) -> Keypoint:
    return Keypoint(x=(a.x + b.x) / 2, y=(a.y + b.y) / 2, confidence=min(a.confidence, b.confidence))


def _person_bbox_area(keypoints: np.ndarray, scores: np.ndarray) -> float:
    """Pixel-squared area spanning one detected person's confident keypoints.

    Used to pick the primary subject out of multiple people the detector finds in a frame — a
    server filmed courtside occupies far more of the frame than any background crowd member, so
    the largest-area person is a robust, cheap foreground filter for crowded real-match footage.
    """
    valid = scores >= MIN_CONFIDENCE
    if not valid.any():
        return 0.0
    xs, ys = keypoints[valid, 0], keypoints[valid, 1]
    return float((xs.max() - xs.min()) * (ys.max() - ys.min()))


def select_primary_person(keypoints: np.ndarray, scores: np.ndarray) -> int:
    """Index of the detected person most likely to be the tennis player, not a bystander.

    `keypoints`/`scores` are the per-person arrays rtmlib.Body returns (shape
    `(num_people, num_keypoints, ...)`); this picks the largest-bbox-area person, defaulting to
    index 0 if every person has zero confident keypoints (nothing to compare, so no change in
    behavior from before this existed).
    """
    return max(range(len(keypoints)), key=lambda i: _person_bbox_area(keypoints[i], scores[i]))


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
        self._pose = None  # standalone rtmlib.RTMPose, lazily loaded only for the fused path

    def infer(self, image: np.ndarray, person_bbox: list[float] | None = None) -> dict[str, Keypoint]:
        """Runs pose inference. With no `person_bbox`, behaves exactly as before (routes through
        `rtmlib.Body`, which runs its own YOLOX-m person detector). With a `person_bbox` (pixel
        xyxy, unflipped/unnormalized — see `ObjectDetectionModel.infer_with_person`), skips that
        redundant detector and feeds the box straight to a standalone `RTMPose` on the same
        checkpoint/input size `Body` uses — the fused path measured in `latency-findings.md`.
        """
        if person_bbox is not None:
            return self._infer_fused(image, person_bbox)
        if self._body is None:
            self._body = Body(backend=self.backend, device=self.device)
        keypoints, scores = self._body(image)
        if len(keypoints) == 0:
            return {}
        h, w = image.shape[:2]
        primary = select_primary_person(keypoints, scores)
        return map_coco17_to_backend_schema(keypoints[primary], scores[primary], w, h)

    def _infer_fused(self, image: np.ndarray, person_bbox: list[float]) -> dict[str, Keypoint]:
        if self._pose is None:
            from rtmlib import RTMPose

            # Resolve the exact pose checkpoint/input size Body would use, without paying for
            # its bundled YOLOX-m detector at inference time.
            reference = Body(backend=self.backend, device="cpu")
            self._pose = RTMPose(
                onnx_model=reference.pose_model.onnx_model,
                model_input_size=reference.pose_model.model_input_size,
                backend=self.backend,
                device=self.device,
            )
        keypoints, scores = self._pose(image, bboxes=[person_bbox])
        if len(keypoints) == 0:
            return {}
        h, w = image.shape[:2]
        primary = select_primary_person(keypoints, scores)
        return map_coco17_to_backend_schema(keypoints[primary], scores[primary], w, h)


@lru_cache(maxsize=1)
def get_pose_model() -> RTMPoseModel:
    return RTMPoseModel()
