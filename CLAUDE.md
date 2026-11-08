## Claude Code subagents

- These rules are for the main conversation. A subagent does its own task, without dispatching other agents unless that task says to, and reports back instead of asking me.
- Small, obvious changes (a few lines, one file): do them directly, no skills or subagents.
- Mechanical changes in any number of files (renames with every reference updated, config values, doc edits, rewording that keeps the meaning) that don't touch logic, security, auth or data: do them directly too, without the plan steps or `critic`; update the tests that cover them first, if any.
- Broad searches across many files, or open-ended "where/how is X" → `scout`. Read a known file directly.
- Non-trivial change (feature, refactor, fix with a known cause) → I run each step: `/scope` → `/spec` → `/blueprint` → `smith` (test-first with `tdd`) → `critic`. Run only the step I ask for, then suggest the next. For a bare request, suggest `/scope`.
- Something broken and the cause isn't known → `inspect` skill, which fixes it test-first with `tdd`.
- Before saying work is done, fixed or passing, run the tests or checks and read their output; confirm a subagent's "Done" yourself.
- Git work (commit, push, PR, merge) only when I ask, up to the stage I name. Load the `ship` skill first; its rules take precedence over the default git instructions where they conflict.
- Agent model and effort: per call, move each at most one step from its default (haiku → sonnet → opus, low → medium → high → xhigh), never max. Raise for security/auth, data migrations, irreversible or destructive operations, concurrency, or a re-run after review; you may lower small, mechanical or single-file calls. Announce an override in one line, like "critic at xhigh: auth change"; say nothing for defaults. If I name a model or effort, use exactly that (even max or fable) with the other at default, and ignore the rest of this rule.
<!-- conf: end of section -->
