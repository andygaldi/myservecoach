---
name: phase
description: Run the agentic coding loop for one phase. Implements task groups from the phase plan, self-verifies via scripts/verify.sh after each group, iterates on failure, runs a multi-perspective deep review when all groups are green, and stops for human review.
---

# /phase — Agentic Coding Loop

Implements a single phase from the `phases/<name>/` triad (requirements, plan, validation)
using a tight implement → verify → iterate loop. When all task groups pass, runs a
multi-perspective deep review (correctness, design, spec compliance) via three parallel
subagents, then stops for human review. Also stops — with a report — when stuck after the
retry budget.

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

### Step 4 — Deep review (three parallel subagents)

When all task groups are green, spawn **three subagents in parallel** — one per perspective —
each reviewing the full branch diff against the phase triad. Give every subagent the diff,
the phase `requirements.md`, `plan.md`, and `validation.md` as context.

**Agent A — Correctness**
Does the implementation actually do what the plan and requirements say? Look for logic
errors, missed edge cases, off-by-ones, wrong return types, missed branches, or anything
that would cause a test to pass for the wrong reason.

**Agent B — Design & simplicity**
Is the code clear and idiomatic for the surface (Python/FastAPI or Swift/SwiftUI)? Are
there unnecessary abstractions, redundant logic, or simpler ways to express the same thing?
Does anything violate conventions already established in the codebase?

**Agent C — Spec compliance**
Does the diff stay strictly within the In Scope list in `requirements.md`? Does it satisfy
every acceptance criterion in `validation.md`? Does it touch anything listed as Out of
Scope or leave any required item unaddressed?

Wait for all three agents to finish, then synthesize their findings into a concise report:
- **Findings** (grouped by perspective; omit perspectives with nothing to flag)
- **Recommended fixes** (if any — apply only with user approval)

### Step 5 — Stop for review

Present the task-group summary and the deep-review report together, then stop:

```
✅ All task groups complete and verified green.

Summary:
- [Task Group 1] — <one sentence description of what was done>
- [Task Group 2] — ...

Deep review findings:
<synthesized output from the three agents, or "No issues found." if clean>

Next: Please review, address any findings you agree with, then check off validation.md.
See: phases/<name>/validation.md
```

Do **not** commit, push, or open a PR — that is the user's action after review.

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

- It does not run `/loop` (interval-based recurrence) — the loop here is bounded to this
  phase.
- It does not use the `verify` skill (which runs the full app visually) — it uses
  `scripts/verify.sh` for a machine-checkable signal.
- It does not commit or push — review and merge are always human actions.
