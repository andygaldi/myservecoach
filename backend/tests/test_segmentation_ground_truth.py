"""Ground-truth regression test for six-frame serve-phase detection.

Runs the real off-device pose/detection pipeline against every calibration video and asserts
each detected phase frame's timestamp falls within tolerance of a hand-authored ground truth
(backend/tools/segmentation_ground_truth.json). Opt-in and gated like P1/P2's model-integration
tests, since it needs real models plus the gitignored local calibration videos — not a general
CV accuracy benchmark (that's P18's job), just a catch for regressions to the phase-detection
heuristics this phase tuned.

Tolerance is tiered per phase (`phase_tolerances` in the ground truth JSON, falling back to the
scalar `tolerance_seconds` for any phase not listed): release/contact are precise singular
moments and get the tightest tolerance; trophy_pose/racket_drop are less strictly defined and
get a medium tolerance; start/finish are the least strictly defined (and least consequential
for downstream coaching heuristics) and get the loosest tolerance.
"""

import json
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.engine.phases import detect_phases, segment_serves
from app.models import ServePhase
from app.services.object_detection import get_object_detection_model
from app.services.pose_model import get_pose_model
from tools.segmentation_report import build_frame_sequence, slice_detections_by_segments

_TOOLS_DIR = Path(__file__).parent.parent / "tools"
_GROUND_TRUTH_PATH = _TOOLS_DIR / "segmentation_ground_truth.json"
_STRIDE = 2


@pytest.mark.skipif(
    not os.environ.get("RUN_MODEL_INTEGRATION_TESTS"),
    reason="Requires real models + local calibration_data videos; opt-in via RUN_MODEL_INTEGRATION_TESTS=1",
)
def test_all_videos_match_ground_truth():
    ground_truth = json.loads(_GROUND_TRUTH_PATH.read_text())
    default_tolerance = ground_truth["tolerance_seconds"]
    phase_tolerances = ground_truth.get("phase_tolerances", {})

    pose_model = get_pose_model()
    detection_model = get_object_detection_model()

    failures: list[str] = []

    for video_name, expected_serves in ground_truth["videos"].items():
        video_path = _TOOLS_DIR / "calibration_data" / video_name
        frames, detections, _ = build_frame_sequence(video_path, _STRIDE, pose_model, detection_model)
        segments = segment_serves(frames)
        segment_detections = slice_detections_by_segments(detections, segments)

        if len(segments) != len(expected_serves):
            failures.append(
                f"{video_name}: expected {len(expected_serves)} serve(s), detected {len(segments)}"
            )
            continue

        for expected_serve, segment_frames, segment_dets in zip(expected_serves, segments, segment_detections):
            serve_index = expected_serve["serve_index"]
            phases = detect_phases(segment_frames, segment_dets)

            for phase_name, expected_timestamp in expected_serve["phases"].items():
                detected_frame = phases[ServePhase(phase_name)]

                if expected_timestamp is None:
                    if detected_frame is not None:
                        failures.append(
                            f"{video_name} serve {serve_index} {phase_name}: expected None, "
                            f"got frame at t={detected_frame.timestamp:.3f}"
                        )
                    continue

                if detected_frame is None:
                    failures.append(
                        f"{video_name} serve {serve_index} {phase_name}: expected t={expected_timestamp:.3f}, "
                        f"got None"
                    )
                    continue

                tolerance = phase_tolerances.get(phase_name, default_tolerance)
                delta = abs(detected_frame.timestamp - expected_timestamp)
                if delta > tolerance:
                    failures.append(
                        f"{video_name} serve {serve_index} {phase_name}: expected t={expected_timestamp:.3f}, "
                        f"got t={detected_frame.timestamp:.3f} (delta={delta:.3f} > tolerance={tolerance})"
                    )

    assert not failures, "\n".join(failures)
