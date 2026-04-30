import pytest
from app.models import Frame, Keypoint, ServePhase
from app.engine.rules import evaluate_rules


def make_frame(keypoints: dict) -> Frame:
    return Frame(timestamp=0.0, keypoints={k: Keypoint(**v) for k, v in keypoints.items()})


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
    assert cues[0].phase == ServePhase.contact
    assert cues[0].severity.value == "major"
    assert "hitting arm" in cues[0].message


def test_contact_wrist_height_fires():
    phases = perfect_phases()
    # Collinear → 180° so contact_arm_extension passes; wrist y=0.3 < shoulder y=0.7
    phases[ServePhase.contact] = make_frame({
        "right_shoulder": {"x": 0.5, "y": 0.7, "confidence": 0.9},
        "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.5, "y": 0.3, "confidence": 0.9},
    })
    cues = evaluate_rules(phases)
    assert len(cues) == 1
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
    # trophy_toss_arm_height skipped; trophy_racket_elbow_flexion still evaluable
    assert all(c.phase != ServePhase.trophy_pose or "tossing arm" not in c.message for c in cues)


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
