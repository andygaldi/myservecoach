from app.models import Frame, ServePhase
from app.engine.angles import keypoint_y

HANDEDNESS: dict[str, str] = {"hitting": "right", "toss": "left"}


def detect_phases(frames: list[Frame]) -> dict[ServePhase, Frame | None]:
    hitting = HANDEDNESS["hitting"]
    toss = HANDEDNESS["toss"]

    # 1. Trophy pose: earliest frame where toss wrist is above shoulder
    #    and both wrists are above hip level.
    #    Elbow angle is intentionally NOT checked here — it is evaluated as a
    #    rule so players with a wrong elbow position still receive feedback.
    trophy_idx: int | None = None
    for i, frame in enumerate(frames):
        toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
        toss_shoulder_y = keypoint_y(frame, f"{toss}_shoulder")
        hitting_wrist_y = keypoint_y(frame, f"{hitting}_wrist")
        hitting_hip_y = keypoint_y(frame, f"{hitting}_hip")

        if any(v is None for v in [toss_wrist_y, toss_shoulder_y, hitting_wrist_y, hitting_hip_y]):
            continue
        if toss_wrist_y <= toss_shoulder_y:
            continue
        if toss_wrist_y <= hitting_hip_y or hitting_wrist_y <= hitting_hip_y:
            continue
        trophy_idx = i
        break

    # 2. Racket drop: minimum hitting-wrist y, only frames after trophy
    drop_idx: int | None = None
    if trophy_idx is not None:
        min_y = float("inf")
        for i in range(trophy_idx + 1, len(frames)):
            w_y = keypoint_y(frames[i], f"{hitting}_wrist")
            if w_y is not None and w_y < min_y:
                min_y = w_y
                drop_idx = i

    # 3. Contact: maximum hitting-wrist y; after racket drop if detected, else full sequence
    contact_search_start = (drop_idx + 1) if drop_idx is not None else 0
    contact_idx: int | None = None
    max_y = float("-inf")
    for i in range(contact_search_start, len(frames)):
        w_y = keypoint_y(frames[i], f"{hitting}_wrist")
        if w_y is not None and w_y > max_y:
            max_y = w_y
            contact_idx = i

    return {
        ServePhase.trophy_pose: frames[trophy_idx] if trophy_idx is not None else None,
        ServePhase.racket_drop: frames[drop_idx] if drop_idx is not None else None,
        ServePhase.contact: frames[contact_idx] if contact_idx is not None else None,
    }
