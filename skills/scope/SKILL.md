---
name: scope
description: Settle the scope of any request with the user before it is specced, asking one question at a time for a vague one, until the scope is agreed. Run it as /scope to settle an idea first; the next step is /spec.
argument-hint: the idea or request
---

# Scope

For any request. For a clear one, play your understanding back in a single pass and ask only what's missing; for a vague one, ask one question at a time. Settle what to build with the user, in this conversation, before anything gets specced or planned. Subagents can't ask the user questions; this step exists so that part happens here.
1. Look first. Skim the relevant code and docs (use `scout` for broad searches) so your questions are grounded in what exists.
2. For a clear request, ask only what's missing, then go to step 6. For a vague one, ask one question at a time. Prefer multiple choice with your recommended option first; use AskUserQuestion when it's available.
3. Cover, in roughly this order:
   - the problem and who it's for
   - must-haves vs nice-to-haves
   - what's explicitly out of scope
   - constraints (compatibility, performance, security, deadlines)
   - how we'll know it works
   - risks and feasibility (unknowns, risky parts; suggest a spike when feasibility is unclear)
   - size (S/M/L, or number of phases)
   - priority: rank the must-haves and mark the smallest version worth shipping first
4. Where there's a real design choice, propose 2-3 approaches with trade-offs and recommend one.
5. Stop once further answers wouldn't change the scope. Usually that's 3-8 questions; this applies to a vague request.
6. Play it back in a short summary: goal, in scope, out of scope, chosen approach, **Risks & feasibility**, **Size**, **Priority / smallest version worth shipping**, and assumptions. Ask the user to confirm or correct it.

Rules:
- No code changes while scoping.
- Don't ask what you can find out from the code yourself.
- Don't ask questions whose answer wouldn't change what gets built.
- If the user says "just do it", stop asking and state the assumptions you're taking.

The summary stays in this conversation and writes no file.

Next: `/spec`.
