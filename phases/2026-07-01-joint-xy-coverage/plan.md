# Phase: joint_xy Coverage — Plan

## Task Group 1 — Add `joint_xy` tests to `test_angles.py`

Extend `backend/tests/test_angles.py` with a `# --- joint_xy ---` section after the
existing `keypoint_y` tests. Add the following five test functions:

1.1 **`test_joint_xy_returns_tuple_when_confidence_sufficient`**
Construct a frame with `right_wrist` at `(0.3, 0.6)` confidence `0.9`.
Assert `joint_xy(frame, "right_wrist") == (0.3, 0.6)`.

1.2 **`test_joint_xy_returns_none_for_missing_joint`**
Construct an empty frame (`make_frame({})`).
Assert `joint_xy(frame, "right_wrist") is None`.

1.3 **`test_joint_xy_returns_none_below_min_confidence`**
Construct a frame with `right_wrist` confidence `0.3` (below `MIN_CONFIDENCE = 0.4`).
Assert `joint_xy(frame, "right_wrist") is None`.

1.4 **`test_joint_xy_at_confidence_boundary_included`**
Construct a frame with `right_wrist` confidence exactly `MIN_CONFIDENCE`.
Assert `joint_xy(frame, "right_wrist", min_confidence=MIN_CONFIDENCE)` returns the tuple
(not None) — confidence `==` threshold is accepted, same as `keypoint_y`.

1.5 **`test_joint_xy_respects_custom_min_confidence`**
Construct a frame with `right_wrist` confidence `0.35`.
Assert `joint_xy(frame, "right_wrist", min_confidence=0.3)` returns the tuple.
Assert `joint_xy(frame, "right_wrist", min_confidence=0.4)` returns `None`.

**Surface:** `backend`
**File to edit:** `backend/tests/test_angles.py`
**Helpers available:** `make_frame` (imported from `conftest`), `MIN_CONFIDENCE` (imported
from `app.engine.angles` — already in the import block at the top of the file).
