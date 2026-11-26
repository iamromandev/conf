---
name: tdd
description: Write a failing test before the code that makes it pass, for new features, bug fixes and behavior changes. Use whenever you're about to write or change production code in a project that has tests.
---

# Test-driven development

Every change to behavior starts with a test that fails for the right reason.

## Cycle
1. **Red**: write one small test for the next piece of behavior (when working outside-in, a failing higher-level test may stay red while unit cycles run under it). Run only that test and confirm it fails for the expected reason (a failed assertion), not a typo, import error or missing fixture.
2. **Green**: write the minimum code that makes it pass. Run it, plus the tests for the code you touched, not the full suite.
3. **Refactor**: clean up the code and the test while everything stays green. If you changed anything, run the same tests again.
4. Repeat until the behavior is complete, then run lint and typecheck.

## Levels
- Unit tests cover logic, integration tests cover module and IO boundaries with real collaborators where cheap, and end-to-end tests cover user-visible flows.
- Take the level from the plan's test strategy, or pick the lowest level that proves the behavior.
- When the behavior spans layers, work outside-in: a failing higher-level test first, then unit tests.

## Rules
- While you work, run the narrowest command that covers the change: one test, file or directory, not the project's whole `make test` or CI check. When the behavior is complete, run the project's lint and typecheck (for a compiled language, the build) and fix what they find. Don't run the full suite; only `ship` runs it, when the user asks.
- Use the project's existing test framework, layout and naming. Don't add a new framework or dependency without asking.
- Test behavior through the public interface, not implementation details. Mock only at real boundaries (network, clock, filesystem, external services).
- One behavior per test, with a name that says what it checks.
- Test only the behaviors the change needs (the spec's acceptance criteria, or the bug being fixed), not every input variation. Cover edge cases only when they carry real risk, and use a parameterized or table test for several cases of one behavior. Add at most one new test per acceptance criterion (or one for the bug); any test beyond that needs a reason in your report.
- Before adding a test, look for an existing one that covers the behavior. If one does, extend or update it instead of writing a near-duplicate.
- In the refactor step, also refactor the tests: delete tests that a newer test fully covers, and tests of behavior you removed. Say which ones you deleted and why.
- If you already wrote code without a test, write the test now and prove it can fail: temporarily break or revert the code, watch the test fail, then restore it.
- Don't change a test just to make it pass. If the test itself is wrong, fix it and say why.

## When to skip
Throwaway prototypes, pure config, generated code and docs, or a project with no test setup. Say that you skipped it and why; don't invent a test framework.
