import os

import numpy as np
import pytest

from app.services.pose_model import RTMPoseModel


@pytest.mark.skipif(
    not os.environ.get("RUN_MODEL_INTEGRATION_TESTS"),
    reason="opt-in: downloads real RTMPose ONNX weights on first run",
)
def test_real_rtmpose_inference_runs():
    model = RTMPoseModel()
    image = np.zeros((480, 640, 3), dtype=np.uint8)
    result = model.infer(image)
    assert isinstance(result, dict)
    # No person in a blank synthetic image, so an empty dict is an acceptable
    # (and expected) result here — the assertion is that inference ran without
    # raising, not that keypoints were found.
