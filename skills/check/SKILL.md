---
name: check
description: Run the actual checks and read their output before saying work is done, fixed or passing. Use before claiming completion, before committing or opening a PR, and before reporting a subagent's work as finished.
---

# Check

A claim of "done", "fixed" or "passing" needs fresh evidence from this session.

## Process
1. Name the check that proves the claim: tests, build, linter, type check, running the app, or the original repro steps for a bug.
2. Run it now, unless the same command already ran in this turn after the last code change and you read its full output; reuse that run instead of repeating it. Any other earlier run doesn't count, and neither does "it's a small change".
3. Read the output: exit code, failure and skip counts, warnings.
4. Check the result against the plan's steps or the spec's acceptance criteria, if there are any.
5. Claim only what the output shows. If something failed, say so and include the relevant output.

## Rules
- "Should work" and "looks right" are not verification.
- A subagent's "Done" or "tests pass" is a claim. For anything that matters, confirm it yourself: read the diff, or re-run the tests unless you already ran them after its last change.
- For a bug fix, confirm the original repro now passes, not just the new test.
- If a check can't run (no tests, broken environment), say exactly what wasn't verified.
