import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request

from app.models import Frame, GoalChunkResponse, GoalChunkResult, GoalPhaseFrame
from app.engine.phases import MIN_PEAK_SEPARATION_SECONDS, segment_serves_with_peaks, slice_detections_by_segments
from app.engine.rules import RULE_IDS
from app.engine.scoring import score_segment
from app.routers.segment import DEFAULT_STRIDE
from app.services import goal_session_buffer
from app.services.object_detection import ObjectDetectionModel, get_object_detection_model
from app.services.pose_model import RTMPoseModel, get_pose_model
from app.services.video_sampler import sample_video_frames

router = APIRouter()

# A segment is safe to score and speak once its peak is at least this far behind the buffer's
# trailing edge — old enough that it cannot be a spurious edge-of-buffer artifact (see
# latency-findings.md Blocker A). Reuses phases.py's own "two peaks this close are the same
# serve" distance rather than inventing a second constant.
CONFIRM_LAG_SECONDS = MIN_PEAK_SEPARATION_SECONDS


async def _read_body(request: Request) -> bytes:
    """Reads the raw chunk body as an async FastAPI dependency, resolved on the event loop
    before the sync `goal_session_chunk` handler below runs in a threadpool — keeps the only I/O
    wait off the CPU-bound path without making the handler itself `async def` (see the latency
    note on `goal_session_chunk`).
    """
    return await request.body()


@router.post("/goal/session/chunk", response_model=GoalChunkResponse)
def goal_session_chunk(  # sync def, not async — see latency note below
    session_id: str,
    goal_rule_id: str,
    body: bytes = Depends(_read_body),
    stride: int = DEFAULT_STRIDE,
    is_final: bool = False,
    pose_model: RTMPoseModel = Depends(get_pose_model),
    detection_model: ObjectDetectionModel = Depends(get_object_detection_model),
) -> GoalChunkResponse:
    """Accepts one chunk of a live Set Goal recording, appends it to the session's growing
    frame/detection buffer, and returns the goal result for every serve segment newly confirmed
    since the last chunk.

    Latency note (`latency-findings.md`): this handler is a plain `def`, not `async def` — as
    originally planned it would be `async def` with synchronous CPU-bound inference inline,
    which stalls FastAPI's event loop for every concurrent request including a queued
    `is_final=true` chunk. FastAPI runs sync `def` route handlers in a threadpool automatically,
    so this is the fix, not `run_in_threadpool` inside an `async def`.
    """
    if goal_rule_id not in RULE_IDS:
        raise HTTPException(400, f"unknown goal_rule_id: {goal_rule_id!r}")

    with tempfile.NamedTemporaryFile(suffix=".mov", delete=False) as tmp:
        tmp_path = Path(tmp.name)
        tmp.write(body)

    try:
        try:
            sampled = sample_video_frames(tmp_path, stride)
        except ValueError:
            raise HTTPException(400, "could not open video")

        chunk_triples: list[tuple[float, Frame, list]] = []
        for ts, img in sampled:
            detections, person_bbox = detection_model.infer_with_person(img)
            keypoints = pose_model.infer(img, person_bbox=person_bbox)
            chunk_triples.append((ts, Frame(timestamp=ts, keypoints=keypoints), detections))

        buffer = goal_session_buffer.append_chunk(session_id, stride, chunk_triples)

        segments_with_peaks = segment_serves_with_peaks(buffer.frames)
        segments = [segment for segment, _ in segments_with_peaks]
        seg_detections = slice_detections_by_segments(buffer.detections, segments)

        if is_final:
            confirmed_count = len(segments_with_peaks)
        else:
            buffer_end = buffer.frames[-1].timestamp if buffer.frames else 0.0
            confirmed_count = sum(
                1 for _, peak_ts in segments_with_peaks if peak_ts <= buffer_end - CONFIRM_LAG_SECONDS
            )

        results: list[GoalChunkResult] = []
        for i in range(buffer.reported_count, confirmed_count):
            scored = score_segment(segments[i], seg_detections[i], goal_rule_id=goal_rule_id)
            phase_detection = next(
                (p for p in scored.phases if p.phase == scored.goal_result.phase), None
            )
            phase_frame = None
            if phase_detection is not None:
                phase_frame = GoalPhaseFrame(
                    frame=segments[i][phase_detection.frame_index],
                    detections=(
                        seg_detections[i][phase_detection.frame_index] if seg_detections[i] else []
                    ),
                )
            results.append(
                GoalChunkResult(segment_index=i, goal_result=scored.goal_result, phase_frame=phase_frame)
            )
        buffer.reported_count = confirmed_count

        if is_final:
            goal_session_buffer.evict(session_id)

        return GoalChunkResponse(results=results)
    finally:
        tmp_path.unlink(missing_ok=True)
