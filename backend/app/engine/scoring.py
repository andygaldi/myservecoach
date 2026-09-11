from app.models import AnalyzeResponse, Detection, Frame, GoalResult, PhaseDetection, ServePhase
from app.engine.goal_cues import directional_spoken_cue
from app.engine.phases import detect_phases
from app.engine.rules import RULE_IDS, RULES_BY_ID, evaluate_rules

_GOAL_PASS_MESSAGE = "Nice serve — goal met!"
_CLEAN_SERVE_SUMMARY = "No major issues detected — good serve!"


class UnknownGoalRuleId(ValueError):
    """Raised when a request's goal_rule_id doesn't match any rule in rules.json."""


def score_segment(
    frames: list[Frame],
    detections: list[list[Detection]] | None = None,
    goal_rule_id: str | None = None,
    view: str = "open_side",
) -> AnalyzeResponse:
    """One serve segment's full scoring: phase detection, rule evaluation, and (when
    goal_rule_id is set) the pass/fail goal check. Called by both POST /v1/analyze (one segment
    per request) and the goal session chunk endpoint (one call per newly-confirmed segment) —
    the single scoring code path both share.
    """
    if goal_rule_id is not None and goal_rule_id not in RULE_IDS:
        raise UnknownGoalRuleId(f"unknown goal_rule_id: {goal_rule_id!r}")

    phase_frames = detect_phases(frames, detections)

    # Both joins below key on object identity rather than timestamp: detect_phases returns the
    # very Frame objects it was handed, and two frames sharing a timestamp would otherwise
    # collide — the later one silently winning for both, so a phase could be scored against a
    # different frame's ball position.
    frame_indices = {id(frame): i for i, frame in enumerate(frames)}
    id_to_detections = {id(frame): dets for frame, dets in zip(frames, detections or [])}
    phase_detections = {
        phase: id_to_detections.get(id(frame))
        for phase, frame in phase_frames.items()
        if frame is not None
    }
    cues = evaluate_rules(phase_frames, phase_detections, view=view)

    # Where each detected phase landed, in ServePhase declaration order.
    phases = [
        PhaseDetection(phase=phase, frame_index=index, timestamp=frame.timestamp)
        for phase in ServePhase
        if (frame := phase_frames.get(phase)) is not None
        and (index := frame_indices.get(id(frame))) is not None
    ]

    trophy_detected = phase_frames.get(ServePhase.trophy_pose) is not None
    summary = _CLEAN_SERVE_SUMMARY if (not cues and trophy_detected) else None

    goal_result = None
    if goal_rule_id is not None:
        firing = next((c for c in cues if c.rule_id == goal_rule_id), None)
        goal_rule = RULES_BY_ID[goal_rule_id]
        if firing is None:
            spoken_cue = _GOAL_PASS_MESSAGE
        elif firing.measured_value is not None:
            spoken_cue = directional_spoken_cue(
                goal_rule, firing.measured_value, phase_frames.get(goal_rule.phase)
            )
        else:
            spoken_cue = firing.message
        goal_result = GoalResult(
            passed=firing is None,
            spoken_cue=spoken_cue,
            phase=goal_rule.phase,
            cue=firing,
        )

    return AnalyzeResponse(cues=cues, summary=summary, phases=phases, goal_result=goal_result)
