---
name: build
description: Carry out an implementation plan (usually from the `blueprint` skill) or a list of review findings, step by step, test-first. Writes and edits code, runs builds, tests and linters, and fixes failures until they pass. Not for small, obvious edits.
---

# Build

Turn the plan into working code, in this conversation.

## Process
1. Follow the plan step by step. If the plan doesn't match the code, take the smallest sensible deviation and note it. Don't redesign.
2. Read the surrounding code before editing; match its style, naming, error handling and patterns.
3. Work in small increments. After each meaningful step, run the relevant build, tests or linter.
4. When something fails, read the actual error, fix the root cause, and re-run. Never weaken or delete tests to make them pass.
5. Write the report, then hand the change to `reviewer` if CLAUDE.md asks for a review.

## Review findings
When the input is a `reviewer` report instead of a plan:
1. Fix the Critical findings first, then Should fix. Leave Nits unless asked.
2. Treat each finding's suggested fix as a starting point: confirm the problem in the code, then make the smallest fix. If a finding is wrong or out of scope, skip it and say why instead of forcing a change.
3. For a bug, write a failing test that shows it before fixing it (the `tdd` skill), unless it can't be tested.
4. Re-run the tests and checks that cover all the fixed code, not only the last fix.

## Rules
- Stay in scope: no drive-by refactors, renames or dependency upgrades unless asked.
- No secrets, credentials or debug leftovers in the code.
- Test first: for behavior you add or change, follow the `tdd` skill. If the project has no test setup, say so; don't add a framework.
- If you're blocked (missing info, broken environment, ambiguous requirement), ask the user instead of guessing.
- Don't commit, push, or open PRs unless explicitly asked.

## Report
- **Done**: what you changed, by file
- **Verification**: commands you ran and whether they passed
- **Deviations / follow-ups**: anything that differs from the plan or still needs attention
- **Findings** (review findings only): each finding as fixed, with how, or skipped, with why
