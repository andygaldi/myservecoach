from dataclasses import dataclass, field

from app.models import Detection, Frame


@dataclass
class _SessionBuffer:
    frames: list[Frame] = field(default_factory=list)
    detections: list[list[Detection]] = field(default_factory=list)
    reported_count: int = 0
    next_offset: float = 0.0


_SESSIONS: dict[str, _SessionBuffer] = {}


def append_chunk(
    session_id: str,
    chunk_duration: float,
    sampled: list[tuple[float, Frame, list[Detection]]],
) -> _SessionBuffer:
    """Appends one chunk's (local_timestamp, frame, detections) triples to session_id's buffer,
    offsetting each frame's timestamp by the buffer's running clock so chunk boundaries don't
    reset time to 0. Frame objects are rebuilt with the offset timestamp (Frame is immutable
    enough that reconstruction, not mutation, is simplest).

    `chunk_duration` must be the chunk video's real duration (video_sampler.video_duration_seconds),
    not derived from stride/sampled-frame-count — an approximation there drifts cumulatively
    across chunks, since it ignores each chunk's true fps and any unsampled tail frames.
    """
    buffer = _SESSIONS.setdefault(session_id, _SessionBuffer())
    for local_ts, frame, dets in sampled:
        buffer.frames.append(Frame(timestamp=buffer.next_offset + local_ts, keypoints=frame.keypoints))
        buffer.detections.append(dets)
    buffer.next_offset += chunk_duration
    return buffer


def evict(session_id: str) -> None:
    """Removes session_id's buffer entry, if present. No-op if already evicted/missing."""
    _SESSIONS.pop(session_id, None)


def clear_all() -> None:
    """Test-only reset of the module-global dict — this buffer is process-lifetime, so tests
    must not leak state into each other via the same import."""
    _SESSIONS.clear()
