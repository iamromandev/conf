## Claude Code subagents

- These rules are for the main conversation. A subagent does its own task, without dispatching other agents or using `scope` unless that task says to, and reports back instead of asking me.
- Small, obvious changes (a few lines, one file): do them directly, no subagents.
- Broad searches across many files, or open-ended "where/how is X" → `explorer`. Read a known file directly.
- Vague or loose feature request → `scope` skill with me first, then `specifier` with the agreed summary, then `planner` with the spec.
- Non-trivial change → `planner` first, then `builder` to implement, then `reviewer`.
- Something broken and the cause isn't known → `inspect` skill.
- If `specifier` or `planner` returns BLOCKING questions, ask me before going on.
- Give `builder` the plan verbatim (plus the spec's acceptance criteria, if there is one).
- Give `reviewer` the plan, `builder`'s report (especially Deviations), and the changed files or commit range.
- If `reviewer` requests changes, send its Critical/Should-fix findings to `builder`, then re-run `reviewer`. Stop after 2 rounds and report to me.
- Before saying work is done, fixed or passing (including when a subagent reports "Done") → `check` skill.
- Per agent call, model and/or effort may move at most one step each from its default, within haiku → sonnet → opus and low → medium → high → xhigh. Never max.
- Raise for security/auth, data migrations, irreversible or destructive operations, concurrency, or a re-run after review. Otherwise you may lower small, mechanical or single-file calls.
- Announce overrides in one line, like "reviewer at xhigh: auth change". No note for defaults.
- If I name a model or effort, use exactly that (even max or fable), the other at default; skip signals, step limit and note.
<!-- conf: end of section -->
