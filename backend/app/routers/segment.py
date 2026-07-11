import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request

from app.models import Frame, SegmentRequest, SegmentResponse, ServeSegment
from app.engine.phases import segment_serves, slice_detections_by_segments
from app.services.object_detection import ObjectDetectionModel, get_object_detection_model
from app.services.pose_model import RTMPoseModel, get_pose_model
from app.services.video_sampler import sample_video_frames

router = APIRouter()

DEFAULT_STRIDE = 2


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


@router.post("/segment/video", response_model=SegmentResponse)
async def segment_video(
    request: Request,
    stride: int = DEFAULT_STRIDE,
    session_id: str | None = None,
    pose_model: RTMPoseModel = Depends(get_pose_model),
    detection_model: ObjectDetectionModel = Depends(get_object_detection_model),
) -> SegmentResponse:
    with tempfile.NamedTemporaryFile(suffix=".mov", delete=False) as tmp:
        tmp_path = Path(tmp.name)
        async for chunk in request.stream():
            tmp.write(chunk)

    try:
        try:
            sampled = sample_video_frames(tmp_path, stride)
        except ValueError:
            raise HTTPException(400, "could not open video")
        if not sampled:
            raise HTTPException(400, "video contains no frames")

        frames = [Frame(timestamp=ts, keypoints=pose_model.infer(img)) for ts, img in sampled]
        detections = [detection_model.infer(img) for _, img in sampled]

        serve_frames = segment_serves(frames)
        serve_detections = slice_detections_by_segments(detections, serve_frames)
        segments = [
            ServeSegment(frames=f, detections=d)
            for f, d in zip(serve_frames, serve_detections)
        ]
        return SegmentResponse(segments=segments)
    finally:
        tmp_path.unlink(missing_ok=True)
