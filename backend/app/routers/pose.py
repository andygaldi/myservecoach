from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

from app.models import Frame, PoseResponse
from app.services.pose_model import RTMPoseModel, decode_image, get_pose_model

router = APIRouter()


@router.post("/pose", response_model=PoseResponse)
async def pose(
    frames: list[UploadFile] = File(...),
    timestamps: list[float] = Form(...),
    session_id: str | None = Form(None),
    pose_model: RTMPoseModel = Depends(get_pose_model),
) -> PoseResponse:
    if len(frames) != len(timestamps):
        raise HTTPException(400, "frames and timestamps must be the same length")

    result_frames: list[Frame] = []
    for upload, timestamp in zip(frames, timestamps):
        raw = await upload.read()
        image = decode_image(raw)
        if image is None:
            raise HTTPException(400, "invalid image data")
        keypoints = pose_model.infer(image)
        result_frames.append(Frame(timestamp=timestamp, keypoints=keypoints))

    return PoseResponse(frames=result_frames)
