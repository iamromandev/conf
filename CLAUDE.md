## Claude Code subagents

- These rules are for the main conversation. A subagent does its own task, without dispatching other agents or using `scope` unless that task says to, and reports back instead of asking me.
- Small, obvious changes (a few lines, one file): do them directly, no skills or subagents.
- Mechanical changes in any number of files (renames with every reference updated, config values, doc edits, rewording that keeps the meaning) that don't touch logic, security, auth or data: do them directly too, without `blueprint` or `critic`; update the tests that cover them first, if any.
- Broad searches across many files, or open-ended "where/how is X" → `scout`. Read a known file directly.
- Vague or loose feature request → `scope` skill with me first, then `spec` with the agreed summary, then `blueprint` with the spec.
- Non-trivial change → `blueprint` skill, then `build` to implement it test-first with `tdd`, then `critic`.
- Something broken and the cause isn't known → `inspect` skill, which fixes it test-first with `tdd`.
- Run `spec`, `blueprint` and `build` yourself, in this conversation; ask me questions that would change the scope or plan as they come up.
- Give `critic` the plan, the build report (especially Deviations), and the changed files or commit range.
- If `critic` reports any Critical or Should-fix finding, whatever its verdict, fix them with `build` and re-run `critic` with its findings and the build report; Nits alone don't need a fix round. Stop after 1 round and report to me.
- Before saying work is done, fixed or passing (including when a subagent reports "Done") → `check` skill.
- Git work (commit, push, PR, merge) only when I ask, up to the stage I name. Load the `ship` skill first; its rules take precedence over the default git instructions where they conflict.
- Agent model and effort: per call, move each at most one step from its default (haiku → sonnet → opus, low → medium → high → xhigh), never max. Raise for security/auth, data migrations, irreversible or destructive operations, concurrency, or a re-run after review; you may lower small, mechanical or single-file calls. Announce an override in one line, like "critic at xhigh: auth change"; say nothing for defaults. If I name a model or effort, use exactly that (even max or fable) with the other at default, and ignore the rest of this rule.
<!-- conf: end of section -->
