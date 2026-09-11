import pytest

from app.engine.goal_cues import directional_spoken_cue
from app.engine.rules import RULES_BY_ID
from app.engine.scoring import UnknownGoalRuleId, score_segment
from app.models import Frame, Keypoint

BAD_ELBOW_FRAME = Frame(
    timestamp=0.0,
    keypoints={
        "right_shoulder": Keypoint(x=0.5, y=0.7, confidence=0.9),
        "right_elbow": Keypoint(x=0.5, y=0.5, confidence=0.9),
        "right_wrist": Keypoint(x=0.8, y=0.6, confidence=0.9),
        "right_hip": Keypoint(x=0.5, y=0.3, confidence=0.9),
        "left_wrist": Keypoint(x=0.3, y=0.8, confidence=0.9),
        "left_shoulder": Keypoint(x=0.4, y=0.65, confidence=0.9),
    },
)

CLEAN_SERVE_FRAMES = [
    Frame(
        timestamp=0.0,
        keypoints={
            "right_shoulder": Keypoint(x=0.8, y=0.5, confidence=0.9),
            "right_elbow": Keypoint(x=0.6, y=0.5, confidence=0.9),
            "right_wrist": Keypoint(x=0.6, y=0.7, confidence=0.9),
            "right_hip": Keypoint(x=0.5, y=0.3, confidence=0.9),
            "left_wrist": Keypoint(x=0.3, y=0.8, confidence=0.9),
            "left_shoulder": Keypoint(x=0.4, y=0.65, confidence=0.9),
        },
    ),
    Frame(
        timestamp=1.0,
        keypoints={
            "right_wrist": Keypoint(x=0.3, y=0.1, confidence=0.9),
            "right_hip": Keypoint(x=0.5, y=0.3, confidence=0.9),
        },
    ),
    Frame(
        timestamp=2.0,
        keypoints={
            "right_shoulder": Keypoint(x=0.5, y=0.5, confidence=0.9),
            "right_elbow": Keypoint(x=0.5, y=0.7, confidence=0.9),
            "right_wrist": Keypoint(x=0.5, y=0.9, confidence=0.9),
        },
    ),
]


def test_unknown_goal_rule_id_raises():
    with pytest.raises(UnknownGoalRuleId):
        score_segment([BAD_ELBOW_FRAME], goal_rule_id="not_a_real_rule")


def test_goal_result_omitted_when_no_goal_rule_id():
    result = score_segment([BAD_ELBOW_FRAME])
    assert result.goal_result is None


def test_goal_result_failed_when_rule_fires():
    result = score_segment([BAD_ELBOW_FRAME], goal_rule_id="trophy_hitting_elbow_shoulder_line")
    assert result.goal_result is not None
    assert result.goal_result.passed is False
    firing_cue = next(c for c in result.cues if c.rule_id == "trophy_hitting_elbow_shoulder_line")
    rule = RULES_BY_ID["trophy_hitting_elbow_shoulder_line"]
    assert result.goal_result.spoken_cue == directional_spoken_cue(rule, firing_cue.measured_value)
    assert result.goal_result.spoken_cue != firing_cue.message


def test_goal_result_passed_when_rule_does_not_fire():
    result = score_segment(CLEAN_SERVE_FRAMES, goal_rule_id="trophy_toss_arm_straight")
    assert result.goal_result is not None
    assert result.goal_result.passed is True
    assert result.goal_result.spoken_cue == "Nice serve — goal met!"
