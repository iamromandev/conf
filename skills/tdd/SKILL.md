---
name: tdd
description: Write a failing test before the code that makes it pass, for new features, bug fixes and behavior changes. Use whenever you're about to write or change production code in a project that has tests.
---

# Test-driven development

Every change to behavior starts with a test that fails for the right reason.

## Cycle
1. **Red**: write one small test for the next piece of behavior. Run it and confirm it fails for the expected reason (a failed assertion), not a typo, import error or missing fixture.
2. **Green**: write the minimum code that makes it pass. Run it, plus the tests around it.
3. **Refactor**: clean up the code and the test while everything stays green. Run them again.
4. Repeat until the behavior is complete, then run the full suite.

## Rules
- Use the project's existing test framework, layout and naming. Don't add a new framework or dependency without asking.
- Test behavior through the public interface, not implementation details. Mock only at real boundaries (network, clock, filesystem, external services).
- One behavior per test, with a name that says what it checks.
- If you already wrote code without a test, write the test now and prove it can fail: temporarily break or revert the code, watch the test fail, then restore it.
- Don't change a test just to make it pass. If the test itself is wrong, fix it and say why.

## When to skip
Throwaway prototypes, pure config, generated code and docs, or a project with no test setup. Say that you skipped it and why; don't invent a test framework.
