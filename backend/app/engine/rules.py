import json
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, model_validator

from app.models import Cue, Detection, Frame, ServePhase, Severity
from app.engine.angles import (
    compute_angle,
    joint_xy,
    keypoint_x,
    keypoint_y,
    segment_angle_from_vertical,
    MIN_CONFIDENCE,
)
from app.engine.phases import bbox_center

_RULES_PATH = Path(__file__).parent.parent.parent / "rules.json"


class _Rule(BaseModel):
    id: str
    phase: ServePhase
    metric: Literal["y_diff", "x_diff", "angle", "angle_from_vertical", "ball_offset_x", "ball_offset_y"]
    joints: list[str]
    comparison: Literal["gte", "lte", "range"]
    threshold: float | None = None
    threshold_min: float | None = None
    threshold_max: float | None = None
    severity: Severity
    message: str
    # Not a Literal like `metric`/`comparison`: P15 will add a "behind_server" view without
    # needing to touch this model again. A typo'd view in rules.json loads as a distinct,
    # permanently-unmatched value rather than failing validation at import.
    view: str = "open_side"

    @model_validator(mode="after")
    def _validate_thresholds(self) -> "_Rule":
        if self.comparison in ("gte", "lte") and self.threshold is None:
            raise ValueError(
                f"Rule '{self.id}': 'threshold' is required for comparison '{self.comparison}'"
            )
        if self.comparison == "range" and (
            self.threshold_min is None or self.threshold_max is None
        ):
            raise ValueError(
                f"Rule '{self.id}': 'threshold_min' and 'threshold_max' are required for comparison 'range'"
            )
        return self


_RULES: list[_Rule] = [_Rule(**r) for r in json.loads(_RULES_PATH.read_text())["rules"]]


def compute_metric_value(
    frame: Frame, metric: str, joints: list[str], detections: list[Detection] | None = None
) -> float | None:
    """Compute a rule metric's raw value for `frame`, or None if inputs are unavailable.

    Shared by `evaluate_rules` (reads `rule.metric`/`rule.joints`) and
    `tools/analyze_angles.py` (reads its own candidate metric specs) so calibration math and
    runtime rule-evaluation math stay identical by construction.
    """
    if metric == "y_diff":
        y0 = keypoint_y(frame, joints[0])
        y1 = keypoint_y(frame, joints[1])
        if y0 is None or y1 is None:
            return None
        return y0 - y1
    if metric == "x_diff":
        x0 = keypoint_x(frame, joints[0])
        x1 = keypoint_x(frame, joints[1])
        if x0 is None or x1 is None:
            return None
        return x0 - x1
    if metric == "angle":
        a = joint_xy(frame, joints[0])
        b = joint_xy(frame, joints[1])
        c = joint_xy(frame, joints[2])
        if a is None or b is None or c is None:
            return None
        return compute_angle(a, b, c)
    if metric == "angle_from_vertical":
        return segment_angle_from_vertical(frame, joints[0], joints[1])
    if metric in ("ball_offset_x", "ball_offset_y"):
        if not detections:
            return None
        ball = next((d for d in detections if d.label == "ball"), None)
        if ball is None:
            return None
        ball_x, ball_y = bbox_center(ball.bbox)
        joint = joint_xy(frame, joints[0])
        if joint is None:
            return None
        return (ball_x - joint[0]) if metric == "ball_offset_x" else (ball_y - joint[1])
    raise AssertionError(f"unreachable metric: {metric!r}")


def _passes(value: float, rule: _Rule) -> bool:
    if rule.comparison == "gte":
        return value >= rule.threshold  # type: ignore[operator]
    if rule.comparison == "lte":
        return value <= rule.threshold  # type: ignore[operator]
    if rule.comparison == "range":
        return rule.threshold_min <= value <= rule.threshold_max  # type: ignore[operator]
    raise AssertionError(f"unreachable comparison: {rule.comparison!r}")


def evaluate_rules(
    phase_frames: dict[ServePhase, Frame | None],
    phase_detections: dict[ServePhase, list[Detection] | None] | None = None,
    view: str = "open_side",
) -> list[Cue]:
    phase_detections = phase_detections or {}
    cues = []
    for rule in _RULES:
        if rule.view != view:
            continue
        frame = phase_frames.get(rule.phase)
        if frame is None:
            continue
        detections = phase_detections.get(rule.phase)
        value = compute_metric_value(frame, rule.metric, rule.joints, detections)
        if value is None:
            continue
        if not _passes(value, rule):
            cues.append(Cue(
                rule_id=rule.id,
                phase=rule.phase,
                message=rule.message,
                severity=rule.severity,
                metric=rule.metric,
                joints=rule.joints,
                measured_value=value,
                comparison=rule.comparison,
                threshold=rule.threshold,
                threshold_min=rule.threshold_min,
                threshold_max=rule.threshold_max,
            ))
    return cues
