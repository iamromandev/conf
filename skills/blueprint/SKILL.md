---
name: blueprint
description: Plan a change step by step, with acceptance criteria and phases, for smith to build. Run it as /blueprint after spec; the next step is asking smith to build it.
argument-hint: the request, or a task folder to save to
---

# Blueprint

Plan the change before writing code, in this conversation, so `smith` can follow it step by step.

Given a finding, or a `smith` report saying the plan doesn't hold, revise the existing plan (the saved `plan.md`, or the one in this conversation) to account for it and the code already in the tree.

Start from the spec agreed in this conversation, or the `spec.md` the request names; without either, write your own acceptance criteria. For items still open in the spec's Open questions, ask the user or record an assumption.

1. Restate the goal and success criteria in a sentence or two. If a question would change the plan, ask the user now (AskUserQuestion when it's available). For the rest, state the assumption you're taking.
2. Research in proportion to the change: read the files that change and their direct callers and tests, then stop once you can write concrete steps. Skip what you already read in this conversation. Hand broad searches (where something lives, what uses it, across many files) to `scout` and read only the files it points to. Follow existing patterns, conventions and test setup rather than inventing new ones.
3. When the right approach isn't obvious, weigh at least two; pick one and say why in a line.
4. Write the plan and save it as described in Save.

Rules:
- No code changes while planning.
- Carry the spec's requirement IDs (R, NFR) into the acceptance criteria and the test strategy.
- Architecture, Interfaces & data models, Test strategy and Rollout & rollback may each say "n/a" with a reason when they don't apply, such as for a small refactor.
- Write it for someone who hasn't seen this conversation, since `smith` gets only the plan: include the decisions made and why.
- Be concrete: real file paths, function names, and the shape of each change. No vague steps like "update the logic".
- Keep steps small and ordered so each one can be built and verified on its own.
- Split the plan into phases when it's too big for one `smith` run (roughly more than 8 steps, or parts that can be built and reviewed on their own). Each phase must leave the code building and the tests passing.
- Call out risks: breaking changes, migrations, security, performance, anything irreversible.

Output:
- **Goal**: one line
- **Approach**: 2-4 sentences, plus the alternative you rejected and why
- **Acceptance criteria**: the spec's, as written, with their requirement IDs; without a spec, observable checks that show the change works
- **Architecture**: the components touched or added and how they interact
- **Interfaces & data models**: signatures, schemas, API shapes and migrations, decided before the steps
- **Test strategy**: for each acceptance criterion and NFR, the test level (unit, integration or end-to-end) and how it runs
- **Rollout & rollback**: flags, migration order and how to undo the change
- **Phases** (only when split): each phase's name and the steps it covers
- **Steps**: numbered; for each, the files touched, what changes, and how to verify it
- **Tests**: files to add or update
- **Risks & assumptions**

## Save
Ask the user whether to save the plan to `docs/conf/tasks/<slug>/plan.md` or keep it in the conversation (AskUserQuestion when it's available). If the spec for this task was saved in this conversation, reuse its folder and don't ask again.
To save:
- The slug is `<issue>-<short-kebab-name>` (`42-csv-export`, `ABC-12-sso`), or `<short-kebab-name>` without an issue. If `docs/conf/tasks/<slug>/` exists and its `plan.md` is for the same task (same summary or issue), update it in place; otherwise append `-2` (or the next free number) to the slug.
- Create the folder in the project's root and write `plan.md` there.
- In a git repo, unless `git check-ignore -q docs/conf/tasks/<slug>/plan.md` already succeeds, first add the line `**/docs/conf/tasks/` to the repo's `.git/info/exclude` (in a worktree, the `info/exclude` under `git rev-parse --path-format=absolute --git-common-dir`), creating it if needed. Never edit `.gitignore` or any other tracked file for this.
- If the exclude write fails, tell the user the folder will show up in `git status`, and keep going. Outside git, skip it and say so.
- If writing the folder is refused, say so and keep the plan in the conversation.

Next: ask `smith` to build it (pass `plan.md`'s path, or the plan text if it wasn't saved), then `critic` to review.
