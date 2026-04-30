from fastapi import APIRouter
from app.models import AnalyzeRequest, AnalyzeResponse, Cue, ServePhase, Severity
from app.engine.phases import detect_phases
from app.engine.rules import evaluate_rules

router = APIRouter()

_CLEAN_SERVE_CUE = Cue(
    phase=ServePhase.contact,
    message="No major issues detected — good serve!",
    severity=Severity.minor,
)


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    phase_frames = detect_phases(request.frames)
    cues = evaluate_rules(phase_frames)
    if not cues:
        cues = [_CLEAN_SERVE_CUE]
    return AnalyzeResponse(cues=cues)
