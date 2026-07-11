from enum import Enum
from pydantic import BaseModel, Field


class Keypoint(BaseModel):
    x: float
    y: float
    confidence: float


class Frame(BaseModel):
    timestamp: float
    keypoints: dict[str, Keypoint]


class BoundingBox(BaseModel):
    x_min: float
    y_min: float
    x_max: float
    y_max: float


class Detection(BaseModel):
    label: str
    confidence: float
    bbox: BoundingBox


class AnalyzeRequest(BaseModel):
    frames: list[Frame] = Field(min_length=1)
    detections: list[list[Detection]] | None = None
    session_id: str | None = None


class SegmentRequest(BaseModel):
    frames: list[Frame] = Field(min_length=1)
    detections: list[list[Detection]] | None = None
    session_id: str | None = None


class ServeSegment(BaseModel):
    frames: list[Frame]
    detections: list[list[Detection]] | None = None


class SegmentResponse(BaseModel):
    segments: list[ServeSegment]


class ServePhase(str, Enum):
    start = "start"
    release = "release"
    trophy_pose = "trophy_pose"
    racket_drop = "racket_drop"
    contact = "contact"
    finish = "finish"


class Severity(str, Enum):
    major = "major"
    minor = "minor"


class Cue(BaseModel):
    rule_id: str
    phase: ServePhase
    message: str
    severity: Severity


class AnalyzeResponse(BaseModel):
    cues: list[Cue] = Field(default_factory=list)
    summary: str | None = None


class PoseResponse(BaseModel):
    frames: list[Frame]


class DetectionFrame(BaseModel):
    timestamp: float
    detections: list[Detection]


class DetectResponse(BaseModel):
    frames: list[DetectionFrame]
