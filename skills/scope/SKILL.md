---
name: scope
description: Talk a vague idea or loose feature request through with the user, one question at a time, until the scope is agreed, before any spec, plan or code. Use when the request leaves open what to build, who it's for, or what "done" means.
---

# Scope

Settle what to build with the user, in this conversation, before anything gets specced or planned. Subagents can't ask the user questions; this skill exists so that part happens here.

## Process
1. Look first. Skim the relevant code and docs (use `explorer` for broad searches) so your questions are grounded in what exists.
2. Ask one question at a time. Prefer multiple choice with your recommended option first; use AskUserQuestion when it's available.
3. Cover, in roughly this order:
   - the problem and who it's for
   - must-haves vs nice-to-haves
   - what's explicitly out of scope
   - constraints (compatibility, performance, security, deadlines)
   - how we'll know it works
4. Where there's a real design choice, propose 2-3 approaches with trade-offs and recommend one.
5. Stop once further answers wouldn't change the scope. Usually that's 3-8 questions.
6. Play it back in a short summary: goal, in scope, out of scope, chosen approach, assumptions. Ask the user to confirm or correct it.
7. Hand off: go on with the `spec` skill, using the confirmed summary (and a file path if the user wants the spec saved).

## Rules
- No code and no file edits while scoping.
- Don't ask what you can find out from the code yourself.
- Don't ask questions whose answer wouldn't change what gets built.
- If the user says "just do it", stop asking, state the assumptions you're taking, and hand off.
