import pytest
from pydantic import ValidationError
from app.models import Frame, Keypoint, ServePhase
from app.engine.rules import evaluate_rules, _Rule
from conftest import make_frame


# Canonical "perfect" keypoints — every rule passes, zero cues produced.

# trophy_toss_arm_height : left_wrist y=0.8 > left_shoulder y=0.65  → diff=+0.15 ≥ 0 ✓
# trophy_racket_elbow_flexion: right_shoulder/elbow/wrist give 90°   → in [80,110] ✓
PERFECT_TROPHY = {
    "right_shoulder": {"x": 0.6, "y": 0.7, "confidence": 0.9},
    "right_elbow":    {"x": 0.6, "y": 0.5, "confidence": 0.9},
    "right_wrist":    {"x": 0.8, "y": 0.5, "confidence": 0.9},
    "left_wrist":     {"x": 0.3, "y": 0.8, "confidence": 0.9},
    "left_shoulder":  {"x": 0.4, "y": 0.65, "confidence": 0.9},
}

# racket_drop_depth: right_wrist y=0.1 < right_hip y=0.3  → diff=-0.2 ≤ 0 ✓
PERFECT_RACKET_DROP = {
    "right_wrist": {"x": 0.8, "y": 0.1, "confidence": 0.9},
    "right_hip":   {"x": 0.5, "y": 0.3, "confidence": 0.9},
}

# contact_arm_extension : collinear at x=0.5 → 180° ≥ 150° ✓
# contact_wrist_height  : right_wrist y=0.9 > right_shoulder y=0.5 → diff=+0.4 ≥ 0 ✓
PERFECT_CONTACT = {
    "right_shoulder": {"x": 0.5, "y": 0.5, "confidence": 0.9},
    "right_elbow":    {"x": 0.5, "y": 0.7, "confidence": 0.9},
    "right_wrist":    {"x": 0.5, "y": 0.9, "confidence": 0.9},
}


def perfect_phases():
    return {
        ServePhase.trophy_pose: make_frame(PERFECT_TROPHY),
        ServePhase.racket_drop: make_frame(PERFECT_RACKET_DROP),
        ServePhase.contact:     make_frame(PERFECT_CONTACT),
    }


# --- Zero-cue baseline ---

def test_perfect_frames_fire_no_cues():
    assert evaluate_rules(perfect_phases()) == []


# --- Individual rule violations ---

def test_trophy_toss_arm_height_fires():
    phases = perfect_phases()
    phases[ServePhase.trophy_pose] = make_frame({
        **PERFECT_TROPHY,
        "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},  # y=0.2 < shoulder y=0.65
    })
    cues = evaluate_rules(phases)
    assert len(cues) == 1
    assert cues[0].rule_id == "trophy_toss_arm_height"
    assert cues[0].phase == ServePhase.trophy_pose
    assert cues[0].severity.value == "major"
    assert "tossing arm" in cues[0].message


def test_trophy_racket_elbow_flexion_fires():
    phases = perfect_phases()
    # Horizontal straight arm → 180°, outside [80, 110]
    phases[ServePhase.trophy_pose] = make_frame({
        **PERFECT_TROPHY,
        "right_shoulder": {"x": 0.3, "y": 0.5, "confidence": 0.9},
        "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.7, "y": 0.5, "confidence": 0.9},
    })
    cues = evaluate_rules(phases)
    assert len(cues) == 1
    assert cues[0].rule_id == "trophy_racket_elbow_flexion"
    assert cues[0].phase == ServePhase.trophy_pose
    assert cues[0].severity.value == "major"
    assert "racket arm" in cues[0].message


def test_racket_drop_depth_fires():
    phases = perfect_phases()
    phases[ServePhase.racket_drop] = make_frame({
        **PERFECT_RACKET_DROP,
        "right_wrist": {"x": 0.8, "y": 0.5, "confidence": 0.9},  # y=0.5 > hip y=0.3
    })
    cues = evaluate_rules(phases)
    assert len(cues) == 1
    assert cues[0].rule_id == "racket_drop_depth"
    assert cues[0].phase == ServePhase.racket_drop
    assert cues[0].severity.value == "major"
    assert "racket lower" in cues[0].message


def test_contact_arm_extension_fires():
    phases = perfect_phases()
    # 90° at elbow (< 150°); wrist y=0.5 > shoulder y=0.3 so contact_wrist_height still passes
    phases[ServePhase.contact] = make_frame({
        "right_shoulder": {"x": 0.5, "y": 0.3, "confidence": 0.9},
        "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.7, "y": 0.5, "confidence": 0.9},
    })
    cues = evaluate_rules(phases)
    assert len(cues) == 1
    assert cues[0].rule_id == "contact_arm_extension"
    assert cues[0].phase == ServePhase.contact
    assert cues[0].severity.value == "major"
    assert "hitting arm" in cues[0].message


def test_contact_wrist_height_fires():
    phases = perfect_phases()
    # Non-collinear geometry: shoulder=(0.3,0.7), elbow=(0.5,0.5), wrist=(0.65,0.3)
    # Vectors from elbow: to_shoulder=(-0.2,0.2), to_wrist=(0.15,-0.2)
    # dot = (-0.2)(0.15) + (0.2)(-0.2) = -0.03 - 0.04 = -0.07
    # mag_ba = sqrt(0.04+0.04) = sqrt(0.08) ≈ 0.2828
    # mag_bc = sqrt(0.0225+0.04) = sqrt(0.0625) = 0.25
    # cos = -0.07 / (0.2828 * 0.25) ≈ -0.990 → angle ≈ 171.9° ≥ 150° ✓ (contact_arm_extension passes)
    # wrist y=0.3 < shoulder y=0.7 → diff=-0.4 < 0 → contact_wrist_height fires ✓
    phases[ServePhase.contact] = make_frame({
        "right_shoulder": {"x": 0.3, "y": 0.7, "confidence": 0.9},
        "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.65, "y": 0.3, "confidence": 0.9},
    })
    cues = evaluate_rules(phases)
    assert len(cues) == 1
    assert cues[0].rule_id == "contact_wrist_height"
    assert cues[0].phase == ServePhase.contact
    assert cues[0].severity.value == "minor"
    assert "arm higher" in cues[0].message


# --- Skip conditions ---

def test_none_phase_frame_skips_its_rules():
    phases = {
        ServePhase.trophy_pose: None,
        ServePhase.racket_drop: make_frame(PERFECT_RACKET_DROP),
        ServePhase.contact:     make_frame(PERFECT_CONTACT),
    }
    assert evaluate_rules(phases) == []


def test_low_confidence_keypoints_skip_rule():
    low_conf = {k: {**v, "confidence": 0.1} for k, v in PERFECT_TROPHY.items()}
    phases = perfect_phases()
    phases[ServePhase.trophy_pose] = make_frame(low_conf)
    assert evaluate_rules(phases) == []


def test_missing_keypoint_skips_rule():
    phases = perfect_phases()
    # Remove the toss shoulder — y_diff metric can't be computed → rule skipped
    trophy_kps = {k: v for k, v in PERFECT_TROPHY.items() if k != "left_shoulder"}
    phases[ServePhase.trophy_pose] = make_frame(trophy_kps)
    cues = evaluate_rules(phases)
    # trophy_toss_arm_height is skipped; no other trophy rules fire either
    assert cues == []


# --- Ordering and counts ---

def test_rules_evaluated_in_order():
    # Both trophy rules fire; they should appear in rules.json order
    phases = perfect_phases()
    phases[ServePhase.trophy_pose] = make_frame({
        **PERFECT_TROPHY,
        "left_wrist":     {"x": 0.3, "y": 0.2, "confidence": 0.9},  # toss arm height fires
        "right_shoulder": {"x": 0.3, "y": 0.5, "confidence": 0.9},  # elbow flexion fires
        "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.7, "y": 0.5, "confidence": 0.9},
    })
    cues = evaluate_rules(phases)
    assert len(cues) == 2
    assert "tossing arm" in cues[0].message   # trophy_toss_arm_height comes first
    assert "racket arm" in cues[1].message    # trophy_racket_elbow_flexion comes second


# --- New multi-rule tests ---

def test_all_rules_fire_simultaneously():
    # Trophy frame: left_wrist y=0.2 < left_shoulder y=0.65 → trophy_toss_arm_height fires
    # Straight arm (180°) → trophy_racket_elbow_flexion fires (outside [80,110])
    # Racket drop: right_wrist y=0.5 > right_hip y=0.3 → racket_drop_depth fires
    # Contact: 90° elbow angle (< 150°) → contact_arm_extension fires
    #          right_wrist y=0.5 < right_shoulder y=0.7 → contact_wrist_height fires
    phases = {
        ServePhase.trophy_pose: make_frame({
            "left_wrist":     {"x": 0.3, "y": 0.2,  "confidence": 0.9},  # below left_shoulder
            "left_shoulder":  {"x": 0.4, "y": 0.65, "confidence": 0.9},
            "right_shoulder": {"x": 0.3, "y": 0.5,  "confidence": 0.9},  # straight arm → 180°
            "right_elbow":    {"x": 0.5, "y": 0.5,  "confidence": 0.9},
            "right_wrist":    {"x": 0.7, "y": 0.5,  "confidence": 0.9},
        }),
        ServePhase.racket_drop: make_frame({
            "right_wrist": {"x": 0.8, "y": 0.5, "confidence": 0.9},  # above hip
            "right_hip":   {"x": 0.5, "y": 0.3, "confidence": 0.9},
        }),
        ServePhase.contact: make_frame({
            "right_shoulder": {"x": 0.5, "y": 0.7, "confidence": 0.9},
            "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
            "right_wrist":    {"x": 0.7, "y": 0.5, "confidence": 0.9},  # 90° angle, wrist below shoulder
        }),
    }
    cues = evaluate_rules(phases)
    assert len(cues) == 5
    rule_ids = [c.rule_id for c in cues]
    assert rule_ids == [
        "trophy_toss_arm_height",
        "trophy_racket_elbow_flexion",
        "racket_drop_depth",
        "contact_arm_extension",
        "contact_wrist_height",
    ]


def test_evaluate_rules_with_missing_phase_key():
    # Empty dict — no phases present at all — should return no cues
    assert evaluate_rules({}) == []


def test_empty_keypoints_frame():
    # All frames have empty keypoints — metric computation always returns None → no cues
    phases = {
        ServePhase.trophy_pose: make_frame({}),
        ServePhase.racket_drop: make_frame({}),
        ServePhase.contact:     make_frame({}),
    }
    assert evaluate_rules(phases) == []


# --- _Rule model validation ---

def test_rule_model_rejects_unknown_comparison():
    with pytest.raises(ValidationError):
        _Rule(
            id="test",
            phase="trophy_pose",
            metric="y_diff",
            joints=["left_wrist", "left_shoulder"],
            comparison="eq",  # not a valid Literal
            threshold=0.0,
            severity="major",
            message="test",
        )


def test_rule_model_rejects_unknown_metric():
    with pytest.raises(ValidationError):
        _Rule(
            id="test",
            phase="trophy_pose",
            metric="z_diff",  # not a valid Literal
            joints=["left_wrist", "left_shoulder"],
            comparison="gte",
            threshold=0.0,
            severity="major",
            message="test",
        )
