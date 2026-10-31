## Claude Code subagents

- These rules are for the main conversation. A subagent does its own task, without dispatching other agents or using `scope` unless that task says to, and reports back instead of asking me.
- Small, obvious changes (a few lines, one file): do them directly, no skills or subagents.
- Broad searches across many files, or open-ended "where/how is X" → `explorer`. Read a known file directly.
- Vague or loose feature request → `scope` skill with me first, then `spec` with the agreed summary, then `blueprint` with the spec.
- Non-trivial change → `blueprint` skill, then `build` to implement it test-first with `tdd`, then `critic`.
- Something broken and the cause isn't known → `inspect` skill, which fixes it test-first with `tdd`.
- Run `spec`, `blueprint` and `build` yourself, in this conversation; ask me questions that would change the scope or plan as they come up.
- Give `critic` the plan, the build report (especially Deviations), and the changed files or commit range.
- If `critic` reports any Critical or Should-fix finding, whatever its verdict, fix them with `build` and re-run `critic` with its findings and the build report; Nits alone don't need a fix round. Stop after 1 round and report to me.
- Before saying work is done, fixed or passing (including when a subagent reports "Done") → `check` skill.
- Git work only when I ask (commit, PR, merge), up to the stage I name; merging includes cleanup. Run `check` before committing. Without a GitHub remote or a signed-in gh, stop after committing and say why. If the parent branch is gone, ask me which base to use.
- Branch: if the current branch was made for this task earlier in this conversation (by you, or named by me), keep it; otherwise cut one from the current branch, even the default, and that branch is its parent. Name it `<issue>-<short-kebab-name>`, or `<type>/<short-kebab-name>` (feat, fix, chore, docs, refactor, test) without an issue. The issue is one I name or the task came from; never search for or create one. Leave uncommitted changes that aren't part of the task out of the commit, and mention them.
- Commits: Conventional Commits, imperative summary of about 72 characters or fewer, ending ` (#<issue>)` when there is one; the body says why.
- PR: open it with gh against the parent branch (in a later session, the PR's existing base), titled like the commit summary, with Summary, Changes and Testing sections and `Closes #<issue>` when there is one.
- Merge only when CI has passed (none pending or failed; no checks counts as passed, say so), no review requests changes and no review thread is unresolved; otherwise stop and tell me which. If the branch is behind its base, rebase it with `gh pr update-branch --rebase` and wait for CI again; stop on conflicts. Then merge without asking again: rebase if the PR has 1 commit, squash if more. If that method isn't allowed, stop and tell me; don't try another.
- After merging, delete the remote and local branch, switch to the parent branch, pull, and prune stale remote branches. If there's an issue, close it or move it to Done in its tracker (GitHub, Jira, Linear…) unless the merge did, and comment with a link to the merged PR; if you can't reach the tracker, say so.
- Agent model and effort: per call, move each at most one step from its default (haiku → sonnet → opus, low → medium → high → xhigh), never max. Raise for security/auth, data migrations, irreversible or destructive operations, concurrency, or a re-run after review; you may lower small, mechanical or single-file calls. Announce an override in one line, like "critic at xhigh: auth change"; say nothing for defaults. If I name a model or effort, use exactly that (even max or fable) with the other at default, and ignore the rest of this rule.
<!-- conf: end of section -->
