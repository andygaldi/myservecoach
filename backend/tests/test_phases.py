import pytest
from app.models import BoundingBox, Detection, Frame, Keypoint, ServePhase
from app.engine.phases import _min_max_normalize, detect_phases
from conftest import make_frame


def _ball_detection(center_y: float, confidence: float = 0.9) -> Detection:
    return Detection(
        label="ball",
        confidence=confidence,
        bbox=BoundingBox(x_min=0.4, x_max=0.42, y_min=center_y - 0.01, y_max=center_y + 0.01),
    )


def _racket_detection(center_y: float, confidence: float = 0.9) -> Detection:
    return Detection(
        label="racket",
        confidence=confidence,
        bbox=BoundingBox(x_min=0.4, x_max=0.42, y_min=center_y - 0.01, y_max=center_y + 0.01),
    )


def _racket_ball_pair(distance: float) -> list[Detection]:
    racket = Detection(
        label="racket", confidence=0.9,
        bbox=BoundingBox(x_min=0.50, x_max=0.52, y_min=0.50, y_max=0.52),
    )
    ball = Detection(
        label="ball", confidence=0.9,
        bbox=BoundingBox(x_min=0.50 + distance, x_max=0.52 + distance, y_min=0.50, y_max=0.52),
    )
    return [racket, ball]


# Canonical "mid-serve" keypoints for a right-handed player — used as a base frame for tests
# that don't care about the specific signal being probed. The toss (left) elbow defaults to a
# bent position (~59°) so trophy_pose's toss-arm-straightness signal has something to discriminate
# against when a test explicitly straightens it.
BASE_KPS = {
    "right_shoulder": {"x": 0.6, "y": 0.5,  "confidence": 0.9},
    "right_elbow":    {"x": 0.4, "y": 0.5,  "confidence": 0.9},
    "right_wrist":    {"x": 0.4, "y": 0.7,  "confidence": 0.9},
    "right_hip":      {"x": 0.5, "y": 0.3,  "confidence": 0.9},
    "right_knee":     {"x": 0.5, "y": 0.15, "confidence": 0.9},
    "right_ankle":    {"x": 0.5, "y": 0.0,  "confidence": 0.9},
    "left_wrist":     {"x": 0.3, "y": 0.8,  "confidence": 0.9},
    "left_shoulder":  {"x": 0.4, "y": 0.65, "confidence": 0.9},
    "left_elbow":     {"x": 0.5, "y": 0.75, "confidence": 0.9},  # bent (~59°) toss elbow, default
    "left_hip":       {"x": 0.3, "y": 0.3,  "confidence": 0.9},
    "left_knee":      {"x": 0.3, "y": 0.15, "confidence": 0.9},
    "left_ankle":     {"x": 0.3, "y": 0.0,  "confidence": 0.9},
}

# A straightened toss elbow (~177°) — used to signal trophy_pose's toss-arm-straightness candidate.
STRAIGHT_TOSS_ELBOW = {"left_elbow": {"x": 0.35, "y": 0.72, "confidence": 0.9}}


# --- Trophy pose detection: combined hip-height + toss-arm-straightness signal ---

def test_trophy_picks_frame_with_combined_signal():
    # A 3-frame crouched-hip + straight-toss-arm plateau (f1-f3) between a neutral frame (f0) and
    # a contact-like frame (f4, high wrist) — trophy should land within the plateau.
    f0 = make_frame(BASE_KPS, 0.0)
    crouched = {"right_hip": {"x": 0.5, "y": 0.15, "confidence": 0.9}, **STRAIGHT_TOSS_ELBOW}
    f1 = make_frame({**BASE_KPS, **crouched}, 1.0)
    f2 = make_frame({**BASE_KPS, **crouched}, 2.0)
    f3 = make_frame({**BASE_KPS, **crouched}, 3.0)
    f4 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 1.2, "confidence": 0.9}}, 4.0)

    result = detect_phases([f0, f1, f2, f3, f4])
    assert result[ServePhase.trophy_pose] is f2


def test_trophy_combines_hip_and_toss_arm_neither_alone_dominates():
    # Group A: extreme hip crouch (y=0.05) but only moderately straight arm (~105°).
    # Group B: moderate hip crouch (y=0.25) but a fully straight arm (~177°).
    # Neither group maxes out both signals — the combined weighted score must still pick a
    # winner (group A, by a modest margin) rather than trivially matching whichever group has
    # the single most extreme raw value.
    f0 = make_frame(BASE_KPS, 0.0)
    group_a_kps = {"right_hip": {"x": 0.5, "y": 0.05, "confidence": 0.9},
                    "left_elbow": {"x": 0.42, "y": 0.735, "confidence": 0.9}}
    fA1 = make_frame({**BASE_KPS, **group_a_kps}, 1.0)
    fA2 = make_frame({**BASE_KPS, **group_a_kps}, 2.0)
    fA3 = make_frame({**BASE_KPS, **group_a_kps}, 3.0)
    group_b_kps = {"right_hip": {"x": 0.5, "y": 0.25, "confidence": 0.9}, **STRAIGHT_TOSS_ELBOW}
    fB1 = make_frame({**BASE_KPS, **group_b_kps}, 4.0)
    fB2 = make_frame({**BASE_KPS, **group_b_kps}, 5.0)
    fB3 = make_frame({**BASE_KPS, **group_b_kps}, 6.0)
    f_contact = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 1.2, "confidence": 0.9}}, 7.0)

    result = detect_phases([f0, fA1, fA2, fA3, fB1, fB2, fB3, f_contact])
    assert result[ServePhase.trophy_pose] is fA2


def test_trophy_smooths_series_to_reduce_outlier_influence():
    # A single spurious frame (f3) with an extreme, isolated hip-crouch spike must not win over a
    # genuine (less extreme but multi-frame) crouched/straight-arm plateau (f7-f9) elsewhere.
    f0 = make_frame(BASE_KPS, 0.0)
    f1 = make_frame(BASE_KPS, 1.0)
    f2 = make_frame(BASE_KPS, 2.0)
    f3 = make_frame({**BASE_KPS, "right_hip": {"x": 0.5, "y": 0.02, "confidence": 0.9}}, 3.0)  # spurious spike
    f4 = make_frame(BASE_KPS, 4.0)
    f5 = make_frame(BASE_KPS, 5.0)
    f6 = make_frame(BASE_KPS, 6.0)
    modest = {"right_hip": {"x": 0.5, "y": 0.2, "confidence": 0.9},
              "left_elbow": {"x": 0.38, "y": 0.73, "confidence": 0.9}}
    f7 = make_frame({**BASE_KPS, **modest}, 7.0)
    f8 = make_frame({**BASE_KPS, **modest}, 8.0)
    f9 = make_frame({**BASE_KPS, **modest}, 9.0)
    f10 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 1.2, "confidence": 0.9}}, 10.0)

    result = detect_phases([f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10])
    assert result[ServePhase.trophy_pose] is f8


def test_trophy_bounded_by_release_and_contact_window():
    # f_before precedes release (toss wrist below shoulder) but has the most extreme (would-be
    # winning) hip/arm signal in the whole sequence — it must be excluded. The real pick must
    # come from within [release, contact).
    f_before = make_frame(
        {**BASE_KPS, "right_hip": {"x": 0.5, "y": 0.01, "confidence": 0.9}, **STRAIGHT_TOSS_ELBOW,
         "left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9}},
        0.0,
    )
    f_release = make_frame(BASE_KPS, 1.0)  # toss wrist rises above shoulder here
    modest = {"right_hip": {"x": 0.5, "y": 0.2, "confidence": 0.9},
              "left_elbow": {"x": 0.37, "y": 0.73, "confidence": 0.9}}
    f2 = make_frame({**BASE_KPS, **modest}, 2.0)
    f3 = make_frame({**BASE_KPS, **modest}, 3.0)
    f4 = make_frame({**BASE_KPS, **modest}, 4.0)
    f_contact = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 1.2, "confidence": 0.9}}, 5.0)

    result = detect_phases([f_before, f_release, f2, f3, f4, f_contact])
    assert result[ServePhase.trophy_pose] is f3


def test_trophy_falls_back_to_toss_arm_only_when_no_hip_data():
    no_hip = {k: v for k, v in BASE_KPS.items() if k not in ("right_hip", "left_hip")}
    f0 = make_frame(no_hip, 0.0)
    f1 = make_frame({**no_hip, **STRAIGHT_TOSS_ELBOW}, 1.0)
    f2 = make_frame({**no_hip, **STRAIGHT_TOSS_ELBOW}, 2.0)
    f3 = make_frame({**no_hip, **STRAIGHT_TOSS_ELBOW}, 3.0)
    f4 = make_frame({**no_hip, "right_wrist": {"x": 0.4, "y": 1.2, "confidence": 0.9}}, 4.0)

    result = detect_phases([f0, f1, f2, f3, f4])
    assert result[ServePhase.trophy_pose] is f2


def test_trophy_none_when_no_hip_or_toss_elbow_data():
    no_signal = {
        "left_wrist": {"x": 0.3, "y": 0.8, "confidence": 0.9},
        "left_shoulder": {"x": 0.4, "y": 0.65, "confidence": 0.9},
        "right_wrist": {"x": 0.4, "y": 0.7, "confidence": 0.9},
    }
    f0 = make_frame(no_signal, 0.0)
    f1 = make_frame({**no_signal, "right_wrist": {"x": 0.4, "y": 0.9, "confidence": 0.9}}, 1.0)

    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is None
    assert result[ServePhase.contact] is f1  # unaffected — contact only needs wrist data


def test_trophy_low_confidence_keypoints_excluded():
    low_conf = {k: {**v, "confidence": 0.1} for k, v in BASE_KPS.items()}
    result = detect_phases([make_frame(low_conf, 0.0)])
    assert result[ServePhase.trophy_pose] is None


def test_single_trophy_frame_detected():
    f = make_frame(BASE_KPS, 0.0)
    result = detect_phases([f])
    assert result[ServePhase.trophy_pose] is f


def test_trophy_ties_broken_to_first_frame():
    f0 = make_frame(BASE_KPS, 0.0)
    f1 = make_frame(BASE_KPS, 1.0)
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is f0


# --- Racket drop detection: highest shoulder-external-rotation proxy angle (no smoothing) ---

def test_racket_drop_picks_frame_with_highest_er_proxy_angle():
    f0 = make_frame(BASE_KPS, 0.0)  # trophy-like: wrist above elbow
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.25, "y": 0.35, "confidence": 0.9}}, 1.0)  # partial (135°)
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.40, "y": 0.05, "confidence": 0.9}}, 2.0)  # peak (180°)
    f3 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.55, "y": 0.35, "confidence": 0.9}}, 3.0)  # partial (135°)
    f4 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 1.2, "confidence": 0.9}}, 4.0)  # contact

    result = detect_phases([f0, f1, f2, f3, f4])
    assert result[ServePhase.trophy_pose] is f0
    assert result[ServePhase.contact] is f4
    assert result[ServePhase.racket_drop] is f2


def test_racket_drop_has_no_smoothing_so_an_isolated_spike_wins():
    # Unlike trophy_pose, racket_drop's window is deliberately unsmoothed (window=1) — real
    # windows are often just 1-4 frames wide, where smoothing was empirically found to dilute the
    # one true peak more than it removes noise. An isolated single-frame spike (f2) must win here
    # over a wider but less extreme plateau (f4-f6), the opposite of trophy_pose's behavior.
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.7, "confidence": 0.9}}, 1.0)  # baseline (0°)
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.40, "y": 0.05, "confidence": 0.9}}, 2.0)  # isolated spike (180°)
    f3 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.7, "confidence": 0.9}}, 3.0)  # baseline (0°)
    f4 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.25, "y": 0.35, "confidence": 0.9}}, 4.0)  # plateau (135°)
    f5 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.25, "y": 0.35, "confidence": 0.9}}, 5.0)
    f6 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.25, "y": 0.35, "confidence": 0.9}}, 6.0)
    f7 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 1.2, "confidence": 0.9}}, 7.0)  # contact

    result = detect_phases([f0, f1, f2, f3, f4, f5, f6, f7])
    assert result[ServePhase.racket_drop] is f2


def test_racket_drop_none_when_no_frames_between_trophy_and_contact():
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 1.0)  # contact
    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is f0
    assert result[ServePhase.contact] is f1
    assert result[ServePhase.racket_drop] is None


def test_racket_drop_none_when_no_wrist_or_elbow_data_in_window():
    no_wrist_elbow = {k: v for k, v in BASE_KPS.items() if k not in ("right_elbow", "right_wrist")}
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame(no_wrist_elbow, 1.0)  # no hitting wrist/elbow data
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 2.0)  # contact

    result = detect_phases([f0, f1, f2])
    assert result[ServePhase.racket_drop] is None


def test_racket_drop_none_when_no_trophy():
    no_signal = {
        "left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
        "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9},
        "right_wrist": {"x": 0.8, "y": 0.6, "confidence": 0.9},
    }
    f0 = make_frame(no_signal, 0.0)
    f1 = make_frame({**no_signal, "right_wrist": {"x": 0.8, "y": 0.9, "confidence": 0.9}}, 1.0)

    result = detect_phases([f0, f1])
    assert result[ServePhase.trophy_pose] is None
    assert result[ServePhase.racket_drop] is None
    assert result[ServePhase.contact] is f1  # falls back to full-sequence search


# --- Full sequence integration ---

def test_full_sequence_resolves_all_six_phases():
    f0 = make_frame({**BASE_KPS, "left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9}}, 0.0)  # start
    f1 = make_frame(BASE_KPS, 1.0)  # release (toss wrist rises above shoulder)
    crouched = {"right_hip": {"x": 0.5, "y": 0.15, "confidence": 0.9}, **STRAIGHT_TOSS_ELBOW}
    f2 = make_frame({**BASE_KPS, **crouched}, 2.0)
    f3 = make_frame({**BASE_KPS, **crouched}, 3.0)
    f4 = make_frame({**BASE_KPS, **crouched}, 4.0)  # trophy
    f5 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.40, "y": 0.05, "confidence": 0.9}}, 5.0)  # racket drop
    f6 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.40, "y": 0.05, "confidence": 0.9}}, 6.0)  # dropped plateau
    f7 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.40, "y": 0.05, "confidence": 0.9}}, 7.0)  # dropped plateau
    f8 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 1.2, "confidence": 0.9}}, 8.0)  # contact
    f9 = make_frame(
        {**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.5, "confidence": 0.9},
         "left_knee": {"x": 0.45, "y": 0.15, "confidence": 0.9}}, 8.2,
    )  # finish: toss-knee ~90°, within 0.4s of contact

    result = detect_phases([f0, f1, f2, f3, f4, f5, f6, f7, f8, f9])
    assert result[ServePhase.start] is f0
    assert result[ServePhase.release] is f1
    assert result[ServePhase.trophy_pose] is f3
    # racket_drop has no smoothing (window=1): all three plateau frames tie at 180°, so the first
    # (ascending index) wins — f5, not the middle frame.
    assert result[ServePhase.racket_drop] is f5
    assert result[ServePhase.contact] is f8
    assert result[ServePhase.finish] is f9


# --- Release detection: ball-primary path now also requires the toss wrist already above the
#     toss shoulder (guards against a low-confidence ball detection while still held pre-toss),
#     falling back to the toss-wrist-only condition whenever the combined condition never
#     resolves (not just when no ball was ever detected). ---

def test_release_requires_toss_wrist_above_shoulder_even_with_ball_detected():
    # f0: ball detected above the (low) toss wrist, but toss wrist is still below the shoulder —
    #     must NOT trigger release (this is the bug this session fixed: a ball still held
    #     pre-toss, bent-over stance, used to satisfy the ball-alone condition).
    # f1: toss wrist now above shoulder, ball still above wrist — this is the real release.
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)
    detections = [[_ball_detection(0.3)], [_ball_detection(0.9)]]

    result = detect_phases([f0, f1], detections)
    assert result[ServePhase.release] is f1


def test_release_falls_back_to_toss_wrist_when_ball_condition_never_satisfied():
    # A ball is detected throughout, but never while the toss wrist is also above the shoulder
    # (e.g. object detection loses the ball during the actual toss arc) — falls back to the
    # toss-wrist-only condition rather than resolving to None.
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)
    detections = [[_ball_detection(0.1)], []]  # ball only ever near the ground, well below any wrist

    result = detect_phases([f0, f1], detections)
    assert result[ServePhase.release] is f1


def test_release_falls_back_to_toss_wrist_when_ball_never_detected():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)
    detections = [[_racket_detection(0.9)], []]  # racket only, no ball anywhere

    result = detect_phases([f0, f1], detections)
    assert result[ServePhase.release] is f1


def test_release_falls_back_when_detections_is_none():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)

    result = detect_phases([f0, f1])
    assert result[ServePhase.release] is f1


def test_release_none_when_toss_never_rises_and_no_ball():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.2, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)

    result = detect_phases([f0])
    assert result[ServePhase.release] is None


# --- Start detection ---

def test_start_is_lowest_toss_wrist_before_release():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.3, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9},  # lowest toss wrist
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 1.0)
    f2 = make_frame({"left_wrist": {"x": 0.3, "y": 0.6, "confidence": 0.9},  # release
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 2.0)

    result = detect_phases([f0, f1, f2])
    assert result[ServePhase.release] is f2
    assert result[ServePhase.start] is f1


def test_start_falls_back_to_trophy_bound_when_no_release():
    # Toss wrist never rises above the toss shoulder anywhere in the sequence (release resolves
    # via neither the ball-primary nor the toss-wrist-only path), yet trophy_pose still resolves
    # since it no longer depends on toss-wrist height at all — only hip height + toss-arm
    # straightness. f0/f1 are deliberately non-trophy-like (baseline hip/bent arm); f2 is the
    # genuine trophy-like frame (crouched hip, straight toss arm). Right-wrist heights are
    # deliberately distinct across frames to avoid a tie in contact's preliminary window estimate.
    f0 = make_frame({**BASE_KPS, "left_wrist": {"x": 0.3, "y": 0.05, "confidence": 0.9},
                      "right_wrist": {"x": 0.4, "y": 0.6, "confidence": 0.9}}, 0.0)
    f1 = make_frame({**BASE_KPS, "left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9},
                      "right_wrist": {"x": 0.4, "y": 0.63, "confidence": 0.9}}, 1.0)
    crouched = {"right_hip": {"x": 0.5, "y": 0.15, "confidence": 0.9},
                "left_elbow": {"x": 0.35, "y": 0.72, "confidence": 0.9},
                "left_wrist": {"x": 0.3, "y": 0.15, "confidence": 0.9},
                "right_wrist": {"x": 0.4, "y": 0.66, "confidence": 0.9}}
    f2 = make_frame({**BASE_KPS, **crouched}, 2.0)  # trophy

    result = detect_phases([f0, f1, f2])
    assert result[ServePhase.release] is None
    assert result[ServePhase.trophy_pose] is f2
    assert result[ServePhase.start] is f0


def test_start_none_when_neither_release_nor_trophy_resolve():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9},
                      "left_shoulder": {"x": 0.4, "y": 0.5, "confidence": 0.9}}, 0.0)

    result = detect_phases([f0])
    assert result[ServePhase.release] is None
    assert result[ServePhase.trophy_pose] is None
    assert result[ServePhase.start] is None


# --- Finish detection: within FINISH_WINDOW_SECONDS after contact, the frame whose toss-side
#     (landing) knee flexion is closest to FINISH_TARGET_KNEE_ANGLE (90°) ---

def test_finish_is_closest_to_90_degree_toss_knee_flexion_after_contact():
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}, 1.0)  # contact
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.5, "confidence": 0.9},
                      "left_knee": {"x": 0.4, "y": 0.15, "confidence": 0.9}}, 1.1)  # ~112°
    f3 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.4, "confidence": 0.9},
                      "left_knee": {"x": 0.45, "y": 0.15, "confidence": 0.9}}, 1.2)  # 90° exactly
    f4 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.3, "confidence": 0.9},
                      "left_knee": {"x": 0.3, "y": 0.15, "confidence": 0.9}}, 1.3)  # 180° (straight)

    result = detect_phases([f0, f1, f2, f3, f4])
    assert result[ServePhase.contact] is f1
    assert result[ServePhase.finish] is f3


def test_finish_bounded_to_window_after_contact():
    # A near-perfect 90° knee angle outside the post-contact window must lose to a less-perfect
    # angle inside it — proves the window bound, not just "closest angle anywhere", governs.
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}, 1.0)  # contact
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.5, "confidence": 0.9},
                      "left_knee": {"x": 0.42, "y": 0.15, "confidence": 0.9}}, 1.3)  # within window (~103°)
    f3 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.3, "confidence": 0.9},
                      "left_knee": {"x": 0.45, "y": 0.15, "confidence": 0.9}}, 1.6)  # outside window, exactly 90°

    result = detect_phases([f0, f1, f2, f3])
    assert result[ServePhase.finish] is f2


def test_finish_falls_back_to_last_frame_of_window_when_no_knee_data():
    no_left_knee = {k: v for k, v in BASE_KPS.items() if k != "left_knee"}
    f0 = make_frame(no_left_knee, 0.0)  # trophy
    f1 = make_frame({**no_left_knee, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}, 1.0)  # contact
    f2 = make_frame({**no_left_knee, "right_wrist": {"x": 0.8, "y": 0.5, "confidence": 0.9}}, 1.2)  # in window
    f3 = make_frame({**no_left_knee, "right_wrist": {"x": 0.8, "y": 0.3, "confidence": 0.9}}, 1.3)  # in window, last
    f4 = make_frame({**no_left_knee, "right_wrist": {"x": 0.8, "y": 0.2, "confidence": 0.9}}, 2.0)  # outside window

    result = detect_phases([f0, f1, f2, f3, f4])
    assert result[ServePhase.finish] is f3


def test_finish_falls_back_to_last_frame_when_no_contact():
    f0 = make_frame({"left_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9}}, 0.0)
    f1 = make_frame({"left_wrist": {"x": 0.3, "y": 0.05, "confidence": 0.9}}, 1.0)

    result = detect_phases([f0, f1])
    assert result[ServePhase.contact] is None
    assert result[ServePhase.finish] is f1


# --- Combined-signal contact detection ---

def test_contact_combines_wrist_height_and_racket_ball_proximity():
    # f1: highest wrist_y (would win on wrist-height alone) but poor (distant) racket-ball
    #     proximity. f2: mid wrist_y but the best (closest) proximity. f3: lowest wrist_y and
    #     mid proximity. The weighted combination must favor f2's balanced signals over f1's
    #     single-axis dominance.
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 1.0)
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.85, "confidence": 0.9}}, 2.0)
    f3 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.75, "confidence": 0.9}}, 3.0)

    detections = [
        [],
        _racket_ball_pair(0.5),   # f1: poor proximity
        _racket_ball_pair(0.01),  # f2: best proximity
        _racket_ball_pair(0.3),   # f3: mid proximity
    ]

    result = detect_phases([f0, f1, f2, f3], detections)
    assert result[ServePhase.contact] is f2


def test_contact_wrist_only_ranking_with_no_detections():
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.85, "confidence": 0.9}}, 1.0)
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.8, "y": 0.95, "confidence": 0.9}}, 2.0)  # highest wrist

    result = detect_phases([f0, f1, f2])
    assert result[ServePhase.contact] is f2


def test_contact_falls_back_when_ball_or_racket_missing_from_frame():
    # Frame 2 has only a racket, frame 3 has only a ball — never both in the same frame, so
    # proximity is never computed and the ranking must match wrist-height-only.
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.80, "confidence": 0.9}}, 1.0)
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.85, "confidence": 0.9}}, 2.0)
    f3 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 3.0)  # highest wrist

    detections = [
        [],
        [_racket_detection(0.5)],
        [_ball_detection(0.5)],
        [],
    ]

    result = detect_phases([f0, f1, f2, f3], detections)
    assert result[ServePhase.contact] is f3


def test_contact_detections_shorter_than_frames():
    f0 = make_frame(BASE_KPS, 0.0)  # trophy
    f1 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.80, "confidence": 0.9}}, 1.0)
    f2 = make_frame({**BASE_KPS, "right_wrist": {"x": 0.4, "y": 0.95, "confidence": 0.9}}, 2.0)  # highest wrist

    detections = [[]]  # shorter than frames — must not raise IndexError

    result = detect_phases([f0, f1, f2], detections)
    assert result[ServePhase.contact] is f2


def test_min_max_normalize_handles_equal_values():
    assert _min_max_normalize({1: 5.0, 2: 5.0, 3: 5.0}) == {1: 1.0, 2: 1.0, 3: 1.0}
    assert _min_max_normalize({7: 3.0}) == {7: 1.0}
    assert _min_max_normalize({}) == {}
