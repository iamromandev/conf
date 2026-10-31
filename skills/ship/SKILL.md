---
name: ship
description: Commit, push, open a pull request or merge, following the branch, commit, PR and merge rules. Use whenever the user asks to commit, push, open a PR or merge, and only up to the stage they name. Merging includes cleanup.
---

# Ship

Take the change as far as the user asked (commit, PR or merge), and no further.

## Before committing
- Run the `check` skill.
- Without a GitHub remote or a signed-in gh, stop after committing and say why.
- If the parent branch is gone, ask the user which base to use.

## Branch
If the current branch was made for this task, earlier in this conversation (by you, or named by the user), or a `docs/conf/tasks/*/status.md` has a `- Branch:` line naming the current branch (any other branch doesn't count), keep it; otherwise cut one from the current branch, even the default, and that branch is its parent. Name it `<issue>-<short-kebab-name>`, or `<type>/<short-kebab-name>` (feat, fix, chore, docs, refactor, test) without an issue. The issue is one the user names or the task came from; never search for or create one. Leave uncommitted changes that aren't part of the task out of the commit, and mention them; `docs/conf/tasks/` is never committed.

## Commit
Conventional Commits, imperative summary of about 72 characters or fewer, ending ` (#<issue>)` when there is one; the body says why.

## PR
Open it with gh against the parent branch (the `- Parent:` line of that `status.md`, if there is one; in a later session, the PR's existing base), titled like the commit summary, with Summary, Changes and Testing sections and `Closes #<issue>` when there is one.

## Merge
Merge only when CI has passed (none pending or failed; no checks counts as passed, say so), no review requests changes and no review thread is unresolved; otherwise stop and tell the user which. If the branch is behind its base, rebase it with `gh pr update-branch --rebase` and wait for CI again; stop on conflicts. Then merge without asking again: rebase if the PR has 1 commit, squash if more. If that method isn't allowed, stop and tell the user; don't try another.

## After merging
Delete the remote and local branch, switch to the parent branch, pull, and prune stale remote branches. If there's an issue, close it or move it to Done in its tracker (GitHub, Jira, Linear…) unless the merge did, and comment with a link to the merged PR; if you can't reach the tracker, say so.
