---
name: phase
description: Run the agentic coding loop for one phase. Implements task groups from the phase plan, self-verifies via scripts/verify.sh after each group, iterates on failure, and stops when all groups are green. Deep review is a separate step — run /phase-review next.
---

# /phase — Agentic Coding Loop

Implements a single phase from the `phases/<name>/` triad (requirements, plan, validation)
using a tight implement → verify → iterate loop. Stops when all task groups pass — deep
review is a separate step, run via `/phase-review`. Also stops — with a report — when stuck
after the retry budget.

## Input

Pass the phase folder name as an argument, e.g.:

```
/phase 2026-07-01-joint-xy-coverage
```

The folder must exist at `phases/<name>/` and contain all three files:
- `requirements.md` — scope and constraints
- `plan.md` — task groups with sub-tasks
- `validation.md` — definition of done and verification steps

## Procedure

### Step 1 — Read the triad

Read all three files before touching any code:
1. `phases/<name>/requirements.md` — understand scope and out-of-scope list
2. `phases/<name>/plan.md` — identify the ordered Task Groups and their sub-tasks
3. `phases/<name>/validation.md` — understand the definition of done

Determine the **surface** (`backend` or `ios`) from context (Python files → backend, Swift
files → ios). If ambiguous, ask before proceeding.

### Step 2 — Run the baseline verify

Before making any changes, run:

```bash
scripts/verify.sh <surface>
```

If the baseline is already red, **stop immediately** and tell the user: pre-existing failures
must be fixed before running the loop. Do not attempt to implement over a broken baseline.

### Step 3 — Implement task groups, one at a time

For each Task Group in order:

1. **Implement** all sub-tasks in the group.
2. **Verify** by running `scripts/verify.sh <surface>`.
3. If **green** → proceed to the next group.
4. If **red** → diagnose the failure, fix it, re-verify. Retry up to **3 times**.
   - If still red after 3 retries: **stop**. Report which group failed, what you tried, and
     the test output. Ask the user how to proceed. Do not advance to the next group.

### Step 4 — Stop and hand off to review

When all task groups are green, present the task-group summary and stop:

```
✅ All task groups complete and verified green.

Summary:
- [Task Group 1] — <one sentence description of what was done>
- [Task Group 2] — ...

Next: run /phase-review <name> for the three-perspective deep review.
```

Do **not** run the deep review here — that is `/phase-review`'s job. Do **not** commit, push,
or open a PR — that is `/merge`'s job.

## Verification oracle

```bash
scripts/verify.sh backend   # cd backend && .venv/bin/pytest -q
scripts/verify.sh ios       # xcodebuild test on iPhone 17 Pro / iOS 26.4 Simulator
```

Exit 0 = green. Any non-zero exit = red.

## Retry budget

3 fix attempts per task group. After 3 failures on the same group, stop and escalate
to the user rather than spinning indefinitely.

## What this skill does NOT do

- It does not run the deep review — that is `/phase-review`, run as a separate step once all
  groups are green.
- It does not run `/loop` (interval-based recurrence) — the loop here is bounded to this
  phase.
- It does not use the `verify` skill (which runs the full app visually) — it uses
  `scripts/verify.sh` for a machine-checkable signal.
- It does not commit or push — review and merge are always human actions.
