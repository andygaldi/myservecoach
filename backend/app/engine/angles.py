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


def knee_flexion_angle(frame: Frame, side: str) -> float | None:
    """Angle in degrees at the `side` knee (hip->knee->ankle). A straight leg is close to 180°;
    smaller angles indicate a more deeply bent (flexed) knee."""
    hip_xy = joint_xy(frame, f"{side}_hip")
    knee_xy = joint_xy(frame, f"{side}_knee")
    ankle_xy = joint_xy(frame, f"{side}_ankle")
    if hip_xy is None or knee_xy is None or ankle_xy is None:
        return None
    return compute_angle(hip_xy, knee_xy, ankle_xy)


def max_knee_flexion_angle(frame: Frame) -> float | None:
    """The more-flexed (smaller-angle) of the two knees this frame, or whichever side resolves
    if only one has confident keypoints; None if neither does."""
    angles = [a for a in (knee_flexion_angle(frame, "left"), knee_flexion_angle(frame, "right")) if a is not None]
    return min(angles) if angles else None


def hip_height(frame: Frame, side: str) -> float | None:
    """Normalized y-coordinate of the hip/pelvis: prefers the derived `pelvis` midpoint (more
    stable than a single hip keypoint) with a `side`-hip fallback when pelvis is unavailable."""
    pelvis_y = keypoint_y(frame, "pelvis")
    if pelvis_y is not None:
        return pelvis_y
    return keypoint_y(frame, f"{side}_hip")


def arm_straightness_angle(frame: Frame, side: str) -> float | None:
    """Angle in degrees at the `side` elbow (shoulder->elbow->wrist). A fully extended (straight)
    arm is close to 180°; a bent arm is smaller."""
    shoulder_xy = joint_xy(frame, f"{side}_shoulder")
    elbow_xy = joint_xy(frame, f"{side}_elbow")
    wrist_xy = joint_xy(frame, f"{side}_wrist")
    if shoulder_xy is None or elbow_xy is None or wrist_xy is None:
        return None
    return compute_angle(shoulder_xy, elbow_xy, wrist_xy)


def forearm_angle_from_vertical(frame: Frame, side: str) -> float | None:
    """Angle in degrees between the `side` forearm (elbow->wrist) and straight-up vertical.

    A 2D proxy for shoulder external rotation: 2D keypoints can't measure the humerus's axial
    rotation directly, but as the arm cocks into the "back-scratch" position the forearm visibly
    swings from pointing up (near release/trophy) to pointing down and behind the body (fully
    cocked) — so this angle grows toward 180° at maximum external rotation and shrinks again as
    the arm extends upward into contact.
    """
    elbow_xy = joint_xy(frame, f"{side}_elbow")
    wrist_xy = joint_xy(frame, f"{side}_wrist")
    if elbow_xy is None or wrist_xy is None:
        return None
    straight_up = (elbow_xy[0], elbow_xy[1] + 1.0)
    return compute_angle(straight_up, elbow_xy, wrist_xy)
