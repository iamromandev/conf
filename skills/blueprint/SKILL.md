---
name: blueprint
description: Plan a change step by step, with acceptance criteria and phases, for smith to build. Foreman's plan step; run it on its own as /blueprint to get only a plan. For a whole task, use foreman.
argument-hint: task folder, or the change
---

# Blueprint

Every route. Plan the change before writing code, in this conversation, so `smith` can follow it step by step.

Where it goes: given a task folder, save the plan as `plan.md` there. With none, show it in the conversation, save nothing, and end by saying `/foreman` builds it.

Given a finding, or a `smith` report saying the plan doesn't hold, revise the existing `plan.md` to account for it and the code already in the tree.

1. Restate the goal and success criteria in a sentence or two. If a question would change the plan, ask the user now (AskUserQuestion when it's available). For the rest, state the assumption you're taking.
2. Research in proportion to the change: read the files that change and their direct callers and tests, then stop once you can write concrete steps. Skip what you already read in this conversation. Hand broad searches (where something lives, what uses it, across many files) to `scout` and read only the files it points to. Follow existing patterns, conventions and test setup rather than inventing new ones.
3. When the right approach isn't obvious, weigh at least two; pick one and say why in a line.
4. Write the plan and save it as described in Where it goes.

Rules:
- No code changes while planning.
- Write it for someone who hasn't seen this conversation, since `smith` gets only the files: include the decisions made and why.
- Be concrete: real file paths, function names, and the shape of each change. No vague steps like "update the logic".
- Keep steps small and ordered so each one can be built and verified on its own.
- Split the plan into phases when it's too big for one `smith` run (roughly more than 8 steps, or parts that can be built and reviewed on their own). Each phase must leave the code building and the tests passing.
- Call out risks: breaking changes, migrations, security, performance, anything irreversible.

Output:
- **Goal**: one line
- **Approach**: 2-4 sentences, plus the alternative you rejected and why
- **Acceptance criteria**: the spec's, as written; without a spec, observable checks that show the change works
- **Phases** (only when split): each phase's name and the steps it covers
- **Steps**: numbered; for each, the files touched, what changes, and how to verify it
- **Tests**: what to add or update
- **Risks & assumptions**
