# Phase: joint_xy Coverage — Requirements

## Scope

Add unit test coverage for the `joint_xy` function in `backend/app/engine/angles.py`.

`joint_xy` is used throughout the rule engine and phase detector to extract normalized
`(x, y)` coordinates for a named joint from a frame. It currently has **zero test
coverage** despite being called in production code paths.

## In Scope

- Tests for `joint_xy` in `backend/tests/test_angles.py` (extend the existing file)
- All meaningful behavioral cases:
  - Returns `(x, y)` tuple when joint is present and confidence meets threshold
  - Returns `None` when joint is missing from the frame
  - Returns `None` when joint confidence is below `MIN_CONFIDENCE`
  - Returns `(x, y)` when confidence is exactly at `MIN_CONFIDENCE` (boundary included — same semantics as `keypoint_y`)
  - Respects a custom `min_confidence` argument
- Uses the existing `make_frame` helper from `conftest.py`

## Out of Scope

- Changes to `angles.py` itself — no production code changes
- Tests for `compute_angle` or `keypoint_y` (already covered)
- Any other backend files

## Context

`joint_xy` has the same confidence-gating logic as `keypoint_y` (which is already
well-tested), but additionally packages both x and y coordinates into a tuple. The boundary
semantics (`confidence < min_confidence` → reject; `==` → accept) should be verified
explicitly since that's a subtle off-by-one that has tripped up the related function in
previous discussions. This phase is the **first experiential run** of the `/phase` loop.
