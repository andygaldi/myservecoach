from app.engine.angles import joint_xy
from app.engine.rules import _Rule
from app.models import Frame

# rule_id -> phrase(s), used only when a rule's comparison direction can be determined for the
# failing value. Not every rule maps cleanly to "too low"/"too high" — the phrase is worded per
# rule, not templated generically. A `gte`/`lte` rule only ever misses in one direction (a `gte`
# miss is always low, an `lte` miss is always high), so it gets a single bare phrase; a `range`
# rule can miss on either side and gets a (low_phrase, high_phrase) pair.
#
# trophy_hitting_elbow_shoulder_line is a special case: its "angle" metric is an unsigned vertex
# angle (angles.compute_angle, via math.acos, clamped to [0, 180]), and its range's threshold_max
# is 180 — the metric's own ceiling. A miss is always `value < threshold_min` regardless of
# whether the elbow is actually too high or too low relative to the line, so the generic
# value-vs-threshold direction logic below can't be used for it. See `_trophy_elbow_direction`.
_DIRECTION_PHRASES: dict[str, str | tuple[str, str]] = {
    "release_toss_arm_straight": "Straighten your tossing arm more at release.",
    "trophy_toss_arm_straight": "Straighten your tossing arm more at the trophy pose.",
    "trophy_toss_arm_vertical": "Bring your tossing arm more vertical.",
    "release_toss_hand_eye_height": ("Release the ball a bit higher, closer to eye level.", "Release the ball a bit lower, closer to eye level."),
    "trophy_hitting_elbow_shoulder_line": ("Raise your hitting elbow to line up with your shoulders.", "Lower your hitting elbow to line up with your shoulders."),
    "racket_drop_ball_height": ("Toss the ball a bit higher above your shoulder.", "Toss the ball a bit lower above your shoulder."),
    "racket_drop_ball_front": ("Toss the ball further out in front of you.", "Toss the ball less far out in front of you."),
    "contact_left_hip_angle": ("Drive your hips through more for extension.", "Ease off the hip drive slightly at contact."),
    "contact_shoulders_stacked": ("Raise your hitting shoulder to stack over your non-hitting shoulder.", "Lower your hitting shoulder to stack over your non-hitting shoulder."),
}


def _trophy_elbow_direction(frame: Frame | None) -> str | None:
    """Which side of the shoulder line (left_shoulder -> right_shoulder, extended) the hitting
    elbow sits on, via the 2D cross product of that line against the shoulder-to-elbow vector.
    Unlike the rule's own unsigned vertex angle (math.acos, always >= 0), the cross product's
    sign survives — positive means the elbow is above the line (too high), negative means below
    (too low). Returns None when a required joint is missing/low-confidence.
    """
    if frame is None:
        return None
    b = joint_xy(frame, "right_shoulder")
    a = joint_xy(frame, "left_shoulder")
    c = joint_xy(frame, "right_elbow")
    if a is None or b is None or c is None:
        return None
    ba = (a[0] - b[0], a[1] - b[1])
    bc = (c[0] - b[0], c[1] - b[1])
    cross = ba[0] * bc[1] - ba[1] * bc[0]
    return "high" if cross >= 0 else "low"


def directional_spoken_cue(rule: _Rule, value: float, frame: Frame | None = None) -> str:
    """Returns a more specific spoken-cue phrase for a failed rule when one is defined, else
    `rule.message` unchanged. `value` is the metric value that failed `rule`'s comparison —
    direction is derived from which bound it violated (gte: below threshold means "low"; lte:
    above threshold means "high"; range: below min means "low", above max means "high"), reusing
    the calibrated threshold rather than a new one.

    `frame` is only used for trophy_hitting_elbow_shoulder_line, whose direction can't be read
    off `value` (see `_trophy_elbow_direction`) — ignored for every other rule.
    """
    phrases = _DIRECTION_PHRASES.get(rule.id)
    if phrases is None:
        return rule.message
    low, high = phrases if isinstance(phrases, tuple) else (phrases, phrases)

    if rule.id == "trophy_hitting_elbow_shoulder_line":
        direction = _trophy_elbow_direction(frame)
        return rule.message if direction is None else (high if direction == "high" else low)

    if rule.comparison == "gte":
        return low if value < rule.threshold else high  # type: ignore[operator]
    if rule.comparison == "lte":
        return high if value > rule.threshold else low  # type: ignore[operator]
    if rule.comparison == "range":
        if value < rule.threshold_min:  # type: ignore[operator]
            return low
        return high
    raise AssertionError(f"unreachable comparison: {rule.comparison!r}")
