# Spec-Driven Development (SDD) Workflow with Coding Agents

## Creating the Constitution

### Step 1: Create the Project Constitution

Start Claude within the project's root directory and use a prompt like the following:

> We are writing [Application Name], [Optional: Application Short Description]. Look in [Relevant Documentation] for relevant information on the project.
> Let's create a 'constitution' in a specs directory
> - `mission.md`
> - `tech-stack.md`
> - `roadmap.md` for high-level implementation order, in very small phases of work.
>
> Important: You *must* use your AskUserQuestion tool, grouped on these 3, before writing to disk

### Step 2: Review and Refine the Constitution

Read through the generated `specs/` documents and note any corrections or additions. Rather than editing the files directly, ask the agent to apply your changes — this keeps all artifacts consistent and lets the agent propagate updates across related documents if needed.

Example prompt:

> Please update `specs/mission.md` to [describe change]. Also update `specs/roadmap.md` to [describe change].

Additionally, run a clarification pass for each document in the constitution. This surfaces ambiguities the agent can resolve with you before any implementation begins:

> Identify any items in the `mission.md` document that need to be clarified. Important: You *must* use your AskUserQuestion tool.

Repeat this prompt for each document:

> Identify any items in the `tech-stack.md` document that need to be clarified. Important: You *must* use your AskUserQuestion tool.

> Identify any items in the `roadmap.md` document that need to be clarified. Important: You *must* use your AskUserQuestion tool.

### Step 3: Commit the Constitution

Once the constitution documents are reviewed and refined, commit them to version control:

> Please commit the specs directory.

## Building Features from the Roadmap

Repeat this section for each phase on the roadmap until the product is complete.

### Feature Specification

> **Skill:** `/plan`

Run `/plan` to start a new feature. The skill finds the next `⬜ Pending` phase on
`specs/roadmap.md`, creates a `feature/` branch off `develop`, and generates the phase
triad (`phases/YYYY-MM-DD-<name>/{requirements,plan,validation}.md`) — asking you questions
about scope, decisions, and acceptance criteria **before** writing each file to disk.

Review the generated triad. If you find something wrong, ask the agent to fix it rather
than editing directly — this keeps all three files in sync. Time spent here expands into
hundreds of lines of code downstream.

> [Requested change] and update the rest of the feature spec to be in sync.

### Feature Implementation

> **Skill:** `/phase <YYYY-MM-DD-phase-name>`

Run `/phase` with the phase folder name. The skill:
1. Implements task groups from `plan.md` one at a time
2. Self-verifies after each group via `scripts/verify.sh` (exit 0 = green)
3. Iterates on failures up to 3 times per group, then stops for you if stuck
4. When all groups are green, runs a three-agent deep review — **Correctness**, **Design & simplicity**, **Spec compliance** — in parallel
5. Stops and presents the summary + deep-review findings for your review

If you find issues after review, ask the agent to fix them with both the spec and implementation in sync:

> Update phases/YYYY-MM-DD-feature-name/plan.md and implementation to [Requested change]

### Feature Validation and Merge

> **Skill:** `/merge`

Once you are satisfied with the implementation and deep-review findings, run `/merge`. The
skill marks the phase `✅ Complete` in `specs/roadmap.md`, commits, opens a PR into
`develop`, squash-merges, and deletes the branch — leaving `develop` clean and ready for
the next `/plan`.

Note: if large updates were made to the constitution during this phase, it may be better to
make those changes in a separate branch before running `/merge`.

## Project Replanning

### Step 1: Create a Replanning Branch

Create a dedicated branch for replanning work to keep constitution changes isolated:

> Please create a replanning branch.

### Step 2: Validate

#### Update the Validation Workflow (if necessary)

If you want to change how validation is performed, supply the agent your testing preferences so the tech stack and all existing specs stay in sync:

> Update tech-stack.md to capture that we want to use [Preferred Testing Framework] for validation. Update existing specs and code to reflect these testing changes.

#### Write New Tests

Ask the agent to write a test suite using the specified testing framework:

> Write a new test suite using the specified testing framework.

#### Run the Tests and Commit

Run the tests to validate they work, then commit if they pass:

> Run the tests. If they pass, commit the changes.

### Step 3: Change the Product Plan (if necessary)

#### Update the Specs for the New Change

Ask the agent to update all relevant specs and schedule the change on the roadmap:

> [Product request]. Update the product specs and all feature specs to reflect this. Schedule it on the roadmap as its own feature phase.

#### Review and Commit

Review the spec and roadmap changes, then commit if all looks good:

> Please commit the spec and roadmap changes.

### Step 4: Revisit the Product Roadmap

Look at the next task in the product roadmap and decide if it still makes sense to be the next one. Make any adjustments to the order or grouping of features. If changes were made, commit them:

> Please commit the roadmap changes.

### Step 5: Automate the Process

The core SDD loop is already automated via three project skills in `.claude/skills/`:

| Skill | Replaces | What it does |
|---|---|---|
| `/plan` | Feature Specification (manual prompts) | Generates the phase triad with guided questions before each file write |
| `/phase` | Feature Implementation + Deep Review | Implements task groups, self-verifies via `scripts/verify.sh`, runs three-agent deep review |
| `/merge` | Complete and Merge (manual steps) | Marks phase complete, commits, PRs into develop, squash-merges, deletes branch |

Additional skills you can add work the same way — create `.claude/skills/<name>/SKILL.md`
with `name` and `description` frontmatter. For example, a changelog skill:

> I want to keep a CHANGELOG.md in the project root, with headings for dates. If no changelog, examine git commits and add bullets for each date. Help me write a skill for this.

Personal skills (available across all your projects) go in `~/.claude/skills/`.

### Step 6: Commit and Merge

Once satisfied with all replanning changes, commit and merge the branch:

> Commit this, switch to main, and merge this branch, then delete it.
