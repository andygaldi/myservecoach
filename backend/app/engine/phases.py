import math

from app.models import BoundingBox, Detection, Frame, ServePhase
from app.engine.angles import (
    arm_straightness_angle,
    forearm_angle_from_vertical,
    hip_height,
    keypoint_y,
    knee_flexion_angle,
    MIN_CONFIDENCE,
)

# Hardcoded right-handed server. A wrong hitting side previously produced only wrong cues;
# since P6d, segment_serves' serve *count* also derives from the hitting wrist, so a wrong
# side now miscounts serves too. P7b promotes this from known limitation to prerequisite —
# it must become configurable before behind-camera work, which can't assume handedness from
# framing alone.
HANDEDNESS: dict[str, str] = {"hitting": "right", "toss": "left"}

MIN_REST_SECONDS = 0.3
LOW_MOTION_VELOCITY_THRESHOLD = 0.03  # normalized units per second
# Calibrated against the real corpus in this phase's Group 6 (segmentation_sweep.py grid search);
# see validation.md run notes for the full grid and how these were chosen. min_peak_separation was
# widened past the corpus-only optimum (0.6) to 1.5 after the six-phase regression suite surfaced
# vesa_slow_mo.mov: a single slow-motion serve's wrist trajectory produces several weak, closely-
# spaced local maxima above the floor that a tighter window wrongly split into multiple serves.
HITTING_WRIST_FLOOR_K = 0.15
MIN_PEAK_SEPARATION_SECONDS = 1.5
CONTACT_WRIST_WEIGHT = 0.5
CONTACT_PROXIMITY_WEIGHT = 0.5
TROPHY_HIP_WEIGHT = 0.5
TROPHY_TOSS_ARM_WEIGHT = 0.5
# Trophy pose's window is wide relative to its two candidate frames, so smoothing over nearby
# frames helps; racket_drop's window is often just 1-4 frames (fast real swings), where the same
# smoothing dilutes the one true peak more than it removes noise — empirically validated against
# hand-labeled ground truth, not just theoretical. Each phase gets its own window accordingly.
TROPHY_SMOOTHING_WINDOW = 3
RACKET_DROP_SMOOTHING_WINDOW = 1
# Finish: how far past contact (in real seconds) to search for the landing, and the toss-leg knee
# angle that marks it. Bounded rather than searching the whole rest of the segment — empirically
# tuned against hand-labeled ground truth on real-speed footage (0.4s comfortably covers the
# landing on every real-time-speed calibration video); doesn't generalize to genuinely
# slow-motion source footage, which isn't representative of the app's live self-recording use
# case, so that gap is an accepted limitation rather than something this window chases.
FINISH_WINDOW_SECONDS = 0.4
FINISH_TARGET_KNEE_ANGLE = 90.0


def _frame_velocity(a: Frame, b: Frame) -> float:
    """Mean per-second displacement, in normalized coordinates, across keypoints shared by both frames.

    Normalizing by the real timestamp delta (rather than treating each frame pair as one fixed
    step) keeps the result comparable across source videos recorded at different frame rates.
    """
    shared = set(a.keypoints) & set(b.keypoints)
    distances = []
    for name in shared:
        kp_a, kp_b = a.keypoints[name], b.keypoints[name]
        if kp_a.confidence < MIN_CONFIDENCE or kp_b.confidence < MIN_CONFIDENCE:
            continue
        distances.append(math.hypot(kp_a.x - kp_b.x, kp_a.y - kp_b.y))
    if not distances:
        return 0.0
    mean_distance = sum(distances) / len(distances)
    dt = b.timestamp - a.timestamp
    return mean_distance / dt if dt > 0 else mean_distance


def _torso_length(frame: Frame) -> float | None:
    """Vertical distance between the derived neck and pelvis midpoints, or None if either is
    unavailable — the body-relative scale used to size the hitting-wrist floor."""
    neck_y = keypoint_y(frame, "neck")
    pelvis_y = keypoint_y(frame, "pelvis")
    if neck_y is None or pelvis_y is None:
        return None
    return abs(neck_y - pelvis_y)


def _hitting_wrist_floor_score(frame: Frame, hitting: str, floor_k: float) -> float | None:
    """The hitting wrist's height above a body-relative floor (neck_y + floor_k * torso_length),
    or None if any of neck/pelvis/{hitting}_wrist is unavailable. Positive means the wrist is
    above the floor (y increases upward — see pose_model.py's coordinate convention); only
    positive-score frames are peak candidates, which is what rejects a toss-and-catch (the toss
    arm rises, the hitting arm does not)."""
    neck_y = keypoint_y(frame, "neck")
    torso_length = _torso_length(frame)
    wrist_y = keypoint_y(frame, f"{hitting}_wrist")
    if neck_y is None or torso_length is None or wrist_y is None:
        return None
    floor = neck_y + floor_k * torso_length
    return wrist_y - floor


def _find_serve_peaks(
    frames: list[Frame], hitting: str, floor_k: float, min_peak_separation_seconds: float
) -> list[int]:
    """Frame indices of accepted serve peaks: local maxima of the positive hitting-wrist floor
    score, greedily non-max-suppressed by descending score with a minimum real-seconds
    separation between accepted peaks (fps-invariant by construction, same reasoning as
    _frame_velocity's dt-normalization). Accepted peak count is the serve count."""
    # Keep every frame's score, including negative ones — only missing neck/pelvis/wrist drops a
    # frame from the series entirely. Negative-score runs between two humps are what lets two
    # equal-height, widely-separated peaks be told apart below; filtering to positive scores here
    # first would make them look like immediate (and thus wrongly mergeable) neighbors.
    scores: dict[int, float] = {}
    for i, frame in enumerate(frames):
        score = _hitting_wrist_floor_score(frame, hitting, floor_k)
        if score is not None:
            scores[i] = score

    if not scores:
        return []

    # Local maxima over the full scored series, comparing each frame to its nearest scored
    # neighbors by position (not raw frame-index distance, since low-confidence frames may be
    # missing) — mirrors _smooth_series' same positional-neighbor convention. Equal-score runs
    # (e.g. a sustained high-wrist follow-through) are grouped into a single plateau first, so a
    # wide flat run is counted as one peak rather than many. Only positive-score plateaus are
    # ever accepted as peaks — this is the load-bearing hitting-side restriction that rejects a
    # toss-and-catch (toss arm rises, hitting arm does not).
    ordered = sorted(scores)
    plateaus: list[list[int]] = []
    for i in ordered:
        if plateaus and scores[i] == scores[plateaus[-1][-1]]:
            plateaus[-1].append(i)
        else:
            plateaus.append([i])

    local_maxima: list[int] = []
    for pos, plateau in enumerate(plateaus):
        score = scores[plateau[0]]
        if score <= 0:
            continue
        prev_score = scores[plateaus[pos - 1][-1]] if pos > 0 else None
        next_score = scores[plateaus[pos + 1][0]] if pos < len(plateaus) - 1 else None
        if (prev_score is None or score > prev_score) and (next_score is None or score > next_score):
            local_maxima.append(plateau[len(plateau) // 2])

    local_maxima.sort(key=lambda i: scores[i], reverse=True)
    accepted: list[int] = []
    for i in local_maxima:
        if all(abs(frames[i].timestamp - frames[j].timestamp) >= min_peak_separation_seconds for j in accepted):
            accepted.append(i)

    return sorted(accepted)


def _place_boundary(
    frames: list[Frame], peak_a: int, peak_b: int, velocity_threshold: float, min_rest_seconds: float
) -> int:
    """The boundary index between two consecutive accepted peaks: the midpoint of the longest
    low-velocity ("rest") run found strictly between them, or — if no run in that span clears
    min_rest_seconds — the frame index nearest the time-midpoint between the two peaks. Never
    adds, removes, or merges a serve; only slides where the cut between two already-counted
    serves falls."""
    if peak_b <= peak_a + 1:
        return peak_a

    runs: list[tuple[int, int, float]] = []
    rest_run_start: int | None = None

    for i in range(peak_a + 2, peak_b):
        velocity = _frame_velocity(frames[i - 1], frames[i])
        if velocity < velocity_threshold:
            if rest_run_start is None:
                rest_run_start = i - 1
        elif rest_run_start is not None:
            duration = frames[i - 1].timestamp - frames[rest_run_start].timestamp
            if duration >= min_rest_seconds:
                runs.append((rest_run_start, i - 1, duration))
            rest_run_start = None

    if rest_run_start is not None:
        end = peak_b - 1
        duration = frames[end].timestamp - frames[rest_run_start].timestamp
        if duration >= min_rest_seconds:
            runs.append((rest_run_start, end, duration))

    if runs:
        best_start, best_end, _ = max(runs, key=lambda run: run[2])
        return (best_start + best_end) // 2

    midpoint_ts = (frames[peak_a].timestamp + frames[peak_b].timestamp) / 2
    return min(range(peak_a + 1, peak_b), key=lambda i: abs(frames[i].timestamp - midpoint_ts))


def segment_serves(
    frames: list[Frame],
    min_rest_seconds: float = MIN_REST_SECONDS,
    velocity_threshold: float = LOW_MOTION_VELOCITY_THRESHOLD,
    floor_k: float = HITTING_WRIST_FLOOR_K,
    min_peak_separation_seconds: float = MIN_PEAK_SEPARATION_SECONDS,
) -> list[list[Frame]]:
    """Split a continuous recording's frames into per-serve sub-lists.

    Counts by presence, not absence: each accepted hitting-wrist-height peak (see
    _find_serve_peaks) is one serve. Zero peaks (idle-only, or a clip where the hitting wrist
    never clears its body-relative floor) returns []. Boundaries between consecutive peaks are
    placed by the existing low-velocity rest-gap logic, bounded to the span between the two
    peaks (see _place_boundary) — that logic can no longer add, remove, or merge a serve, only
    slide where the cut falls.
    """
    if not frames:
        return []

    hitting = HANDEDNESS["hitting"]
    peaks = _find_serve_peaks(frames, hitting, floor_k, min_peak_separation_seconds)

    if not peaks:
        return []
    if len(peaks) == 1:
        return [frames]

    boundaries = [
        _place_boundary(frames, peaks[i], peaks[i + 1], velocity_threshold, min_rest_seconds)
        for i in range(len(peaks) - 1)
    ]

    segments: list[list[Frame]] = []
    start = 0
    for boundary in boundaries:
        segments.append(frames[start : boundary + 1])
        start = boundary + 1
    segments.append(frames[start:])
    return segments


def slice_detections_by_segments(
    detections: list[list[Detection]], segments: list[list[Frame]]
) -> list[list[list[Detection]]]:
    """Slice a flat per-frame detections list at the same boundaries segment_serves used for frames."""
    serve_detections: list[list[list[Detection]]] = []
    cursor = 0
    for segment in segments:
        serve_detections.append(detections[cursor : cursor + len(segment)])
        cursor += len(segment)
    return serve_detections


def bbox_center(bbox: BoundingBox) -> tuple[float, float]:
    return ((bbox.x_min + bbox.x_max) / 2, (bbox.y_min + bbox.y_max) / 2)


def _detection_center_y(dets: list[Detection], label: str) -> float | None:
    detection = next((d for d in dets if d.label == label), None)
    if detection is None:
        return None
    return bbox_center(detection.bbox)[1]


def _racket_ball_distance(dets: list[Detection]) -> float | None:
    racket = next((d for d in dets if d.label == "racket"), None)
    ball = next((d for d in dets if d.label == "ball"), None)
    if racket is None or ball is None:
        return None
    racket_x, racket_y = bbox_center(racket.bbox)
    ball_x, ball_y = bbox_center(ball.bbox)
    return math.hypot(racket_x - ball_x, racket_y - ball_y)


def _min_max_normalize(values: dict[int, float]) -> dict[int, float]:
    """Min-max normalize a {frame_index: raw_value} mapping to [0, 1].

    When every value is equal (including the single-entry case), everything normalizes to 1.0
    rather than dividing by zero, so a lone candidate still wins on its own signal.
    """
    if not values:
        return {}
    lo = min(values.values())
    hi = max(values.values())
    if hi == lo:
        return {i: 1.0 for i in values}
    return {i: (v - lo) / (hi - lo) for i, v in values.items()}


def _smooth_series(values: dict[int, float], window: int) -> dict[int, float]:
    """Centered moving-average smoothing over a sparse {frame_index: value} series.

    Averages each entry with its nearest available neighbors *by position within the series*
    (not by raw frame-index distance, since some frames may be missing due to low-confidence
    keypoints) — damps single-frame outliers before a max/min search picks a winner.
    """
    if not values:
        return {}
    ordered = sorted(values)
    half = window // 2
    smoothed: dict[int, float] = {}
    for pos, i in enumerate(ordered):
        neighborhood = ordered[max(0, pos - half) : pos + half + 1]
        smoothed[i] = sum(values[n] for n in neighborhood) / len(neighborhood)
    return smoothed


def _find_contact_idx(
    frames: list[Frame], detections: list[list[Detection]] | None, hitting: str, search_start: int
) -> int | None:
    """Combined wrist-height + racket-ball-proximity contact search from `search_start` onward.

    Falls back to wrist-height-only when no detections are available or racket+ball aren't both
    detected in a given frame. Factored out because trophy_pose's search window is bounded by a
    preliminary contact estimate computed *before* trophy_idx is known (see detect_phases), and
    the final post-trophy contact search reuses the same logic.
    """
    wrist_heights: dict[int, float] = {}
    for i in range(search_start, len(frames)):
        wrist_y = keypoint_y(frames[i], f"{hitting}_wrist")
        if wrist_y is not None:
            wrist_heights[i] = wrist_y

    proximities: dict[int, float] = {}
    if detections is not None:
        for i in range(search_start, len(frames)):
            if i >= len(detections):
                continue
            distance = _racket_ball_distance(detections[i])
            if distance is not None:
                proximities[i] = -distance  # lower distance (closer) => higher score

    wrist_norm = _min_max_normalize(wrist_heights)
    proximity_norm = _min_max_normalize(proximities)
    return _weighted_best([(CONTACT_WRIST_WEIGHT, wrist_norm), (CONTACT_PROXIMITY_WEIGHT, proximity_norm)])


def _weighted_best(signals: list[tuple[float, dict[int, float]]]) -> int | None:
    """Pick the frame index with the highest weighted-average score across normalized signals.

    Each `(weight, normalized_map)` pair contributes only for frames present in its map, so a
    frame missing some signals is scored on whichever ones it has. Iterates candidate indices in
    ascending order with a strict `>` comparison, so the first frame to reach the max score wins
    ties — matching plain max-search semantics over an ordered sequence.
    """
    candidate_indices = set()
    for _, signal in signals:
        candidate_indices |= set(signal)

    best_idx: int | None = None
    best_score = float("-inf")
    for i in sorted(candidate_indices):
        parts = [(weight, signal[i]) for weight, signal in signals if i in signal]
        total_weight = sum(w for w, _ in parts)
        score = sum(w * v for w, v in parts) / total_weight if total_weight else float("-inf")
        if score > best_score:
            best_score = score
            best_idx = i
    return best_idx


def detect_phases(
    frames: list[Frame], detections: list[list[Detection]] | None = None
) -> dict[ServePhase, Frame | None]:
    hitting = HANDEDNESS["hitting"]
    toss = HANDEDNESS["toss"]

    # 0. Release: first frame where a detected ball is above the toss hand *and* the toss wrist
    #    has already risen above the toss shoulder. The wrist-above-shoulder condition guards
    #    against a low-confidence ball detection while the ball is still held pre-toss (bent-over
    #    setup stance, wrist low) — a single such frame used to be enough to trigger release far
    #    too early, since the ball-alone condition never checked whether the toss motion had
    #    actually begun. Falls back to the toss-wrist-only condition if no frame satisfies the
    #    combined ball condition (e.g. the ball isn't reliably detected during the real toss arc
    #    for a given video — object detection can lose a small fast-moving ball to motion blur).
    release_idx: int | None = None
    if detections is not None:
        for i, frame in enumerate(frames):
            if i >= len(detections):
                continue
            ball_y = _detection_center_y(detections[i], "ball")
            toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
            toss_shoulder_y = keypoint_y(frame, f"{toss}_shoulder")
            if ball_y is None or toss_wrist_y is None or toss_shoulder_y is None:
                continue
            if ball_y > toss_wrist_y and toss_wrist_y > toss_shoulder_y:
                release_idx = i
                break

    if release_idx is None:
        for i, frame in enumerate(frames):
            toss_wrist_y = keypoint_y(frame, f"{toss}_wrist")
            toss_shoulder_y = keypoint_y(frame, f"{toss}_shoulder")
            if toss_wrist_y is None or toss_shoulder_y is None:
                continue
            if toss_wrist_y > toss_shoulder_y:
                release_idx = i
                break

    # 1. Trophy pose: combined lowest-hip-height + straightest-toss-arm signal, bounded to
    #    [release, contact) so the search can't wander into an unrelated part of the clip (e.g. a
    #    non-serve motion elsewhere in the segment). Contact isn't known yet at this point, so a
    #    throwaway *preliminary* contact estimate (searched from release onward) stands in for the
    #    window's upper bound; the real contact_idx used everywhere else is recomputed below once
    #    trophy_idx is known. Hip height (the loading crouch depth) and toss-arm straightness (the
    #    tossing arm extended toward the ball) were selected empirically against hand-labeled
    #    ground truth over several other candidates (knee flexion, hitting-elbow height/angle) —
    #    each raw signal is smoothed across nearby frames before scoring, so a single noisy frame
    #    can't unduly swing the pick.
    trophy_search_start = release_idx if release_idx is not None else 0
    prelim_contact_idx = _find_contact_idx(frames, detections, hitting, trophy_search_start)
    trophy_search_end = prelim_contact_idx + 1 if prelim_contact_idx is not None else len(frames)

    hip_heights: dict[int, float] = {}
    toss_arm_angles: dict[int, float] = {}
    for i in range(trophy_search_start, trophy_search_end):
        frame = frames[i]
        hip_y = hip_height(frame, hitting)
        if hip_y is not None:
            hip_heights[i] = hip_y
        arm_angle = arm_straightness_angle(frame, toss)
        if arm_angle is not None:
            toss_arm_angles[i] = arm_angle

    # Negate hip height before normalizing so a lower (more-crouched) raw value scores higher;
    # toss-arm straightness is already "higher is better" (closer to a fully extended 180°).
    hip_norm = _min_max_normalize({i: -v for i, v in _smooth_series(hip_heights, TROPHY_SMOOTHING_WINDOW).items()})
    toss_arm_norm = _min_max_normalize(_smooth_series(toss_arm_angles, TROPHY_SMOOTHING_WINDOW))

    trophy_idx = _weighted_best([(TROPHY_HIP_WEIGHT, hip_norm), (TROPHY_TOSS_ARM_WEIGHT, toss_arm_norm)])

    # 1b. Start: the frame with the lowest toss-wrist height, searched before release (or before
    #     trophy pose if release didn't resolve) — marks the bottom of the toss backswing right
    #     before the arm begins its ascent.
    start_search_end = release_idx if release_idx is not None else trophy_idx
    start_idx: int | None = None
    if start_search_end is not None and start_search_end > 0:
        min_toss_wrist_y = float("inf")
        for i in range(0, start_search_end):
            toss_wrist_y = keypoint_y(frames[i], f"{toss}_wrist")
            if toss_wrist_y is not None and toss_wrist_y < min_toss_wrist_y:
                min_toss_wrist_y = toss_wrist_y
                start_idx = i

    # 2. Contact: combined wrist-height + racket-ball-proximity signal, searched from the *final*
    #    trophy_idx onward (trophy_pose no longer needs contact's search_start as an input — see
    #    the preliminary-contact estimate above — so this just reruns the same search with the
    #    now-known real trophy_idx). Falls back to the full sequence when no trophy is detected.
    contact_search_start = trophy_idx + 1 if trophy_idx is not None else 0
    contact_idx = _find_contact_idx(frames, detections, hitting, contact_search_start)

    # 3. Racket drop: frame strictly between trophy and contact with the highest smoothed
    #    shoulder-external-rotation proxy (forearm-to-vertical angle — see
    #    angles.forearm_angle_from_vertical). 2D keypoints can't measure the humerus's true axial
    #    rotation, but the forearm's visible swing from pointing up (trophy) to pointing down and
    #    behind the body (fully cocked) peaks at the "back-scratch" position this phase marks.
    #    Smoothed across nearby frames before picking the max to reduce single-frame noise.
    drop_idx: int | None = None
    if trophy_idx is not None and contact_idx is not None:
        er_angles: dict[int, float] = {}
        for i in range(trophy_idx + 1, contact_idx):
            angle = forearm_angle_from_vertical(frames[i], hitting)
            if angle is not None:
                er_angles[i] = angle

        drop_idx = _weighted_best([(1.0, _smooth_series(er_angles, RACKET_DROP_SMOOTHING_WINDOW))])

    # 4. Finish: within FINISH_WINDOW_SECONDS after contact, the frame whose toss-side (landing)
    #    knee flexion is closest to FINISH_TARGET_KNEE_ANGLE — the front leg absorbing the
    #    landing. Bounded to a short post-contact window rather than searching the rest of the
    #    segment: the prior ankle-height heuristic could fall through to the segment's last frame
    #    when no clear post-contact dip existed, landing many seconds late whenever trailing
    #    footage (walking, resetting) was included in the serve segment. Falls back to the last
    #    frame of the same bounded window (not the whole segment) if no knee data resolves within
    #    it, and to the segment's last frame only when there's no contact at all.
    finish_idx: int | None = None
    if contact_idx is not None:
        contact_ts = frames[contact_idx].timestamp
        window_end = contact_idx + 1
        while window_end < len(frames) and frames[window_end].timestamp - contact_ts <= FINISH_WINDOW_SECONDS:
            window_end += 1

        landing_scores: dict[int, float] = {}
        for i in range(contact_idx + 1, window_end):
            angle = knee_flexion_angle(frames[i], toss)
            if angle is not None:
                landing_scores[i] = -abs(angle - FINISH_TARGET_KNEE_ANGLE)

        if landing_scores:
            finish_idx = _weighted_best([(1.0, landing_scores)])
        elif window_end > contact_idx + 1:
            finish_idx = window_end - 1
    if finish_idx is None:
        finish_idx = len(frames) - 1 if frames else None

    return {
        ServePhase.start: frames[start_idx] if start_idx is not None else None,
        ServePhase.release: frames[release_idx] if release_idx is not None else None,
        ServePhase.trophy_pose: frames[trophy_idx] if trophy_idx is not None else None,
        ServePhase.racket_drop: frames[drop_idx] if drop_idx is not None else None,
        ServePhase.contact: frames[contact_idx] if contact_idx is not None else None,
        ServePhase.finish: frames[finish_idx] if finish_idx is not None else None,
    }
