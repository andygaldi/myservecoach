import os
from functools import lru_cache

import numpy as np
from ultralytics import YOLO

from app.models import BoundingBox, Detection

DETECTION_CLASS_MAP: dict[int, str] = {
    32: "ball",  # COCO "sports ball"
    38: "racket",  # COCO "tennis racket"
}


def map_yolo_results_to_detections(
    boxes, width: int, height: int, confidence_threshold: float
) -> list[Detection]:
    """Map a single frame's YOLO `Boxes` result to the backend detection schema.

    Filters to only the racket/ball classes and the given confidence threshold,
    normalizes pixel coordinates to 0-1, and y-flips them to match the Vision-derived
    convention (origin bottom-left, y increasing upward) that `map_coco17_to_backend_schema`
    established for pose keypoints, so detection and pose signals share one coordinate
    system when P4 combines them. The y-flip inverts which raw coordinate is smaller, so
    the flipped min/max are re-sorted to preserve the y_min < y_max invariant.
    """
    detections: list[Detection] = []
    for cls, conf, xyxy in zip(boxes.cls, boxes.conf, boxes.xyxy):
        class_id = int(cls)
        if class_id not in DETECTION_CLASS_MAP:
            continue
        confidence = float(conf)
        if confidence < confidence_threshold:
            continue

        x_min, y_min, x_max, y_max = (float(v) for v in xyxy)
        flipped_y_min = 1.0 - (y_max / height)
        flipped_y_max = 1.0 - (y_min / height)

        detections.append(
            Detection(
                label=DETECTION_CLASS_MAP[class_id],
                confidence=confidence,
                bbox=BoundingBox(
                    x_min=x_min / width,
                    y_min=flipped_y_min,
                    x_max=x_max / width,
                    y_max=flipped_y_max,
                ),
            )
        )
    return detections


class ObjectDetectionModel:
    """Wraps ultralytics.YOLO for racket/ball detection, lazily loading the model."""

    def __init__(
        self,
        device: str | None = None,
        weights: str = "yolo11n.pt",
        confidence_threshold: float = 0.25,
    ):
        self.device = device or os.environ.get("DETECTION_MODEL_DEVICE", "cpu")
        self.weights = weights
        self.confidence_threshold = confidence_threshold
        self._model: YOLO | None = None

    def infer(self, image: np.ndarray) -> list[Detection]:
        if self._model is None:
            self._model = YOLO(self.weights)
        results = self._model.predict(
            image, device=self.device, conf=self.confidence_threshold, verbose=False
        )
        h, w = image.shape[:2]
        return map_yolo_results_to_detections(results[0].boxes, w, h, self.confidence_threshold)


@lru_cache(maxsize=1)
def get_object_detection_model() -> ObjectDetectionModel:
    return ObjectDetectionModel()
