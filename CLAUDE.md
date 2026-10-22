## Claude Code subagents

- These rules are for the main conversation. A subagent does its own task, without dispatching other agents or using `scope` unless that task says to, and reports back instead of asking me.
- Small, obvious changes (a few lines, one file): do them directly, no skills or subagents.
- Broad searches across many files, or open-ended "where/how is X" → `explorer`. Read a known file directly.
- Vague or loose feature request → `scope` skill with me first, then `spec` skill with the agreed summary, then `blueprint` skill with the spec.
- Non-trivial change → `blueprint` skill first, then `build` skill to implement it, then `reviewer`.
- Something broken and the cause isn't known → `inspect` skill.
- Run `spec`, `blueprint` and `build` yourself, one after another, in this conversation; ask me questions that would change the scope or plan as they come up.
- Give `reviewer` the plan, the build report (especially Deviations), and the changed files or commit range.
- If `reviewer` reports any Critical or Should-fix finding, whatever its verdict, fix them with the `build` skill, then re-run `reviewer` with its findings and the build report. Nits alone don't need a fix round. Stop after 1 round and report to me.
- Before saying work is done, fixed or passing (including when a subagent reports "Done") → `check` skill.
- Per agent call, model and/or effort may move at most one step each from its default, within haiku → sonnet → opus and low → medium → high → xhigh. Never max.
- Raise for security/auth, data migrations, irreversible or destructive operations, concurrency, or a re-run after review. Otherwise you may lower small, mechanical or single-file calls.
- Announce overrides in one line, like "reviewer at xhigh: auth change". No note for defaults.
- If I name a model or effort, use exactly that (even max or fable), the other at default; skip signals, step limit and note.
<!-- conf: end of section -->
