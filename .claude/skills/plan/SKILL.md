---
name: plan
description: Create the feature spec triad (requirements, plan, validation) for the next pending phase on the roadmap. Asks questions before writing any file to disk, then commits the spec. Pair with /phase to implement.
---

# /plan — Feature Specification

Creates the `phases/YYYY-MM-DD-<name>/` triad for the next pending phase on the roadmap.
**Always asks questions before writing any file to disk.** Pair with `/phase` to implement.

## Input

No argument needed — the skill finds the next pending phase automatically. Optionally pass
a phase name to target a specific phase:

```
/plan
/plan P1-offdevice-pose
```

## Procedure

### Step 1 — Identify the next phase

Read `specs/roadmap.md`. Find the first item marked `⬜ Pending`. Note its name, description,
and any dependencies mentioned.

Also read `specs/mission.md` and `specs/tech-stack.md` for product and technical constraints
that should inform the spec.

Report to the user which phase was identified and confirm it is the right one before
proceeding. If the user names a different phase, use that instead.

### Step 2 — Create a feature branch

```bash
git checkout develop
git pull origin develop
git checkout -b feature/<kebab-case-phase-name>
```

### Step 3 — Draft and confirm `requirements.md`

Draft a `requirements.md` covering:
- **Scope** — what this phase does (In Scope / Out of Scope lists)
- **Key Decisions** — a table of Decision / Choice / Rationale for non-obvious choices
- **Context** — what prior phases established and why this phase follows from them

**Before writing the file**, use `AskUserQuestion` to surface the key decisions and scope
questions. Ask about:
- Any In Scope / Out of Scope ambiguities
- Key technical or product decisions the phase involves
- Any constraints from `mission.md` or `tech-stack.md` that affect approach

Apply the user's answers, then write the file to
`phases/YYYY-MM-DD-<name>/requirements.md`.

### Step 4 — Draft and confirm `plan.md`

Draft a `plan.md` broken into numbered **Task Groups**, each with numbered sub-tasks.
Sub-tasks must name exact file paths, types, function signatures, and copy strings where
applicable — specific enough that `/phase` can implement them without ambiguity.

**Before writing the file**, use `AskUserQuestion` to confirm the task group breakdown:
- Does the grouping make sense as discrete, verifiable chunks?
- Any ordering concerns or missing sub-tasks?
- Which surface (`backend` or `ios`) each group targets (if mixed)?

Apply the user's answers, then write the file to `phases/YYYY-MM-DD-<name>/plan.md`.

### Step 5 — Draft and confirm `validation.md`

Draft a `validation.md` containing:
- **Definition of Done** header
- A table per area with **Check** / **How to verify** columns — one row per acceptance
  criterion, with concrete verification steps (commands to run, UI interactions, what
  output to expect)
- **Merge Criteria** — the minimum bar for squash-merging into `develop`

**Before writing the file**, use `AskUserQuestion` to confirm:
- Are all acceptance criteria from `requirements.md` covered?
- Are verification steps concrete enough to execute without judgment calls?
- Any manual-only checks (real device, camera) that can't be automated?

Apply the user's answers, then write the file to `phases/YYYY-MM-DD-<name>/validation.md`.

### Step 6 — Review pass

After all three files are written, do a quick self-check:
- `requirements.md` In Scope list is fully reflected in `plan.md` task groups
- Every task group in `plan.md` has at least one corresponding row in `validation.md`
- Nothing in `plan.md` contradicts the Out of Scope list in `requirements.md`

If gaps are found, fix them silently. If a gap requires a user decision, ask before fixing.

### Step 7 — Commit the spec

```bash
git add phases/YYYY-MM-DD-<name>/
git commit -m "spec: <phase name> feature spec"
```

Then tell the user:

```
✅ Spec committed on feature/<name>.

Files:
  phases/YYYY-MM-DD-<name>/requirements.md
  phases/YYYY-MM-DD-<name>/plan.md
  phases/YYYY-MM-DD-<name>/validation.md

Next: review the spec, ask for any changes, then run /phase <YYYY-MM-DD-<name>> to implement.
```

## Important constraints

- **Never write a file before asking the relevant questions for that file.** The
  `AskUserQuestion` call for each doc must come before the `Write` call for that doc.
- Refer to `specs/mission.md` and `specs/tech-stack.md` throughout — the spec must stay
  consistent with the project constitution.
- The triad must follow the format established by prior phases in `phases/` — use the most
  recent completed phase as a style reference.
- Do not begin implementation — that is `/phase`'s job.
