from enum import Enum
from pydantic import BaseModel, Field


class Keypoint(BaseModel):
    x: float
    y: float
    confidence: float


class Frame(BaseModel):
    timestamp: float
    keypoints: dict[str, Keypoint]


class AnalyzeRequest(BaseModel):
    frames: list[Frame] = Field(min_length=1)
    session_id: str | None = None


class ServePhase(str, Enum):
    trophy_pose = "trophy_pose"
    racket_drop = "racket_drop"
    contact = "contact"


class Severity(str, Enum):
    major = "major"
    minor = "minor"


class Cue(BaseModel):
    phase: ServePhase
    message: str
    severity: Severity


class AnalyzeResponse(BaseModel):
    cues: list[Cue] = Field(min_length=1)
