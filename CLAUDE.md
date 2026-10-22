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
- Git work only when I ask (commit, open a PR, merge), and only up to the stage I name; merging includes cleanup. Run the `check` skill before committing. Without a GitHub remote or a signed-in gh, stop after committing and say why. If the parent branch no longer exists, ask me which base to use.
- Branch: if the current branch was created for this task (by you, or named by me, earlier in this conversation), keep using it; otherwise cut a new branch from the current one, even if that is the default branch, and that branch is its parent. Name it `<issue>-<short-kebab-name>`, or `<type>/<short-kebab-name>` (feat, fix, chore, docs, refactor, test) without an issue. The issue is one I name or the task came from; never search for or create one. Leave uncommitted changes that aren't part of the task out of the commit, and mention them.
- Commits: Conventional Commits, imperative summary of about 72 characters or fewer, ending ` (#<issue>)` when there is an issue, body says why.
- PR: open it with gh against the parent branch (in a later session, the PR's existing base), titled like the commit summary, with Summary, Changes and Testing sections and `Closes #<issue>` when there is one.
- Merge only when CI has passed (none pending or failed; no checks counts as passed, say so), no review requests changes and no review thread is unresolved; otherwise stop and tell me which. If the branch is behind its base, rebase it onto the base (gh pr update-branch --rebase) and wait for CI again; stop on conflicts. Then count the PR's commits and merge without asking again: rebase if the PR has 1 commit, squash if more. If that method isn't allowed, stop and tell me; don't try another method.
- After merging, delete the remote and local branch, switch to the parent branch, pull, and prune stale remote branches.
- Then, when there is an issue, update it in the tracker it lives in (GitHub, Jira, Linear…): close it or move it to Done unless the merge already did, and comment with a link to the merged PR. If you can't reach that tracker, say so instead.
- Per agent call, model and/or effort may move at most one step each from its default, within haiku → sonnet → opus and low → medium → high → xhigh. Never max.
- Raise for security/auth, data migrations, irreversible or destructive operations, concurrency, or a re-run after review. Otherwise you may lower small, mechanical or single-file calls.
- Announce overrides in one line, like "reviewer at xhigh: auth change". No note for defaults.
- If I name a model or effort, use exactly that (even max or fable), the other at default; skip signals, step limit and note.
<!-- conf: end of section -->
