import json
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, model_validator

from app.models import Cue, Frame, ServePhase, Severity
from app.engine.angles import compute_angle, joint_xy, keypoint_y, MIN_CONFIDENCE

_RULES_PATH = Path(__file__).parent.parent.parent / "rules.json"


class _Rule(BaseModel):
    id: str
    phase: ServePhase
    metric: Literal["y_diff", "angle"]
    joints: list[str]
    comparison: Literal["gte", "lte", "range"]
    threshold: float | None = None
    threshold_min: float | None = None
    threshold_max: float | None = None
    severity: Severity
    message: str

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


def _compute_metric(frame: Frame, rule: _Rule) -> float | None:
    joints = rule.joints
    if rule.metric == "y_diff":
        y0 = keypoint_y(frame, joints[0])
        y1 = keypoint_y(frame, joints[1])
        if y0 is None or y1 is None:
            return None
        return y0 - y1
    if rule.metric == "angle":
        a = joint_xy(frame, joints[0])
        b = joint_xy(frame, joints[1])
        c = joint_xy(frame, joints[2])
        if a is None or b is None or c is None:
            return None
        return compute_angle(a, b, c)
    return None


def _passes(value: float, rule: _Rule) -> bool:
    if rule.comparison == "gte":
        return value >= rule.threshold  # type: ignore[operator]
    if rule.comparison == "lte":
        return value <= rule.threshold  # type: ignore[operator]
    if rule.comparison == "range":
        return rule.threshold_min <= value <= rule.threshold_max  # type: ignore[operator]
    raise AssertionError(f"unreachable comparison: {rule.comparison!r}")


def evaluate_rules(phase_frames: dict[ServePhase, Frame | None]) -> list[Cue]:
    cues = []
    for rule in _RULES:
        frame = phase_frames.get(rule.phase)
        if frame is None:
            continue
        value = _compute_metric(frame, rule)
        if value is None:
            continue
        if not _passes(value, rule):
            cues.append(Cue(
                rule_id=rule.id,
                phase=rule.phase,
                message=rule.message,
                severity=rule.severity,
            ))
    return cues
