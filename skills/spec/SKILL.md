---
name: spec
description: Write agreed scope or a behavior change up as a testable spec with acceptance criteria. Run it as /spec after scope; the next step is /blueprint.
argument-hint: the request, or a task folder to save to
---

# Spec

For a vague request (after Scope) and for new or changed behavior. A spec says what to build and why; the plan decides how. Write it so it stands on its own for someone with no context.

Start from the scope summary agreed in this conversation, if there is one.

1. Restate the request in one or two sentences. Identify who it's for and the problem it solves.
2. Research the existing system only as far as the spec needs: the code, docs and tests the change touches, so the spec matches current behavior, terminology and constraints. Skip what you already read in this conversation.
3. Open questions: ask the user the ones whose answer would change the scope, one at a time (AskUserQuestion when it's available). Anything still unresolved goes in Open questions; state the assumption only for what was decided.
4. Write the spec and save it as described in Save.

Rules:
- Specify behavior and outcomes, not implementation. Mention files, APIs or data shapes only where they are existing constraints.
- Number functional requirements R1, R2… and non-functional ones NFR1, NFR2…. Each NFR covers whichever of performance, security, reliability, accessibility and compatibility apply, with a measurable target and how to verify it.
- Each acceptance criterion names the requirement IDs it proves, and every requirement has at least one criterion.
- Every requirement must be testable. If you can't say how it would be verified, rewrite it.
- State what is out of scope; it is as useful as what is in.
- Prefer concrete examples (inputs and outputs, user flows) over abstract descriptions.
- Don't invent requirements the request doesn't imply; mark anything speculative as optional or as an open question.
- No code changes while writing the spec.

Output:
- **Summary**: what and why, 2-3 sentences
- **Goals / Non-goals**
- **Users & scenarios**: who does what, with at least one concrete example
- **Requirements**: R1…, each testable (use "must" / "should")
- **Non-functional requirements**: NFR1…, each with a measurable target and how to verify it
- **Data & interfaces**: inputs, outputs, user-visible API and data contracts at the behavior level, or "none"
- **Acceptance criteria**: with IDs, each naming the requirement IDs it proves; observable checks, ideally Given / When / Then
- **Edge cases & errors**
- **Constraints & dependencies**: existing code and dependencies, other than the NFRs
- **Open questions**: unresolved items
- **Assumptions**: what was decided

## Save
Ask the user whether to save the spec to `docs/conf/tasks/<slug>/spec.md` or keep it in the conversation (AskUserQuestion when it's available).
To save:
- The slug is `<issue>-<short-kebab-name>` (`42-csv-export`, `ABC-12-sso`), or `<short-kebab-name>` without an issue. If `docs/conf/tasks/<slug>/` exists and its `spec.md` is for the same task (same summary or issue), update it in place; otherwise append `-2` (or the next free number) to the slug.
- Create the folder in the project's root and write `spec.md` there.
- In a git repo, unless `git check-ignore -q docs/conf/tasks/<slug>/spec.md` already succeeds, first add the line `**/docs/conf/tasks/` to the repo's `.git/info/exclude` (in a worktree, the `info/exclude` under `git rev-parse --path-format=absolute --git-common-dir`), creating it if needed. Never edit `.gitignore` or any other tracked file for this.
- If the exclude write fails, tell the user the folder will show up in `git status`, and keep going. Outside git, skip it and say so.
- If writing the folder is refused, say so and keep the spec in the conversation.

Next: `/blueprint`.
