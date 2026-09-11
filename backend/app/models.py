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
    goal_rule_id: str | None = None


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
    # Deviation detail (P6c): the measured value that failed the rule, plus the rule's own
    # metric/joints/threshold spec, so a client can render "measured 62° · target ≤45°" and draw
    # the measured segment without a hardcoded rule_id → visual mapping of its own. All optional
    # so a Cue can still be constructed from rule identity alone.
    metric: str | None = None
    joints: list[str] = Field(default_factory=list)
    measured_value: float | None = None
    comparison: str | None = None
    threshold: float | None = None
    threshold_min: float | None = None
    threshold_max: float | None = None


class PhaseDetection(BaseModel):
    """Where a detected phase landed in the request's frame list.

    Keypoints are deliberately not repeated here — a client that posted the frames already has
    them, and `frame_index`/`timestamp` are enough to join back to the original frame.
    """

    phase: ServePhase
    frame_index: int
    timestamp: float


class GoalResult(BaseModel):
    passed: bool
    spoken_cue: str
    # Always populated — the ServePhase the goal's own rule targets (not always contact). `cue`
    # is the full firing Cue on a miss (for the failing-joint highlight), None on a pass.
    phase: ServePhase
    cue: Cue | None = None


class AnalyzeResponse(BaseModel):
    cues: list[Cue] = Field(default_factory=list)
    summary: str | None = None
    phases: list[PhaseDetection] = Field(default_factory=list)
    goal_result: GoalResult | None = None


class GoalPhaseFrame(BaseModel):
    frame: Frame
    detections: list[Detection] = Field(default_factory=list)


class GoalChunkResult(BaseModel):
    segment_index: int
    goal_result: GoalResult
    # None when the goal's own phase was never detected in this segment — the existing
    # "frame still shows without a skeleton" tolerance, not an error case.
    phase_frame: GoalPhaseFrame | None = None


class GoalChunkResponse(BaseModel):
    results: list[GoalChunkResult] = Field(default_factory=list)


class PoseResponse(BaseModel):
    frames: list[Frame]


class DetectionFrame(BaseModel):
    timestamp: float
    detections: list[Detection]


class DetectResponse(BaseModel):
    frames: list[DetectionFrame]
