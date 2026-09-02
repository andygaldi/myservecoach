from fastapi import APIRouter, HTTPException
from app.models import AnalyzeRequest, AnalyzeResponse
from app.engine.scoring import UnknownGoalRuleId, score_segment

router = APIRouter()


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    try:
        return score_segment(
            request.frames, request.detections, goal_rule_id=request.goal_rule_id
        )
    except UnknownGoalRuleId as e:
        raise HTTPException(400, str(e))
