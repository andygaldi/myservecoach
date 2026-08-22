from app.models import Frame, Keypoint


def make_frame(keypoints: dict, timestamp: float = 0.0) -> Frame:
    return Frame(timestamp=timestamp, keypoints={k: Keypoint(**v) for k, v in keypoints.items()})


# Shared body-relative geometry for segment_serves' hitting-wrist-peak fixtures (test_segment_serves.py,
# test_segment_endpoint.py): a constant neck/pelvis pair sets a constant floor (see
# _hitting_wrist_floor_score in app.engine.phases), and only the hitting wrist's height varies.
NECK_Y = 0.7
PELVIS_Y = 0.4
IDLE_WRIST_Y = 0.5  # well below the floor — resting arm height, never a peak candidate
PEAK_WRIST_Y = 0.95  # well above the floor — a genuine serve's contact-height wrist


def kp(y: float, x: float = 0.5, confidence: float = 0.9) -> dict:
    return {"x": x, "y": y, "confidence": confidence}


def positioned_frame(wrist_y: float, timestamp: float) -> Frame:
    return make_frame(
        {"neck": kp(NECK_Y), "pelvis": kp(PELVIS_Y), "right_wrist": kp(wrist_y)}, timestamp
    )


def hump(peak_y: float, count: int, start_index: int, fps: float, base_y: float = IDLE_WRIST_Y) -> list:
    """`count` frames rising linearly to `peak_y` at the midpoint, then falling back to `base_y` —
    a single triangular hump in wrist height, crossing the body-relative floor once if `peak_y`
    is above it."""
    frames = []
    for i in range(count):
        progress = i / (count - 1) if count > 1 else 1.0
        triangle = 1 - abs(2 * progress - 1)  # 0 -> 1 -> 0
        wrist_y = base_y + (peak_y - base_y) * triangle
        frames.append(positioned_frame(wrist_y, (start_index + i) / fps))
    return frames


def rest_burst(wrist_y: float, count: int, start_index: int, fps: float) -> list:
    return [positioned_frame(wrist_y, (start_index + i) / fps) for i in range(count)]
