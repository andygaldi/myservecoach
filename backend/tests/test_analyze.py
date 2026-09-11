import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.models import AnalyzeResponse, Frame, ServePhase
from app.engine.phases import detect_phases
from app.engine.goal_cues import directional_spoken_cue
from app.engine.rules import _Rule, RULES_BY_ID
import app.engine.rules as rules_module

VALID_FRAME = {
    "timestamp": 0.0,
    "keypoints": {
        "right_wrist": {"x": 0.5, "y": 0.3, "confidence": 0.9},
    },
}

# Trophy pose frame with ~72° hitting arm — inside [70°,110°] for trophy detection
# but outside [80°,110°] for the rule. shoulder(0.5,0.7)→elbow(0.5,0.5)→wrist(0.8,0.6):
# ba=(0,0.2), bc=(0.3,0.1) → ~72°. Rule trophy_racket_elbow_flexion fires because ~72° ∉ [80°,110°].
BAD_ELBOW_FRAME = {
    "timestamp": 0.0,
    "keypoints": {
        "right_shoulder": {"x": 0.5, "y": 0.7, "confidence": 0.9},
        "right_elbow":    {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "right_wrist":    {"x": 0.8, "y": 0.6, "confidence": 0.9},
        "right_hip":      {"x": 0.5, "y": 0.3, "confidence": 0.9},
        "left_wrist":     {"x": 0.3, "y": 0.8, "confidence": 0.9},
        "left_shoulder":  {"x": 0.4, "y": 0.65, "confidence": 0.9},
    },
}

# A 3-frame sequence where all rules pass — trophy detected, no cues fired.
# Trophy: shoulder(0.8,0.5)→elbow(0.6,0.5)→wrist(0.6,0.7): 90° ∈ [70°,110°]; wrist above elbow and hip
# Racket drop: frame 1 has no elbow data → drop is None → racket_drop_depth rule skipped
# Contact: collinear → 180° ≥ 150°, wrist y=0.9 above shoulder y=0.5
CLEAN_SERVE_FRAMES = [
    {
        "timestamp": 0.0,
        "keypoints": {
            "right_shoulder": {"x": 0.8, "y": 0.5, "confidence": 0.9},
            "right_elbow":    {"x": 0.6, "y": 0.5, "confidence": 0.9},
            "right_wrist":    {"x": 0.6, "y": 0.7, "confidence": 0.9},
            "right_hip":      {"x": 0.5, "y": 0.3, "confidence": 0.9},
            "left_wrist":     {"x": 0.3, "y": 0.8, "confidence": 0.9},
            "left_shoulder":  {"x": 0.4, "y": 0.65, "confidence": 0.9},
        },
    },
    {
        "timestamp": 1.0,
        "keypoints": {
            "right_wrist": {"x": 0.3, "y": 0.1, "confidence": 0.9},
            "right_hip":   {"x": 0.5, "y": 0.3, "confidence": 0.9},
        },
    },
    {
        "timestamp": 2.0,
        "keypoints": {
            "right_shoulder": {"x": 0.5, "y": 0.5, "confidence": 0.9},
            "right_elbow":    {"x": 0.5, "y": 0.7, "confidence": 0.9},
            "right_wrist":    {"x": 0.5, "y": 0.9, "confidence": 0.9},
        },
    },
]


@pytest.fixture
def transport():
    return ASGITransport(app=app)


@pytest.mark.asyncio
async def test_valid_payload_returns_200(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [VALID_FRAME]})
    assert response.status_code == 200
    # Frame has insufficient pose data — just verify the response parses without error
    AnalyzeResponse.model_validate(response.json())


@pytest.mark.asyncio
async def test_empty_frames_returns_422(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": []})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_missing_keypoints_returns_422(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [{"timestamp": 0.0}]})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_extra_keypoint_fields_ignored(transport):
    frame = {
        "timestamp": 0.0,
        "keypoints": {
            "right_wrist": {"x": 0.5, "y": 0.3, "confidence": 0.9, "unknown_field": "ignored"},
        },
    }
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [frame]})
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_no_detected_phases_returns_empty_response(transport):
    # VALID_FRAME has insufficient pose data → no trophy detected → cues=[], summary=None
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [VALID_FRAME]})
    body = AnalyzeResponse.model_validate(response.json())
    assert body.cues == []
    assert body.summary is None


@pytest.mark.asyncio
async def test_clean_serve_returns_good_serve_summary(transport, monkeypatch):
    # Router-wiring test, decoupled from rules.json's tunable calibrated content (Phase P5):
    # with no rules loaded at all, a detected trophy pose and zero cues must still produce the
    # "good serve" summary — this is the /analyze router's own logic, not a rules.json fact.
    monkeypatch.setattr(rules_module, "_RULES", [])
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": CLEAN_SERVE_FRAMES})
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert body.cues == []
    assert body.summary is not None
    assert "good serve" in body.summary.lower()


@pytest.mark.asyncio
async def test_trophy_rule_violation_returns_cue(transport, monkeypatch):
    # Router-wiring test, decoupled from rules.json's tunable calibrated content (Phase P5):
    # a monkeypatched rule keyed to BAD_ELBOW_FRAME's known ~72° hitting-arm angle confirms a
    # rule violation on a real detected trophy frame surfaces as a cue through the full
    # request/response cycle, independent of whatever the real calibrated rules.json holds.
    fixture_rule = _Rule(
        id="test_elbow_flexion",
        phase="trophy_pose",
        metric="angle",
        joints=["right_shoulder", "right_elbow", "right_wrist"],
        comparison="range",
        threshold_min=80,
        threshold_max=110,
        severity="major",
        message="test elbow flexion cue",
        view="open_side",
    )
    monkeypatch.setattr(rules_module, "_RULES", [fixture_rule])
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [BAD_ELBOW_FRAME]})
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert len(body.cues) == 1
    assert body.cues[0].rule_id == "test_elbow_flexion"
    assert body.cues[0].phase == "trophy_pose"
    assert body.cues[0].severity == "major"
    assert body.summary is None


# --- Extended contract: optional `detections` field ---

@pytest.mark.asyncio
async def test_detections_field_accepted_returns_200(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/analyze",
            json={"frames": [VALID_FRAME], "detections": [[]]},
        )
    assert response.status_code == 200
    AnalyzeResponse.model_validate(response.json())


@pytest.mark.asyncio
async def test_detections_field_omitted_still_returns_200(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [VALID_FRAME]})
    assert response.status_code == 200
    AnalyzeResponse.model_validate(response.json())


# --- Phase -> detections wiring (a ball_offset_* rule can only fire through /analyze's
#     phase_detections plumbing, not from keypoints alone) ---

# Resolves to ServePhase.contact only (no trophy/release/racket_drop signals present, so
# contact_search_start falls back to 0) via the wrist-height-only contact search.
CONTACT_ONLY_FRAME = {
    "timestamp": 0.0,
    "keypoints": {
        "right_wrist":   {"x": 0.5, "y": 0.5, "confidence": 0.9},
        "left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9},
    },
}

BALL_OFFSET_RULE = _Rule(
    id="ball_offset_rule",
    phase="contact",
    metric="ball_offset_y",
    joints=["left_shoulder"],
    comparison="gte",
    threshold=999.0,  # always fails once a value is computed
    severity="major",
    message="ball offset fired",
    view="open_side",
)


@pytest.mark.asyncio
async def test_ball_offset_rule_fires_via_analyze_detections(transport, monkeypatch):
    monkeypatch.setattr(rules_module, "_RULES", [BALL_OFFSET_RULE])
    ball_detection = {"label": "ball", "confidence": 0.9, "bbox": {"x_min": 0.35, "y_min": 0.75, "x_max": 0.45, "y_max": 0.85}}
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/analyze",
            json={"frames": [CONTACT_ONLY_FRAME], "detections": [[ball_detection]]},
        )
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert len(body.cues) == 1
    assert body.cues[0].rule_id == "ball_offset_rule"


@pytest.mark.asyncio
async def test_ball_offset_rule_does_not_fire_without_detections(transport, monkeypatch):
    monkeypatch.setattr(rules_module, "_RULES", [BALL_OFFSET_RULE])
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": [CONTACT_ONLY_FRAME]})
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert body.cues == []


@pytest.mark.asyncio
async def test_duplicate_timestamps_join_detections_by_identity(transport, monkeypatch):
    """Two frames sharing a timestamp each keep their own detections.

    /analyze joins detections to phase frames by `id(frame)`. Keying that join on
    `frame.timestamp` instead lets the later of two same-timestamped frames silently win for
    both, scoring a phase against a different frame's ball position. Rigged so the two
    orderings disagree: contact resolves to frame 0 (higher wrist), while a timestamp-keyed
    dict would hand it frame 1's ball.
    """
    monkeypatch.setattr(rules_module, "_RULES", [BALL_OFFSET_RULE])
    frames = [
        {
            "timestamp": 0.0,
            "keypoints": {
                "right_wrist":   {"x": 0.5, "y": 0.9, "confidence": 0.9},
                "left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9},
            },
        },
        {
            "timestamp": 0.0,  # deliberate collision with frame 0
            "keypoints": {
                "right_wrist":   {"x": 0.5, "y": 0.5, "confidence": 0.9},
                "left_shoulder": {"x": 0.4, "y": 0.6, "confidence": 0.9},
            },
        },
    ]
    detections = [
        [{"label": "ball", "confidence": 0.9, "bbox": {"x_min": 0.35, "y_min": 0.80, "x_max": 0.45, "y_max": 0.90}}],
        [{"label": "ball", "confidence": 0.9, "bbox": {"x_min": 0.35, "y_min": 0.05, "x_max": 0.45, "y_max": 0.15}}],
    ]
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/analyze", json={"frames": frames, "detections": detections}
        )
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())

    assert [p.frame_index for p in body.phases if p.phase == ServePhase.contact] == [0]
    assert len(body.cues) == 1
    # frame 0's ball (center y 0.85) minus left_shoulder y 0.6. The timestamp-keyed join would
    # yield frame 1's ball instead: 0.10 - 0.6 = -0.50.
    assert body.cues[0].measured_value == pytest.approx(0.25)


# --- Detected-phase timing (P6c) ---


@pytest.mark.asyncio
async def test_phases_reports_index_and_timestamp_for_each_detected_phase(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": CLEAN_SERVE_FRAMES})
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())

    assert body.phases, "expected at least one detected phase for a clean serve sequence"
    for entry in body.phases:
        assert 0 <= entry.frame_index < len(CLEAN_SERVE_FRAMES)
        # The index must join back to a frame whose timestamp matches the reported one.
        assert CLEAN_SERVE_FRAMES[entry.frame_index]["timestamp"] == entry.timestamp


@pytest.mark.asyncio
async def test_phases_matches_detect_phases_output_exactly(transport):
    """Only phases detect_phases actually resolved appear — no sentinel entries for None."""
    frames = [Frame.model_validate(f) for f in CLEAN_SERVE_FRAMES]
    expected = {phase for phase, frame in detect_phases(frames).items() if frame is not None}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": CLEAN_SERVE_FRAMES})
    body = AnalyzeResponse.model_validate(response.json())

    assert {entry.phase for entry in body.phases} == expected


@pytest.mark.asyncio
async def test_phases_are_ordered_by_serve_phase_declaration(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": CLEAN_SERVE_FRAMES})
    body = AnalyzeResponse.model_validate(response.json())

    declaration_order = list(ServePhase)
    indices = [declaration_order.index(entry.phase) for entry in body.phases]
    assert indices == sorted(indices)


@pytest.mark.asyncio
async def test_cue_deviation_detail_survives_the_wire(transport, monkeypatch):
    """The deviation fields evaluate_rules attaches are serialized by the endpoint, not dropped."""
    monkeypatch.setattr(rules_module, "_RULES", [BALL_OFFSET_RULE])
    ball_detection = {"label": "ball", "confidence": 0.9, "bbox": {"x_min": 0.35, "y_min": 0.75, "x_max": 0.45, "y_max": 0.85}}
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/analyze",
            json={"frames": [CONTACT_ONLY_FRAME], "detections": [[ball_detection]]},
        )
    body = AnalyzeResponse.model_validate(response.json())
    cue = body.cues[0]
    assert cue.metric == BALL_OFFSET_RULE.metric
    assert cue.joints == BALL_OFFSET_RULE.joints
    assert cue.comparison == BALL_OFFSET_RULE.comparison
    assert cue.threshold == BALL_OFFSET_RULE.threshold
    assert cue.measured_value is not None


# --- goal_rule_id / goal_result (P7 Set Goal extension) ---


@pytest.mark.asyncio
async def test_goal_rule_id_matching_firing_rule_returns_failed_goal_result(transport):
    # trophy_hitting_elbow_shoulder_line fires on BAD_ELBOW_FRAME's real rules.json rule (~63°,
    # outside the [155,180] range) — see phases/2026-08-28-p7-goal-library-set-goal-2d.
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/analyze",
            json={
                "frames": [BAD_ELBOW_FRAME],
                "goal_rule_id": "trophy_hitting_elbow_shoulder_line",
            },
        )
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    firing_cue = next(c for c in body.cues if c.rule_id == "trophy_hitting_elbow_shoulder_line")
    assert body.goal_result is not None
    assert body.goal_result.passed is False
    rule = RULES_BY_ID["trophy_hitting_elbow_shoulder_line"]
    # BAD_ELBOW_FRAME's right_elbow (y=0.5) sits well above its shoulder line (y~0.65-0.7) -> "too
    # high" -> the "Lower" phrase, not the frame-blind generic message.
    assert body.goal_result.spoken_cue == "Lower your hitting elbow to line up with your shoulders."
    assert body.goal_result.spoken_cue == directional_spoken_cue(
        rule, firing_cue.measured_value, Frame.model_validate(BAD_ELBOW_FRAME)
    )
    assert body.goal_result.spoken_cue != firing_cue.message


@pytest.mark.asyncio
async def test_goal_rule_id_not_firing_returns_passed_goal_result(transport):
    # trophy_toss_arm_straight does not fire on CLEAN_SERVE_FRAMES (only
    # trophy_hitting_elbow_shoulder_line does), so the goal check passes.
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/analyze",
            json={"frames": CLEAN_SERVE_FRAMES, "goal_rule_id": "trophy_toss_arm_straight"},
        )
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert body.goal_result is not None
    assert body.goal_result.passed is True
    assert body.goal_result.spoken_cue == "Nice serve — goal met!"


@pytest.mark.asyncio
async def test_unrecognized_goal_rule_id_returns_400(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/analyze", json={"frames": [VALID_FRAME], "goal_rule_id": "not_a_real_rule"}
        )
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_no_goal_rule_id_returns_none_goal_result(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/v1/analyze", json={"frames": CLEAN_SERVE_FRAMES})
    assert response.status_code == 200
    body = AnalyzeResponse.model_validate(response.json())
    assert body.goal_result is None
