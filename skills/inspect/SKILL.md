---
name: inspect
description: Find the root cause of a bug, failing test, crash, flaky behavior or unexpected output before changing any code. Use whenever something is broken and the cause isn't already known.
---

# Inspect: systematic debugging

No fix without a root cause you can state and back with evidence.

## Process
1. Reproduce. Get the exact error, stack trace and the command or steps that trigger it. Make it reproduce reliably; if you can't, gather more evidence (logs, inputs, environment) instead of guessing.
2. Read the error in full and find where it's raised.
3. Check what changed: `git log`, `git diff`, dependency, config and environment changes.
4. Trace backward from the symptom to where the bad value or state first appears. Fix it there, not where it surfaces.
5. Form one specific hypothesis and test it with the smallest experiment that could disprove it (a log line, an assertion, a minimal input). Change one thing at a time.
6. Fix, test-first (the `tdd` skill):
   - write a test that reproduces the bug and fails
   - make the minimal fix at the root cause
   - run that test and the related suite
7. If three fix attempts have failed, stop. Question the assumption or the design, and report to the user instead of stacking more fixes.

## Rules
- No shotgun changes: don't try several fixes at once to see what sticks.
- Remove temporary logging and debug code before finishing.
- If the fix is non-trivial (several files, design change), use the `blueprint` skill, then `build`, then `reviewer`, as CLAUDE.md describes.

## Report
- **Root cause**: one or two sentences
- **Evidence**: what proved it
- **Fix**: what changed, by file
- **Verification**: the reproducing test and suite, and whether they passed
