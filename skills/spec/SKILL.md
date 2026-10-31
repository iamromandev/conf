---
name: spec
description: Write agreed scope or a behavior change up as a testable spec with acceptance criteria. Foreman's spec step; run it on its own as /spec to get only a spec. For a whole task, use foreman.
argument-hint: task folder, or the request
---

# Spec

For a vague request (after Scope) and for new or changed behavior. A spec says what to build and why; the plan decides how. Write it so it stands on its own for someone with no context.

Where it goes: given a task folder, save the spec as `spec.md` there. With none, show it in the conversation, save nothing, and end by saying `/foreman` plans and builds it.

Start from the scope summary agreed in this conversation, if there is one.

1. Restate the request in one or two sentences. Identify who it's for and the problem it solves.
2. Research the existing system only as far as the spec needs: the code, docs and tests the change touches, so the spec matches current behavior, terminology and constraints. Skip what you already read in this conversation.
3. Open questions: ask the user the ones whose answer would change the scope, one at a time (AskUserQuestion when it's available). For the rest, state the assumption you're taking.
4. Write the spec and save it as described in Where it goes.

Rules:
- Specify behavior and outcomes, not implementation. Mention files, APIs or data shapes only where they are existing constraints.
- Every requirement must be testable. If you can't say how it would be verified, rewrite it.
- State what is out of scope; it is as useful as what is in.
- Prefer concrete examples (inputs and outputs, user flows) over abstract descriptions.
- Don't invent requirements the request doesn't imply; mark anything speculative as optional or as an open question.
- No code changes while writing the spec.

Output:
- **Summary**: what and why, 2-3 sentences
- **Goals / Non-goals**
- **Users & scenarios**: who does what, with at least one concrete example
- **Requirements**: numbered, each testable (use "must" / "should")
- **Acceptance criteria**: observable checks, ideally Given / When / Then
- **Edge cases & errors**
- **Constraints & dependencies**: existing code, performance, security, compatibility
- **Assumptions**
