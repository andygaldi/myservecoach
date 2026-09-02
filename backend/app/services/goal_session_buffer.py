from dataclasses import dataclass, field

from app.models import Detection, Frame

# Matches CameraService's Pro 2D live-recording lock (720x1280@30fps) — see
# backend/app/routers/segment.py's DEFAULT_STRIDE and CameraService.swift's _configure. Used
# only to convert each chunk's locally-zeroed sample timestamps into the buffer's running
# clock; a session recorded at a different fps would drift, matching the same fixed-fps
# assumption Pro 2D already relies on elsewhere.
_CHUNK_FPS = 30.0


@dataclass
class _SessionBuffer:
    frames: list[Frame] = field(default_factory=list)
    detections: list[list[Detection]] = field(default_factory=list)
    reported_count: int = 0
    next_offset: float = 0.0


_SESSIONS: dict[str, _SessionBuffer] = {}


def append_chunk(
    session_id: str,
    stride: int,
    sampled: list[tuple[float, Frame, list[Detection]]],
) -> _SessionBuffer:
    """Appends one chunk's (local_timestamp, frame, detections) triples to session_id's buffer,
    offsetting each frame's timestamp by the buffer's running clock so chunk boundaries don't
    reset time to 0. Frame objects are rebuilt with the offset timestamp (Frame is immutable
    enough that reconstruction, not mutation, is simplest).
    """
    buffer = _SESSIONS.setdefault(session_id, _SessionBuffer())
    for local_ts, frame, dets in sampled:
        buffer.frames.append(Frame(timestamp=buffer.next_offset + local_ts, keypoints=frame.keypoints))
        buffer.detections.append(dets)
    buffer.next_offset += len(sampled) * (stride / _CHUNK_FPS)
    return buffer


def evict(session_id: str) -> None:
    """Removes session_id's buffer entry, if present. No-op if already evicted/missing."""
    _SESSIONS.pop(session_id, None)


def clear_all() -> None:
    """Test-only reset of the module-global dict — this buffer is process-lifetime, so tests
    must not leak state into each other via the same import."""
    _SESSIONS.clear()
