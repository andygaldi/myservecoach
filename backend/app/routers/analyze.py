from fastapi import APIRouter
from app.models import AnalyzeRequest, AnalyzeResponse, Cue, ServePhase, Severity

router = APIRouter()


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    cues = [
        Cue(
            phase=ServePhase.trophy_pose,
            message="Raise your tossing arm higher at trophy pose — elbow should be at shoulder height.",
            severity=Severity.major,
        ),
        Cue(
            phase=ServePhase.contact,
            message="Extend fully through contact — you're cutting the swing short slightly.",
            severity=Severity.minor,
        ),
    ]
    return AnalyzeResponse(cues=cues)
