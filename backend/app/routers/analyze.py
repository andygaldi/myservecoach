from fastapi import APIRouter
from app.models import AnalyzeRequest, AnalyzeResponse, ServePhase
from app.engine.phases import detect_phases
from app.engine.rules import evaluate_rules

router = APIRouter()

_CLEAN_SERVE_SUMMARY = "No major issues detected — good serve!"


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    phase_frames = detect_phases(request.frames)
    cues = evaluate_rules(phase_frames)
    trophy_detected = phase_frames.get(ServePhase.trophy_pose) is not None
    summary = _CLEAN_SERVE_SUMMARY if (not cues and trophy_detected) else None
    return AnalyzeResponse(cues=cues, summary=summary)
