import math
from app.models import Frame

MIN_CONFIDENCE = 0.4


def compute_angle(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float | None:
    """Angle in degrees at joint b given three (x, y) points.

    Returns None for degenerate cases where one or both vectors have zero length.
    """
    ba = (a[0] - b[0], a[1] - b[1])
    bc = (c[0] - b[0], c[1] - b[1])
    dot = ba[0] * bc[0] + ba[1] * bc[1]
    mag_ba = math.hypot(*ba)
    mag_bc = math.hypot(*bc)
    if mag_ba == 0 or mag_bc == 0:
        return None
    cos_angle = max(-1.0, min(1.0, dot / (mag_ba * mag_bc)))
    return math.degrees(math.acos(cos_angle))


def joint_xy(frame: Frame, joint_name: str, min_confidence: float = MIN_CONFIDENCE) -> tuple[float, float] | None:
    """Normalized (x, y) coordinates of a joint, or None if below confidence threshold."""
    kp = frame.keypoints.get(joint_name)
    if kp is None or kp.confidence < min_confidence:
        return None
    return (kp.x, kp.y)


def keypoint_y(frame: Frame, joint_name: str, min_confidence: float = MIN_CONFIDENCE) -> float | None:
    """Normalized y-coordinate of a joint, or None if below confidence threshold."""
    kp = frame.keypoints.get(joint_name)
    if kp is None or kp.confidence < min_confidence:
        return None
    return kp.y
