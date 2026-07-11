from fastapi import APIRouter

from app.models import SegmentRequest, SegmentResponse, ServeSegment
from app.engine.phases import segment_serves, slice_detections_by_segments

router = APIRouter()


@router.post("/segment", response_model=SegmentResponse)
async def segment(request: SegmentRequest) -> SegmentResponse:
    serve_frames = segment_serves(request.frames)
    if request.detections is not None:
        serve_detections = slice_detections_by_segments(request.detections, serve_frames)
    else:
        serve_detections = [None] * len(serve_frames)
    segments = [
        ServeSegment(frames=frames, detections=dets)
        for frames, dets in zip(serve_frames, serve_detections)
    ]
    return SegmentResponse(segments=segments)
