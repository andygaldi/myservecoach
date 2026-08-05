from fastapi import APIRouter
from app.models import AnalyzeRequest, AnalyzeResponse, PhaseDetection, ServePhase
from app.engine.phases import detect_phases
from app.engine.rules import evaluate_rules

router = APIRouter()

_CLEAN_SERVE_SUMMARY = "No major issues detected — good serve!"


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    phase_frames = detect_phases(request.frames, request.detections)

    # Both joins below key on object identity rather than timestamp: detect_phases returns the
    # very Frame objects it was handed, and two frames sharing a timestamp would otherwise
    # collide — the later one silently winning for both, so a phase could be scored against a
    # different frame's ball position.
    frame_indices = {id(frame): i for i, frame in enumerate(request.frames)}
    id_to_detections = {
        id(frame): dets for frame, dets in zip(request.frames, request.detections or [])
    }
    phase_detections = {
        phase: id_to_detections.get(id(frame))
        for phase, frame in phase_frames.items()
        if frame is not None
    }
    cues = evaluate_rules(phase_frames, phase_detections)

    # Where each detected phase landed, in ServePhase declaration order.
    phases = [
        PhaseDetection(phase=phase, frame_index=index, timestamp=frame.timestamp)
        for phase in ServePhase
        if (frame := phase_frames.get(phase)) is not None
        and (index := frame_indices.get(id(frame))) is not None
    ]

    trophy_detected = phase_frames.get(ServePhase.trophy_pose) is not None
    summary = _CLEAN_SERVE_SUMMARY if (not cues and trophy_detected) else None
    return AnalyzeResponse(cues=cues, summary=summary, phases=phases)
