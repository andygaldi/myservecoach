import os

import numpy as np
import pytest

from app.services.object_detection import ObjectDetectionModel


@pytest.mark.skipif(
    not os.environ.get("RUN_MODEL_INTEGRATION_TESTS"),
    reason="opt-in: downloads real YOLO11n COCO weights on first run",
)
def test_real_yolo_inference_runs():
    model = ObjectDetectionModel()
    image = np.zeros((480, 640, 3), dtype=np.uint8)
    result = model.infer(image)
    assert isinstance(result, list)
    # No racket/ball in a blank synthetic image, so an empty list is an
    # acceptable (and expected) result here — the assertion is that inference
    # ran without raising, not that anything was detected.
