from app.models import Frame, ServePhase
from app.engine.angles import compute_angle, joint_xy, keypoint_y

HANDEDNESS: dict[str, str] = {"hitting": "right", "toss": "left"}


def detect_phases(frames: list[Frame]) -> dict[ServePhase, Frame | None]:
    hitting = HANDEDNESS["hitting"]
    toss = HANDEDNESS["toss"]

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

    # 3. Racket drop: frame strictly between trophy and contact where the hitting
    #    elbow y increased the most compared to the immediately preceding frame.
    drop_idx: int | None = None
    if trophy_idx is not None and contact_idx is not None:
        max_elbow_rise = float("-inf")
        for i in range(trophy_idx + 1, contact_idx):
            elbow_y_curr = keypoint_y(frames[i], f"{hitting}_elbow")
            elbow_y_prev = keypoint_y(frames[i - 1], f"{hitting}_elbow")
            if elbow_y_curr is None or elbow_y_prev is None:
                continue
            delta = elbow_y_curr - elbow_y_prev
            if delta > max_elbow_rise:
                max_elbow_rise = delta
                drop_idx = i

    return {
        ServePhase.trophy_pose: frames[trophy_idx] if trophy_idx is not None else None,
        ServePhase.racket_drop: frames[drop_idx] if drop_idx is not None else None,
        ServePhase.contact: frames[contact_idx] if contact_idx is not None else None,
    }
