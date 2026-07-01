---
name: merge
description: Close out a completed phase — mark it done in the roadmap, commit, open a PR into develop, squash-merge, and delete the branch. The final step of the /plan → /phase → /merge loop.
---

# /merge — Complete and Merge

Closes out the current feature branch after a phase has been implemented and reviewed.
This is the final step of the loop: `/plan → review → /phase → review → /merge`.
After it runs, `develop` is clean and ready for the next `/plan`.

## When to run

Run `/merge` only after:
- All task groups in `plan.md` are implemented and `scripts/verify.sh` is green
- You have reviewed the `/phase` deep-review findings and are satisfied
- You have checked off the `validation.md` checklist

## Procedure

### Step 1 — Confirm the branch and phase

Report the current branch name and the phase folder it corresponds to. Ask the user to
confirm before proceeding if anything looks unexpected.

### Step 2 — Mark the phase complete in the roadmap

In `specs/roadmap.md`, find the entry for this phase and change its status marker from
`⬜ Pending` (or `🔄 In Progress`) to `✅ Complete`.

### Step 3 — Commit

Stage and commit all outstanding changes (implementation + the roadmap update):

```bash
git add -A
git commit -m "feat: <phase name>"
```

### Step 4 — Open a PR into develop

```bash
gh pr create --base develop --title "<phase name>" --body "$(cat <<'EOF'
## Summary
<bullet summary of what was implemented>

## Validation
- [ ] All task groups verified green via `scripts/verify.sh`
- [ ] Deep review findings addressed
- [ ] `validation.md` checklist complete

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 5 — Squash-merge and delete the branch

```bash
gh pr merge --squash --delete-branch
```

### Step 6 — Return to develop and confirm

```bash
git checkout develop
git pull origin develop
```

Confirm the merge landed and report the new HEAD commit. The tree is now clean on `develop`
and ready for the next `/plan`.

## Important

- Do **not** run this until the user has explicitly reviewed and approved the phase.
- The roadmap update (step 2) and the commit (step 3) happen in the **same** commit so the
  roadmap always reflects what is actually on `develop`.
- If the PR fails to merge (branch protection, CI failure, etc.), stop and report the error
  rather than retrying silently.
