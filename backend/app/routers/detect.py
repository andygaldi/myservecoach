from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

from app.models import DetectionFrame, DetectResponse
from app.services.object_detection import ObjectDetectionModel, get_object_detection_model
from app.services.pose_model import decode_image

router = APIRouter()


@router.post("/detect", response_model=DetectResponse)
async def detect(
    frames: list[UploadFile] = File(...),
    timestamps: list[float] = Form(...),
    session_id: str | None = Form(None),
    detection_model: ObjectDetectionModel = Depends(get_object_detection_model),
) -> DetectResponse:
    if len(frames) != len(timestamps):
        raise HTTPException(400, "frames and timestamps must be the same length")

    result_frames: list[DetectionFrame] = []
    for upload, timestamp in zip(frames, timestamps):
        raw = await upload.read()
        image = decode_image(raw)
        if image is None:
            raise HTTPException(400, "invalid image data")
        detections = detection_model.infer(image)
        result_frames.append(DetectionFrame(timestamp=timestamp, detections=detections))

    return DetectResponse(frames=result_frames)
