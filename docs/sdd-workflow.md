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

#### Step 1: Clear the Context

Start a fresh session before beginning each feature to avoid carry-over from previous work:

> `/clear`

#### Step 2: Plan the Next Feature

Ask the agent to identify the next phase from the roadmap, create a branch, and generate the feature spec documents. As the agent asks you to make key decisions, pay attention to potential conflicts or problems. You don't have to agree to the solutions proposed by the agent. Make sure to clarify anything that bothers you.

> Find the next phase on specs/roadmap.md and make a branch, ask me about the feature spec.
> Create:
> - A new directory YYYY-MM-DD-feature-name under specs for this feature work
> - In there:
>   - `plan.md` as a series of numbered task groups.
>   - `requirements.md` for the scope, decisions, context
>   - `validation.md` for how to know the implementation succeeded and can be merged
>
> Refer to specs/mission.md and specs/tech-stack.md for guidance.
>
> Important: You *must* use your AskUserQuestion tool, grouped on these 3, before writing to disk.

#### Step 3: Review the Feature Plan, Requirements, and Validation

Read through the generated feature spec documents. If you find something wrong, ask the agent to fix it rather than editing directly — this ensures `requirements.md` and `validation.md` stay in sync with `plan.md`. The changes made here in the specs will expand downstream into hundreds of lines of code, so time spent here is well spent.

> [Requested change] and update the rest of the feature spec to be in sync.

#### Step 4: Commit the Feature Spec

Once the feature spec is reviewed and refined, commit it to version control:

> Please commit the feature spec.

### Feature Implementation

#### Step 1: Clear the Context

Start a fresh session before beginning implementation to avoid carry-over from the planning phase:

> `/clear`

#### Step 2: Implement the Feature

Ask the agent to implement the task groups in your feature's `plan.md`:

> Implement the task groups in plan.md.

Note: sometimes you might choose to do task groups one at a time for smaller commits.

#### Step 3: Observe and Review Progress

As the agent completes each task group, it will provide a summary of the work performed. Review these summaries to ensure the implementation aligns with the feature spec.

#### Step 4: Commit the Implementation

Once the implementation is complete and reviewed, commit the work:

> Please commit the implementation.

### Feature Validation

#### Step 1: Review the Changes

Go through the changes as you would a code review. Focus on high-level concerns — whether the features work and reflect the spec — rather than implementation details.

#### Step 2: Make Changes

If you find issues, ask the agent to fix them, updating both the spec and the implementation together to keep them in sync:

> Update specs/YYYY-MM-DD-feature-name/plan.md and implementation to [Requested change]

#### Step 3: Deep Review (optional)

You can ask the agent to spawn several sub-agents to do a deep review of the entire project with this feature change. This deep review gives the agent more space to think about the changes, and using sub-agents preserves the main agent's context window rather than polluting it. The agent can usually find important issues during a second look.

> Do a deep review: Spawn multiple subagents to go through all the changes on this branch from three different perspectives and see if anything doesn't make sense, could be better, etc.

#### Step 4: Complete and Merge

Once satisfied with the changes, mark the phase as complete and merge the work:

> Mark this specs/roadmap.md phase as complete, commit this work, switch to main, and merge this branch, then delete it.

Note: if large updates were made to the constitution during this phase, it may be better to make those changes in a separate branch.

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

Automate the SDD workflow with skills. You can work with your agent to help you create skills. For example, you can create a changelog skill with the following prompt:

> I want to keep a CHANGELOG.md in the project root, with headings for dates. If no changelog, examine git commits and add bullets for each date. Then, as we work, we will manually invoke this skill before merging. Help me write a skill for this.

Other ideas for skills include a validation skill that packages updating the README, linting, formatting, test writing, and other quality checks into a repeatable, less manual process.

Take note of where the skill is located — whether it's in the global skills area for all projects to use, or in the project root for only this project to use.

### Step 6: Commit and Merge

Once satisfied with all replanning changes, commit and merge the branch:

> Commit this, switch to main, and merge this branch, then delete it.
