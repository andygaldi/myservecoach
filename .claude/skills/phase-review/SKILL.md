---
name: phase-review
description: Run the multi-perspective deep review for an implemented phase. Spawns three parallel subagents (correctness / design / spec compliance) against the branch diff and the phase triad, then presents the task-group summary and synthesized findings and stops for human review. Runs after /phase, before /merge.
---

# /phase-review — Deep Review

Reviews an implemented phase from three perspectives at once, using three parallel subagents,
then stops and presents the findings for a human decision. This is the third step of the loop:
`/spec → /phase → /phase-review → /merge`.

Separated from `/phase` deliberately: implementation and review are different jobs with
different failure modes, and keeping them apart means you can re-run a review after applying
fixes without re-running the implementation loop.

## When to run

Run `/phase-review` after `/phase` has reported all task groups green. Running it against a
red or partially-implemented branch wastes three agent runs on a diff that is still moving.

## Input

Pass the phase folder name as an argument, e.g.:

```
/phase-review 2026-07-01-joint-xy-coverage
```

If no argument is given, infer the phase from the current branch name and confirm it with the
user before spawning agents. The folder must exist at `phases/<name>/` with all three files.

## Procedure

### Step 1 — Establish the review inputs

Read all three triad files:
1. `phases/<name>/requirements.md` — scope and out-of-scope list
2. `phases/<name>/plan.md` — the task groups that were meant to be implemented
3. `phases/<name>/validation.md` — the definition of done

Determine the **surface** (`backend` or `ios`) the same way `/phase` does (Python files →
backend, Swift files → ios; a phase may touch both).

Capture the full branch diff against `develop`:

```bash
git diff develop...HEAD
git diff --name-only develop...HEAD
```

Include uncommitted work — `/phase` does not commit, so on a fresh phase the diff may be
entirely unstaged. Check `git status` and include working-tree changes in what you hand the
agents.

### Step 2 — Confirm the baseline is green

Run the verify oracle before reviewing:

```bash
scripts/verify.sh <surface>
```

If it is red, **stop** and report. A deep review of a failing branch produces findings the
user has to re-triage after the failure is fixed. Fix the red first (or re-run `/phase`), then
review.

### Step 3 — Deep review (three parallel subagents)

Spawn **three subagents in parallel** — one per perspective — each reviewing the full branch
diff against the phase triad. Give every subagent the diff, the phase `requirements.md`,
`plan.md`, and `validation.md` as context, plus `CLAUDE.md` for codebase conventions.

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

Wait for all three agents to finish, then synthesize their findings. Do not relay three raw
agent reports — deduplicate overlapping findings (the same defect often surfaces from two
perspectives), drop anything that does not survive your own check against the code, and order
what remains most-severe first.

Treat agent output as a claim to verify, not a conclusion to relay. A subagent that reports a
bug in code it misread is common; confirm each finding against the actual diff before it
reaches the user.

### Step 4 — Stop for review

Present the task-group summary and the deep-review report together, then stop:

```
✅ All task groups complete and verified green.

Summary:
- [Task Group 1] — <one sentence description of what was done>
- [Task Group 2] — ...

Deep review findings:
<synthesized, deduplicated, verified findings — most severe first —
 or "No issues found." if clean>

Next: Please review, address any findings you agree with, then check off validation.md.
See: phases/<name>/validation.md
```

For each finding, state what is wrong and what it would cost — a finding the user cannot
weigh is a finding they cannot act on.

**Apply fixes only with user approval.** When the user approves a subset, apply exactly that
subset and say plainly which findings you left unaddressed.

Do **not** commit, push, or open a PR — that is `/merge`'s job, after the user is satisfied.

## Recording the outcome

When findings are applied, record them in `phases/<name>/validation.md` under **Run notes** —
what was found, what was fixed, and what was deliberately left open with the reasoning. The
validation file is the phase's durable record; a finding that was consciously deferred is
worth as much to a later reader as one that was fixed.

## Verification oracle

```bash
scripts/verify.sh backend   # cd backend && .venv/bin/pytest -q
scripts/verify.sh ios       # xcodebuild test on iPhone 17 Pro / iOS 26.4 Simulator
```

Exit 0 = green. Any non-zero exit = red. Re-run after applying any fix.

## What this skill does NOT do

- It does not implement task groups — that is `/phase`'s job. If the review reveals a group
  was never finished, stop and say so rather than quietly finishing it.
- It does not commit, push, or merge — that is `/merge`'s job.
- It is not the built-in `/review` (GitHub PR review) or `/code-review` (working diff). Those
  are general-purpose; this one reviews against a specific phase triad.
