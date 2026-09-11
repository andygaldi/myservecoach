from app.engine.goal_cues import directional_spoken_cue
from app.engine.rules import RULES_BY_ID


def test_gte_rule_below_threshold_returns_low_phrase():
    rule = RULES_BY_ID["release_toss_arm_straight"]  # gte 155
    assert directional_spoken_cue(rule, 120.0) == (
        "Straighten your tossing arm more at release."
    )


def test_lte_rule_above_threshold_returns_high_phrase():
    rule = RULES_BY_ID["trophy_toss_arm_vertical"]  # lte 45
    assert directional_spoken_cue(rule, 70.0) == "Bring your tossing arm more vertical."


def test_range_rule_below_min_returns_low_phrase():
    rule = RULES_BY_ID["release_toss_hand_eye_height"]  # range -0.04..0.1
    assert directional_spoken_cue(rule, -0.1) == (
        "Release the ball a bit higher, closer to eye level."
    )


def test_range_rule_above_max_returns_high_phrase():
    rule = RULES_BY_ID["release_toss_hand_eye_height"]  # range -0.04..0.1
    assert directional_spoken_cue(rule, 0.2) == (
        "Release the ball a bit lower, closer to eye level."
    )


def test_trophy_elbow_shoulder_line_below_min_returns_raise_phrase():
    rule = RULES_BY_ID["trophy_hitting_elbow_shoulder_line"]  # range 155..180
    assert directional_spoken_cue(rule, 130.0) == (
        "Raise your hitting elbow to line up with your shoulders."
    )


def test_trophy_elbow_shoulder_line_above_max_returns_lower_phrase():
    rule = RULES_BY_ID["trophy_hitting_elbow_shoulder_line"]  # range 155..180
    assert directional_spoken_cue(rule, 190.0) == (
        "Lower your hitting elbow to line up with your shoulders."
    )


def test_contact_shoulders_stacked_below_min_returns_raise_phrase():
    rule = RULES_BY_ID["contact_shoulders_stacked"]  # range -0.09..0.04
    assert directional_spoken_cue(rule, -0.2) == (
        "Raise your hitting shoulder to stack over your non-hitting shoulder."
    )


def test_contact_shoulders_stacked_above_max_returns_lower_phrase():
    rule = RULES_BY_ID["contact_shoulders_stacked"]  # range -0.09..0.04
    assert directional_spoken_cue(rule, 0.2) == (
        "Lower your hitting shoulder to stack over your non-hitting shoulder."
    )


def test_rule_with_no_direction_entry_falls_back_to_message(monkeypatch):
    from app.engine import goal_cues

    rule = RULES_BY_ID["release_toss_arm_straight"]
    # Exercise the fallback path without depending on which real rules happen to lack an entry.
    monkeypatch.setitem(goal_cues._DIRECTION_PHRASES, rule.id, None)
    monkeypatch.delitem(goal_cues._DIRECTION_PHRASES, rule.id)

    assert directional_spoken_cue(rule, 120.0) == rule.message
