from app.models import Frame, Keypoint


def make_frame(keypoints: dict, timestamp: float = 0.0) -> Frame:
    return Frame(timestamp=timestamp, keypoints={k: Keypoint(**v) for k, v in keypoints.items()})
