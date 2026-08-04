import pytest
from pydantic import ValidationError
from app.models import BoundingBox, Cue, Detection, Frame, Keypoint, ServePhase, Severity
from app.engine.angles import segment_angle_from_vertical
from app.engine.rules import compute_metric_value, evaluate_rules, _Rule
import app.engine.rules as rules_module
from conftest import make_frame


# Canonical "perfect" keypoints for the P5-calibrated 9-rule open-side set — every rule
# passes, zero cues produced. Values numerically verified against the real
# compute_metric_value() during Phase P5 implementation (see phases/2026-07-09-p5-rule-
# calibration-2d/plan.md Group 5 run notes).

# release_toss_arm_straight: shoulder/elbow/wrist collinear vertical → 180° ≥ 155 ✓
# release_toss_hand_eye_height: wrist y=0.95, nose y=0.9 → diff=+0.05, in [-0.11,0.10] ✓
PERFECT_RELEASE = {
    "left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9},
    "left_elbow":    {"x": 0.4, "y": 0.8, "confidence": 0.9},
    "left_wrist":    {"x": 0.4, "y": 0.95, "confidence": 0.9},
    "nose":          {"x": 0.4, "y": 0.9, "confidence": 0.9},
}

# trophy_toss_arm_straight: shoulder/elbow/wrist collinear vertical → 180° ≥ 145 ✓
# trophy_toss_arm_vertical: shoulder->wrist perfectly vertical → 0° ≤ 45 ✓
# trophy_hitting_elbow_shoulder_line: left_shoulder/right_shoulder/right_elbow collinear
#   horizontal (elbow extended out in line with the shoulders) → 180°, in [155,180] ✓
PERFECT_TROPHY = {
    "left_shoulder":  {"x": 0.4, "y": 0.6, "confidence": 0.9},
    "left_elbow":     {"x": 0.4, "y": 0.75, "confidence": 0.9},
    "left_wrist":     {"x": 0.4, "y": 0.9, "confidence": 0.9},
    "right_shoulder": {"x": 0.6, "y": 0.6, "confidence": 0.9},
    "right_elbow":    {"x": 0.8, "y": 0.6, "confidence": 0.9},
}

# racket_drop_ball_height/racket_drop_ball_front: ball bbox center (0.45, 0.95) relative to
# left_shoulder (0.4, 0.6) → offset_y=+0.35 (in [0.28,0.40]), offset_x=+0.05 (in [-0.01,0.12]) ✓
PERFECT_RACKET_DROP = {
    "left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9},
}
PERFECT_RACKET_DROP_DETECTIONS = [
    Detection(label="ball", confidence=0.9, bbox=BoundingBox(x_min=0.43, x_max=0.47, y_min=0.93, y_max=0.97)),
]

# contact_left_hip_angle: shoulder(0.4,0.6)/hip(0.4,0.3)/knee(0.55,0.1) → ≈143.1°, in [95,156] ✓
# contact_shoulders_stacked: right_shoulder x=0.41 vs left_shoulder x=0.4 → diff=+0.01, in [-0.09,0.04] ✓
PERFECT_CONTACT = {
    "left_shoulder":  {"x": 0.4, "y": 0.6, "confidence": 0.9},
    "left_hip":       {"x": 0.4, "y": 0.3, "confidence": 0.9},
    "left_knee":      {"x": 0.55, "y": 0.1, "confidence": 0.9},
    "right_shoulder": {"x": 0.41, "y": 0.62, "confidence": 0.9},
}


def perfect_phases():
    return {
        ServePhase.release:     make_frame(PERFECT_RELEASE),
        ServePhase.trophy_pose: make_frame(PERFECT_TROPHY),
        ServePhase.racket_drop: make_frame(PERFECT_RACKET_DROP),
        ServePhase.contact:     make_frame(PERFECT_CONTACT),
    }


def perfect_detections():
    return {ServePhase.racket_drop: PERFECT_RACKET_DROP_DETECTIONS}


# --- Zero-cue baseline ---

def test_perfect_frames_fire_no_cues():
    assert evaluate_rules(perfect_phases(), perfect_detections()) == []


# --- Individual rule violations (isolated: only the named rule fails) ---

def test_release_toss_arm_straight_fires():
    phases = perfect_phases()
    phases[ServePhase.release] = make_frame({
        **PERFECT_RELEASE,
        "left_elbow": {"x": 0.55, "y": 0.8, "confidence": 0.9},  # bent to the side → ~98°
    })
    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    assert cues[0].rule_id == "release_toss_arm_straight"
    assert cues[0].phase == ServePhase.release
    assert cues[0].severity.value == "major"
    assert "toss" in cues[0].message.lower()


def test_release_toss_hand_eye_height_fires():
    phases = perfect_phases()
    phases[ServePhase.release] = make_frame({
        **PERFECT_RELEASE,
        "nose": {"x": 0.4, "y": 0.5, "confidence": 0.9},  # far below wrist → diff=+0.45
    })
    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    assert cues[0].rule_id == "release_toss_hand_eye_height"
    assert cues[0].phase == ServePhase.release


def test_trophy_hitting_elbow_shoulder_line_fires():
    phases = perfect_phases()
    phases[ServePhase.trophy_pose] = make_frame({
        **PERFECT_TROPHY,
        "right_elbow": {"x": 0.8, "y": 0.4, "confidence": 0.9},  # dropped below the line → 135°
    })
    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    assert cues[0].rule_id == "trophy_hitting_elbow_shoulder_line"
    assert cues[0].phase == ServePhase.trophy_pose


def test_trophy_toss_arm_straight_fires():
    phases = perfect_phases()
    phases[ServePhase.trophy_pose] = make_frame({
        **PERFECT_TROPHY,
        "left_elbow": {"x": 0.55, "y": 0.75, "confidence": 0.9},  # bent to the side → 90°
    })
    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    assert cues[0].rule_id == "trophy_toss_arm_straight"
    assert cues[0].phase == ServePhase.trophy_pose


def test_trophy_toss_arm_vertical_fires():
    phases = perfect_phases()
    phases[ServePhase.trophy_pose] = make_frame({
        **PERFECT_TROPHY,
        # Straight but diagonal (still 180° at elbow, so arm_straight still passes) → ~53° from vertical
        "left_elbow": {"x": 0.6, "y": 0.75, "confidence": 0.9},
        "left_wrist": {"x": 0.8, "y": 0.9, "confidence": 0.9},
    })
    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    assert cues[0].rule_id == "trophy_toss_arm_vertical"
    assert cues[0].phase == ServePhase.trophy_pose


def test_racket_drop_ball_height_fires():
    phases = perfect_phases()
    detections = {ServePhase.racket_drop: [
        Detection(label="ball", confidence=0.9, bbox=BoundingBox(x_min=0.43, x_max=0.47, y_min=1.28, y_max=1.32)),
    ]}
    cues = evaluate_rules(phases, detections)
    assert len(cues) == 1
    assert cues[0].rule_id == "racket_drop_ball_height"
    assert cues[0].phase == ServePhase.racket_drop


def test_racket_drop_ball_front_fires():
    phases = perfect_phases()
    detections = {ServePhase.racket_drop: [
        Detection(label="ball", confidence=0.9, bbox=BoundingBox(x_min=0.88, x_max=0.92, y_min=0.93, y_max=0.97)),
    ]}
    cues = evaluate_rules(phases, detections)
    assert len(cues) == 1
    assert cues[0].rule_id == "racket_drop_ball_front"
    assert cues[0].phase == ServePhase.racket_drop


def test_contact_left_hip_angle_fires():
    phases = perfect_phases()
    phases[ServePhase.contact] = make_frame({
        **PERFECT_CONTACT,
        "left_knee": {"x": 0.4, "y": 0.05, "confidence": 0.9},  # fully straight leg → 180°
    })
    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    assert cues[0].rule_id == "contact_left_hip_angle"
    assert cues[0].phase == ServePhase.contact


def test_contact_shoulders_stacked_fires():
    phases = perfect_phases()
    phases[ServePhase.contact] = make_frame({
        **PERFECT_CONTACT,
        "right_shoulder": {"x": 0.6, "y": 0.62, "confidence": 0.9},  # far right of left_shoulder
    })
    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    assert cues[0].rule_id == "contact_shoulders_stacked"
    assert cues[0].phase == ServePhase.contact


# --- Skip conditions ---

def test_none_phase_frame_skips_its_rules():
    phases = {
        ServePhase.release:     None,
        ServePhase.trophy_pose: make_frame(PERFECT_TROPHY),
        ServePhase.racket_drop: make_frame(PERFECT_RACKET_DROP),
        ServePhase.contact:     make_frame(PERFECT_CONTACT),
    }
    assert evaluate_rules(phases, perfect_detections()) == []


def test_low_confidence_keypoints_skip_rule():
    low_conf = {k: {**v, "confidence": 0.1} for k, v in PERFECT_TROPHY.items()}
    phases = perfect_phases()
    phases[ServePhase.trophy_pose] = make_frame(low_conf)
    assert evaluate_rules(phases, perfect_detections()) == []


def test_missing_keypoint_skips_rule():
    phases = perfect_phases()
    # Remove the toss shoulder — angle metrics needing it can't be computed → rule skipped
    trophy_kps = {k: v for k, v in PERFECT_TROPHY.items() if k != "left_shoulder"}
    phases[ServePhase.trophy_pose] = make_frame(trophy_kps)
    cues = evaluate_rules(phases, perfect_detections())
    # trophy_toss_arm_straight/trophy_toss_arm_vertical/trophy_hitting_elbow_shoulder_line all
    # need left_shoulder — all skipped; no other trophy rules fire either
    assert cues == []


# --- Ordering and counts ---

def test_rules_evaluated_in_order():
    # Both trophy rules fire; they should appear in rules.json order
    phases = perfect_phases()
    phases[ServePhase.trophy_pose] = make_frame({
        **PERFECT_TROPHY,
        "right_elbow": {"x": 0.8, "y": 0.4, "confidence": 0.9},   # elbow_shoulder_line fires
        "left_elbow":  {"x": 0.55, "y": 0.75, "confidence": 0.9},  # toss_arm_straight fires
    })
    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 2
    assert cues[0].rule_id == "trophy_hitting_elbow_shoulder_line"  # comes first in rules.json
    assert cues[1].rule_id == "trophy_toss_arm_straight"            # comes second


# --- New multi-rule tests ---

def test_all_rules_fire_simultaneously():
    phases = {
        ServePhase.release: make_frame({
            **PERFECT_RELEASE,
            "left_elbow": {"x": 0.55, "y": 0.8, "confidence": 0.9},  # arm_straight fires
            "nose": {"x": 0.4, "y": 0.5, "confidence": 0.9},          # eye_height fires
        }),
        ServePhase.trophy_pose: make_frame({
            **PERFECT_TROPHY,
            "right_elbow": {"x": 0.8, "y": 0.4, "confidence": 0.9},   # elbow_shoulder_line fires
            "left_elbow":  {"x": 0.6, "y": 0.75, "confidence": 0.9},  # diagonal: still straight...
            "left_wrist":  {"x": 0.8, "y": 0.9, "confidence": 0.9},   # ...but not vertical → fires
        }),
        ServePhase.racket_drop: make_frame(PERFECT_RACKET_DROP),
        ServePhase.contact: make_frame({
            **PERFECT_CONTACT,
            "left_knee": {"x": 0.4, "y": 0.05, "confidence": 0.9},          # hip_angle fires
            "right_shoulder": {"x": 0.6, "y": 0.62, "confidence": 0.9},     # shoulders_stacked fires
        }),
    }
    detections = {ServePhase.racket_drop: [
        Detection(label="ball", confidence=0.9, bbox=BoundingBox(x_min=0.88, x_max=0.92, y_min=0.93, y_max=0.97)),
    ]}  # ball far right → racket_drop_ball_front fires; racket_drop_ball_height still passes (y unchanged)
    cues = evaluate_rules(phases, detections)
    rule_ids = [c.rule_id for c in cues]
    assert rule_ids == [
        "release_toss_arm_straight",
        "release_toss_hand_eye_height",
        "trophy_hitting_elbow_shoulder_line",
        "trophy_toss_arm_vertical",
        "racket_drop_ball_front",
        "contact_left_hip_angle",
        "contact_shoulders_stacked",
    ]


def test_evaluate_rules_with_missing_phase_key():
    # Empty dict — no phases present at all — should return no cues
    assert evaluate_rules({}) == []


def test_empty_keypoints_frame():
    # All frames have empty keypoints — metric computation always returns None → no cues
    phases = {
        ServePhase.release:     make_frame({}),
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


def test_rule_model_defaults_view_to_open_side():
    rule = _Rule(
        id="test",
        phase="trophy_pose",
        metric="y_diff",
        joints=["left_wrist", "left_shoulder"],
        comparison="gte",
        threshold=0.0,
        severity="major",
        message="test",
    )
    assert rule.view == "open_side"


# --- New metric types ---

def _ball_detection(x_min, y_min, x_max, y_max) -> Detection:
    return Detection(label="ball", confidence=0.9, bbox=BoundingBox(x_min=x_min, y_min=y_min, x_max=x_max, y_max=y_max))


def _racket_detection() -> Detection:
    return Detection(label="racket", confidence=0.9, bbox=BoundingBox(x_min=0.1, y_min=0.1, x_max=0.2, y_max=0.2))


def test_x_diff_metric():
    frame = make_frame({
        "right_shoulder": {"x": 0.6, "y": 0.5, "confidence": 0.9},
        "left_shoulder":  {"x": 0.4, "y": 0.5, "confidence": 0.9},
    })
    value = compute_metric_value(frame, "x_diff", ["right_shoulder", "left_shoulder"])
    assert value == pytest.approx(0.2)


def test_angle_from_vertical_metric():
    frame = make_frame({
        "left_shoulder": {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "left_wrist":    {"x": 0.6, "y": 0.3, "confidence": 0.9},
    })
    value = compute_metric_value(frame, "angle_from_vertical", ["left_shoulder", "left_wrist"])
    assert value == segment_angle_from_vertical(frame, "left_shoulder", "left_wrist")


def test_ball_offset_y_metric_with_detection():
    frame = make_frame({"left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9}})
    detections = [_ball_detection(0.35, 0.75, 0.45, 0.85)]  # ball center y = 0.8
    value = compute_metric_value(frame, "ball_offset_y", ["left_shoulder"], detections)
    assert value == pytest.approx(0.2)  # 0.8 - 0.6


def test_ball_offset_x_metric_with_detection():
    frame = make_frame({"left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9}})
    detections = [_ball_detection(0.45, 0.75, 0.55, 0.85)]  # ball center x = 0.5
    value = compute_metric_value(frame, "ball_offset_x", ["left_shoulder"], detections)
    assert value == pytest.approx(0.1)  # 0.5 - 0.4


def test_ball_offset_metric_returns_none_when_no_ball_detected():
    frame = make_frame({"left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9}})
    assert compute_metric_value(frame, "ball_offset_y", ["left_shoulder"], []) is None
    assert compute_metric_value(frame, "ball_offset_y", ["left_shoulder"], [_racket_detection()]) is None


def test_ball_offset_metric_returns_none_when_detections_is_none():
    frame = make_frame({"left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9}})
    assert compute_metric_value(frame, "ball_offset_y", ["left_shoulder"], None) is None


# --- View filtering ---

def _fixture_rule(rule_id: str, view: str) -> _Rule:
    return _Rule(
        id=rule_id,
        phase=ServePhase.trophy_pose,
        metric="y_diff",
        joints=["left_wrist", "left_shoulder"],
        comparison="gte",
        threshold=999.0,  # always fails — left_wrist y (0.2) is never >= 999
        severity="major",
        message=f"{rule_id} fired",
        view=view,
    )


def _view_fixture_phases():
    return {
        ServePhase.trophy_pose: make_frame({
            "left_wrist":    {"x": 0.3, "y": 0.2, "confidence": 0.9},
            "left_shoulder": {"x": 0.4, "y": 0.65, "confidence": 0.9},
        }),
    }


def test_evaluate_rules_defaults_to_open_side_view(monkeypatch):
    fixture_rules = [_fixture_rule("open_side_rule", "open_side"), _fixture_rule("behind_server_rule", "behind_server")]
    monkeypatch.setattr(rules_module, "_RULES", fixture_rules)
    cues = evaluate_rules(_view_fixture_phases())
    assert [c.rule_id for c in cues] == ["open_side_rule"]


def test_evaluate_rules_respects_explicit_view_argument(monkeypatch):
    fixture_rules = [_fixture_rule("open_side_rule", "open_side"), _fixture_rule("behind_server_rule", "behind_server")]
    monkeypatch.setattr(rules_module, "_RULES", fixture_rules)
    cues = evaluate_rules(_view_fixture_phases(), view="behind_server")
    assert [c.rule_id for c in cues] == ["behind_server_rule"]


# --- Detections threading ---

def test_evaluate_rules_passes_detections_to_ball_offset_rule(monkeypatch):
    fixture_rule = _Rule(
        id="ball_offset_rule",
        phase=ServePhase.racket_drop,
        metric="ball_offset_y",
        joints=["left_shoulder"],
        comparison="gte",
        threshold=999.0,  # always fails when a value is computed
        severity="major",
        message="ball offset fired",
        view="open_side",
    )
    monkeypatch.setattr(rules_module, "_RULES", [fixture_rule])
    phases = {
        ServePhase.racket_drop: make_frame({"left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9}}),
    }
    detections = {ServePhase.racket_drop: [_ball_detection(0.35, 0.75, 0.45, 0.85)]}

    cues = evaluate_rules(phases, detections)
    assert [c.rule_id for c in cues] == ["ball_offset_rule"]

    cues_without_detections = evaluate_rules(phases)
    assert cues_without_detections == []


# --- Deviation detail on emitted cues (P6c) ---

def test_cue_carries_deviation_detail_for_single_threshold_rule():
    """A gte/lte rule's cue reports the measured value and only `threshold`."""
    phases = perfect_phases()
    bad_trophy = {
        **PERFECT_TROPHY,
        # Straight but diagonal → trophy_toss_arm_vertical (lte 45) fires; arm_straight still passes.
        "left_elbow": {"x": 0.6, "y": 0.75, "confidence": 0.9},
        "left_wrist": {"x": 0.8, "y": 0.9, "confidence": 0.9},
    }
    phases[ServePhase.trophy_pose] = make_frame(bad_trophy)

    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    cue = cues[0]
    assert cue.rule_id == "trophy_toss_arm_vertical"
    assert cue.metric == "angle_from_vertical"
    assert cue.joints == ["left_shoulder", "left_wrist"]
    assert cue.comparison == "lte"
    assert cue.threshold == 45
    assert cue.threshold_min is None
    assert cue.threshold_max is None
    # The reported value is exactly what the rule was evaluated against.
    assert cue.measured_value == compute_metric_value(
        make_frame(bad_trophy), "angle_from_vertical", ["left_shoulder", "left_wrist"]
    )
    assert cue.measured_value > cue.threshold  # i.e. it genuinely failed the comparison


def test_cue_carries_deviation_detail_for_range_rule():
    """A range rule's cue reports both bounds and leaves `threshold` unset."""
    phases = perfect_phases()
    bad_trophy = {
        **PERFECT_TROPHY,
        "right_elbow": {"x": 0.8, "y": 0.4, "confidence": 0.9},  # dropped below the line → 135°
    }
    phases[ServePhase.trophy_pose] = make_frame(bad_trophy)

    cues = evaluate_rules(phases, perfect_detections())
    assert len(cues) == 1
    cue = cues[0]
    assert cue.rule_id == "trophy_hitting_elbow_shoulder_line"
    assert cue.metric == "angle"
    assert cue.joints == ["left_shoulder", "right_shoulder", "right_elbow"]
    assert cue.comparison == "range"
    assert cue.threshold is None
    assert cue.threshold_min == 155
    assert cue.threshold_max == 180
    assert cue.measured_value == compute_metric_value(
        make_frame(bad_trophy), "angle", ["left_shoulder", "right_shoulder", "right_elbow"]
    )
    assert not (cue.threshold_min <= cue.measured_value <= cue.threshold_max)


def test_ball_offset_cue_carries_measured_offset():
    """Detection-derived metrics report their measured value too, not just joint-derived ones."""
    phases = perfect_phases()
    detections = {
        ServePhase.racket_drop: [
            Detection(
                label="ball",
                confidence=0.9,
                # Ball far too high above the shoulder → offset_y ≈ 0.6, outside [0.28, 0.40].
                bbox=BoundingBox(x_min=0.43, x_max=0.47, y_min=1.18, y_max=1.22),
            )
        ]
    }
    cues = evaluate_rules(phases, detections)
    height_cues = [c for c in cues if c.rule_id == "racket_drop_ball_height"]
    assert len(height_cues) == 1
    cue = height_cues[0]
    assert cue.metric == "ball_offset_y"
    assert cue.joints == ["left_shoulder"]
    assert cue.measured_value == pytest.approx(0.6)
    assert cue.threshold_min == 0.28
    assert cue.threshold_max == 0.40


def test_evaluate_rules_populates_deviation_detail_for_every_rule(monkeypatch):
    """Guards against a future rule being added without its deviation detail flowing through.

    Drives the real `evaluate_rules` path one rule at a time with a threshold rigged to fail, so
    deleting any of the deviation kwargs in `rules.py` breaks this test. (Asserting on a
    hand-built `Cue` would not — it would only be restating `rules.json`.)
    """
    frame = make_frame({
        "left_shoulder":  {"x": 0.4, "y": 0.6, "confidence": 0.9},
        "left_elbow":     {"x": 0.5, "y": 0.7, "confidence": 0.9},
        "left_wrist":     {"x": 0.7, "y": 0.9, "confidence": 0.9},
        "right_shoulder": {"x": 0.6, "y": 0.6, "confidence": 0.9},
        "right_elbow":    {"x": 0.8, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.9, "y": 0.3, "confidence": 0.9},
        "left_hip":       {"x": 0.4, "y": 0.3, "confidence": 0.9},
        "left_knee":      {"x": 0.55, "y": 0.1, "confidence": 0.9},
        "nose":           {"x": 0.4, "y": 0.95, "confidence": 0.9},
    })
    detections = [_ball_detection(0.35, 0.75, 0.45, 0.85)]

    for rule in list(rules_module._RULES):
        # Force this rule to fail regardless of its comparison, so a cue is definitely emitted.
        failing = rule.model_copy(update={
            "threshold": 1e6 if rule.comparison == "gte" else -1e6,
            "threshold_min": 1e6,
            "threshold_max": 1e6 + 1,
        })
        monkeypatch.setattr(rules_module, "_RULES", [failing])

        phases = {failing.phase: frame}
        cues = evaluate_rules(phases, {failing.phase: detections})
        assert len(cues) == 1, f"rule {rule.id} produced no cue to inspect"

        cue = cues[0]
        assert cue.rule_id == rule.id
        assert cue.metric == rule.metric
        assert cue.joints == rule.joints
        assert cue.comparison == rule.comparison
        assert cue.measured_value is not None, f"rule {rule.id} lost its measured value"
        assert cue.measured_value == compute_metric_value(
            frame, rule.metric, rule.joints, detections
        )
