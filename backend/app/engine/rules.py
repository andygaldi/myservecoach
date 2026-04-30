import json
from pathlib import Path

from app.models import Cue, Frame, ServePhase, Severity
from app.engine.angles import compute_angle, keypoint_y, MIN_CONFIDENCE

_RULES_PATH = Path(__file__).parent.parent.parent / "rules.json"
_RULES: list[dict] = json.loads(_RULES_PATH.read_text())["rules"]


def _joint_xy(frame: Frame, joint_name: str) -> tuple[float, float] | None:
    kp = frame.keypoints.get(joint_name)
    if kp is None or kp.confidence < MIN_CONFIDENCE:
        return None
    return (kp.x, kp.y)


def _compute_metric(frame: Frame, rule: dict) -> float | None:
    joints = rule["joints"]
    if rule["metric"] == "y_diff":
        y0 = keypoint_y(frame, joints[0])
        y1 = keypoint_y(frame, joints[1])
        if y0 is None or y1 is None:
            return None
        return y0 - y1
    if rule["metric"] == "angle":
        a = _joint_xy(frame, joints[0])
        b = _joint_xy(frame, joints[1])
        c = _joint_xy(frame, joints[2])
        if a is None or b is None or c is None:
            return None
        return compute_angle(a, b, c)
    return None


def _passes(value: float, rule: dict) -> bool:
    comparison = rule["comparison"]
    if comparison == "gte":
        return value >= rule["threshold"]
    if comparison == "lte":
        return value <= rule["threshold"]
    if comparison == "range":
        return rule["threshold_min"] <= value <= rule["threshold_max"]
    return True


def evaluate_rules(phase_frames: dict[ServePhase, Frame | None]) -> list[Cue]:
    cues = []
    for rule in _RULES:
        phase = ServePhase(rule["phase"])
        frame = phase_frames.get(phase)
        if frame is None:
            continue
        value = _compute_metric(frame, rule)
        if value is None:
            continue
        if not _passes(value, rule):
            cues.append(Cue(
                phase=phase,
                message=rule["message"],
                severity=Severity(rule["severity"]),
            ))
    return cues
