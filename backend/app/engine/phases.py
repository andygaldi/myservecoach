import math

from app.models import Detection, Frame, ServePhase
from app.engine.angles import compute_angle, joint_xy, keypoint_y, MIN_CONFIDENCE

HANDEDNESS: dict[str, str] = {"hitting": "right", "toss": "left"}

MIN_REST_SECONDS = 0.4
LOW_MOTION_VELOCITY_THRESHOLD = 0.03  # normalized units per second
RACKET_DROP_ELBOW_WEIGHT = 0.5
RACKET_DROP_RACKET_WEIGHT = 0.5


def _frame_velocity(a: Frame, b: Frame) -> float:
    """Mean per-second displacement, in normalized coordinates, across keypoints shared by both frames.

    Normalizing by the real timestamp delta (rather than treating each frame pair as one fixed
    step) keeps the result comparable across source videos recorded at different frame rates.
    """
    shared = set(a.keypoints) & set(b.keypoints)
    distances = []
    for name in shared:
        kp_a, kp_b = a.keypoints[name], b.keypoints[name]
        if kp_a.confidence < MIN_CONFIDENCE or kp_b.confidence < MIN_CONFIDENCE:
            continue
        distances.append(math.hypot(kp_a.x - kp_b.x, kp_a.y - kp_b.y))
    if not distances:
        return 0.0
    mean_distance = sum(distances) / len(distances)
    dt = b.timestamp - a.timestamp
    return mean_distance / dt if dt > 0 else mean_distance


def segment_serves(
    frames: list[Frame],
    min_rest_seconds: float = MIN_REST_SECONDS,
    velocity_threshold: float = LOW_MOTION_VELOCITY_THRESHOLD,
) -> list[list[Frame]]:
    """Split a continuous recording's frames into per-serve sub-lists.

    A boundary is declared after a sustained low-velocity ("rest") window spanning at least
    min_rest_seconds of real time, but only once genuine motion has already been seen — so
    leading/trailing idle padding at the very start/end of the clip is never split off as its
    own empty "serve".
    """
    if not frames:
        return []

    boundaries: list[int] = []
    rest_run_start: int | None = None
    has_seen_active = False

    for i in range(1, len(frames)):
        velocity = _frame_velocity(frames[i - 1], frames[i])
        if velocity >= velocity_threshold:
            if rest_run_start is not None and has_seen_active:
                rest_duration = frames[i - 1].timestamp - frames[rest_run_start].timestamp
                if rest_duration >= min_rest_seconds:
                    boundaries.append((rest_run_start + i - 1) // 2)
            rest_run_start = None
            has_seen_active = True
        elif rest_run_start is None:
            rest_run_start = i

    segments: list[list[Frame]] = []
    start = 0
    for boundary in boundaries:
        segments.append(frames[start : boundary + 1])
        start = boundary + 1
    segments.append(frames[start:])
    return segments


def _detection_center_y(dets: list[Detection], label: str) -> float | None:
    detection = next((d for d in dets if d.label == label), None)
    if detection is None:
        return None
    return (detection.bbox.y_min + detection.bbox.y_max) / 2.0


def _min_max_normalize(values: dict[int, float]) -> dict[int, float]:
    """Min-max normalize a {frame_index: raw_value} mapping to [0, 1].

    When every value is equal (including the single-entry case), everything normalizes to 1.0
    rather than dividing by zero, so a lone candidate still wins on its own signal.
    """
    if not values:
        return {}
    lo = min(values.values())
    hi = max(values.values())
    if hi == lo:
        return {i: 1.0 for i in values}
    return {i: (v - lo) / (hi - lo) for i, v in values.items()}


def detect_phases(
    frames: list[Frame], detections: list[list[Detection]] | None = None
) -> dict[ServePhase, Frame | None]:
    hitting = HANDEDNESS["hitting"]
    toss = HANDEDNESS["toss"]

    # 0. Release: first frame where a detected ball is above the toss hand, if the ball is ever
    #    detected anywhere in the sequence; otherwise the earliest frame where the toss wrist rises
    #    above the toss shoulder.
    ball_ever_detected = detections is not None and any(
        _detection_center_y(dets, "ball") is not None for dets in detections
    )

    release_idx: int | None = None
    if ball_ever_detected:
        for i, frame in enumerate(frames):
            if detections is None or i >= len(detections):
                continue
            ball_y = _detection_center_y(detections[i], "ball")
            toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
            if ball_y is not None and toss_wrist_y is not None and ball_y > toss_wrist_y:
                release_idx = i
                break
    else:
        for i, frame in enumerate(frames):
            toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
            toss_shoulder_y = keypoint_y(frame, f"{toss}_shoulder")
            if toss_wrist_y is None or toss_shoulder_y is None:
                continue
            if toss_wrist_y > toss_shoulder_y:
                release_idx = i
                break

    # 1. Trophy pose: first qualifying frame whose hitting elbow angle (shoulder→elbow→wrist)
    #    falls within [80°, 100°]. Falls back to the first qualifying frame with no elbow
    #    data if no in-range frame exists.
    #    Conditions:
    #      - toss wrist y > toss shoulder y
    #      - hitting wrist y > hitting hip y
    #      - if hitting elbow present: hitting wrist y > hitting elbow y
    trophy_idx: int | None = None
    trophy_no_elbow_idx: int | None = None
    for i, frame in enumerate(frames):
        toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
        toss_shoulder_y = keypoint_y(frame, f"{toss}_shoulder")
        hitting_wrist_y = keypoint_y(frame, f"{hitting}_wrist")
        hitting_hip_y = keypoint_y(frame, f"{hitting}_hip")

        if any(v is None for v in [toss_wrist_y, toss_shoulder_y, hitting_wrist_y, hitting_hip_y]):
            continue
        if toss_wrist_y <= toss_shoulder_y:
            continue
        if hitting_wrist_y <= hitting_hip_y:
            continue
        hitting_elbow_y = keypoint_y(frame, f"{hitting}_elbow")
        if hitting_elbow_y is not None and hitting_wrist_y <= hitting_elbow_y:
            continue

        shoulder_xy = joint_xy(frame, f"{hitting}_shoulder")
        elbow_xy = joint_xy(frame, f"{hitting}_elbow")
        wrist_xy = joint_xy(frame, f"{hitting}_wrist")
        if shoulder_xy is not None and elbow_xy is not None and wrist_xy is not None:
            angle = compute_angle(shoulder_xy, elbow_xy, wrist_xy)
            if angle is not None and 70.0 <= angle <= 110.0:
                trophy_idx = i
                break
        elif trophy_no_elbow_idx is None:
            trophy_no_elbow_idx = i

    if trophy_idx is None:
        trophy_idx = trophy_no_elbow_idx

    # 1b. Start: the frame with the lowest toss-wrist height, searched before release (or before
    #     trophy pose if release didn't resolve) — marks the bottom of the toss backswing right
    #     before the arm begins its ascent.
    start_search_end = release_idx if release_idx is not None else trophy_idx
    start_idx: int | None = None
    if start_search_end is not None and start_search_end > 0:
        min_toss_wrist_y = float("inf")
        for i in range(0, start_search_end):
            toss_wrist_y = keypoint_y(frames[i], f"{toss}_wrist")
            if toss_wrist_y is not None and toss_wrist_y < min_toss_wrist_y:
                min_toss_wrist_y = toss_wrist_y
                start_idx = i

    # 2. Contact: maximum hitting wrist y after trophy pose.
    #    Falls back to the full sequence when no trophy is detected.
    contact_idx: int | None = None
    search_start = trophy_idx + 1 if trophy_idx is not None else 0
    max_wrist_y = float("-inf")
    for i in range(search_start, len(frames)):
        wrist_y = keypoint_y(frames[i], f"{hitting}_wrist")
        if wrist_y is not None and wrist_y > max_wrist_y:
            max_wrist_y = wrist_y
            contact_idx = i

    # 3. Racket drop: frame strictly between trophy and contact whose combined elbow-rise and
    #    racket-bbox-depth signal scores highest. Each signal is min-max normalized across the
    #    window and weighted by RACKET_DROP_ELBOW_WEIGHT / RACKET_DROP_RACKET_WEIGHT; a frame with
    #    only one signal available is scored on that signal alone. With no detections at all, the
    #    racket term is never available, so the ranking reduces to the elbow-only heuristic.
    drop_idx: int | None = None
    if trophy_idx is not None and contact_idx is not None:
        elbow_rises: dict[int, float] = {}
        for i in range(trophy_idx + 1, contact_idx):
            elbow_y_curr = keypoint_y(frames[i], f"{hitting}_elbow")
            elbow_y_prev = keypoint_y(frames[i - 1], f"{hitting}_elbow")
            if elbow_y_curr is not None and elbow_y_prev is not None:
                elbow_rises[i] = elbow_y_curr - elbow_y_prev

        racket_depths: dict[int, float] = {}
        if detections is not None:
            for i in range(trophy_idx + 1, contact_idx):
                if i >= len(detections):
                    continue
                center_y = _detection_center_y(detections[i], "racket")
                if center_y is not None:
                    racket_depths[i] = -center_y  # lower center_y (more dropped) => higher score

        elbow_norm = _min_max_normalize(elbow_rises)
        racket_norm = _min_max_normalize(racket_depths)

        best_score = float("-inf")
        for i in set(elbow_norm) | set(racket_norm):
            parts = []
            if i in elbow_norm:
                parts.append((RACKET_DROP_ELBOW_WEIGHT, elbow_norm[i]))
            if i in racket_norm:
                parts.append((RACKET_DROP_RACKET_WEIGHT, racket_norm[i]))
            total_weight = sum(w for w, _ in parts)
            score = sum(w * v for w, v in parts) / total_weight if total_weight else float("-inf")
            if score > best_score:
                best_score = score
                drop_idx = i

    # 4. Finish: the frame with the lowest front (leading, toss-side) foot height after contact —
    #    marks the front-foot landing. Falls back to the last frame when there's no post-contact
    #    ankle data, or no contact at all.
    finish_idx: int | None = None
    if contact_idx is not None:
        min_front_foot_y = float("inf")
        for i in range(contact_idx + 1, len(frames)):
            front_foot_y = keypoint_y(frames[i], f"{toss}_ankle")
            if front_foot_y is not None and front_foot_y < min_front_foot_y:
                min_front_foot_y = front_foot_y
                finish_idx = i
    if finish_idx is None:
        finish_idx = len(frames) - 1 if frames else None

    return {
        ServePhase.start: frames[start_idx] if start_idx is not None else None,
        ServePhase.release: frames[release_idx] if release_idx is not None else None,
        ServePhase.trophy_pose: frames[trophy_idx] if trophy_idx is not None else None,
        ServePhase.racket_drop: frames[drop_idx] if drop_idx is not None else None,
        ServePhase.contact: frames[contact_idx] if contact_idx is not None else None,
        ServePhase.finish: frames[finish_idx] if finish_idx is not None else None,
    }
