---
name: foreman
description: Run a non-trivial task (feature, refactor, fix with a known cause, vague or not) through the whole chain, from route and issue through the scope, spec and plan steps (the `scope`, `spec` and `blueprint` skills), the user's OK, build, review and check, keeping its spec, plan and progress in docs/conf/tasks/<slug>/. Use whenever a task isn't small or mechanical, and to resume one with /foreman <slug>.
argument-hint: task or issue, or a task's slug to resume
---

# Foreman

Run the task through the whole chain in this conversation, loading the `scope`, `spec` and `blueprint` skills for those steps, so every non-trivial task goes the same way: a route the user can see, files that outlive the conversation, and one OK from the user before any code is written.

## Start
1. **Resume or new.** If the argument names a folder in `docs/conf/tasks/`, read its `status.md` and carry on from the step marked next; for a step marked in progress, check the working tree first and run that step again. Before running `smith`, make sure the branch recorded in `status.md` is checked out; switch to it, or ask the user if that isn't possible (for example uncommitted changes in the way). A step that leaves nothing on disk (such as the scope step cut off mid-conversation) simply runs again. With no argument and no task described in the conversation, list the tasks in `docs/conf/tasks/` with their next step and ask which to continue. Otherwise it's a new task.
2. **Issue.** If the task names an issue (a GitHub number or URL, a Jira key or URL, another tracker's URL), read it first with that tracker's tool (`gh issue view`, the Atlassian connector…) and use its title, description and acceptance criteria as input to the scope, spec and plan steps. If you can't reach it, say so and go on from the user's words.
3. **Triage.** If the task is small, obvious or mechanical (see CLAUDE.md), say so in one line instead of a Route line and do it that way, with no task folder. Otherwise pick the route:
   - vague (leaves open what to build, who it's for, or what "done" means) → the `scope` skill, then `spec`
   - new or changed behavior → `spec`
   - a refactor, or a fix whose cause is known (for example from `inspect`) → straight to `blueprint`

   Every route then goes `blueprint` → the user's OK → `smith` (test-first with `tdd`) → `critic`, phase by phase → `check` → report.
4. **Route.** For a new task, once the issue is read and before the scope, spec or plan step, print one line such as `Route: issue #42 → spec → blueprint → your OK → smith → critic → check`. If the route changes later, print the new one.
5. **Task folder.** The slug is `<issue>-<short-kebab-name>` (`42-csv-export`, `ABC-12-sso`), or `<short-kebab-name>` without an issue. Create `docs/conf/tasks/<slug>/` in the project's root. If that folder already exists and its `status.md` names a different issue or task, it belongs to another task: append `-2` (or the next free number) to the slug. In a git repo, unless `git check-ignore -q docs/conf/tasks/<slug>/status.md` already succeeds, first add the line `**/docs/conf/tasks/` to the repo's `.git/info/exclude` (in a worktree, the `info/exclude` under `git rev-parse --path-format=absolute --git-common-dir`), creating it if needed. Never edit `.gitignore` or any other tracked file for this. If the exclude write fails, tell the user the folder will show up in `git status`, and keep going. Outside git, skip it and say so. Then write `status.md`. If writing the task folder is refused, say so and keep the spec, plan and status in the conversation.

Once the task folder exists, load each of `scope`, `spec` and `blueprint` with the Skill tool and the task folder's path. If a scope, spec or plan was already agreed in this conversation (for example from `/scope`, `/spec` or `/blueprint`), write any spec or plan to the task folder and skip the matching step.

## status.md
Update it after every step, so a new session can pick the task up:

```
# <slug>: <the task in one line>
- Issue: <link, or none>
- Route: <the route line>
- Branch: <branch> (or: not cut yet / no git)
- Parent: <parent branch>

## Steps
Each step is done, in progress, next or pending:
- spec: done
- plan: done
- your OK: done
- phase 1, smith: in progress
- phase 1, critic: next
- check: pending

## Notes
Each phase's critic verdict, and smith's Blocked report while it's open.
```

## The user's OK
Show the spec summary (if there's a spec), the acceptance criteria, the plan's goal, approach and steps in short, the path to `plan.md`, and the branch you'll cut. Then ask for the user's OK and wait: no `smith` before it. If they ask for changes, revise the plan (and the spec if needed), save, and ask again. If they said "just do it" or the like when giving the task, take that as the OK and say so. "Just do it" covers only the first OK; a revised plan always waits for the user's OK.

On the OK, keep or cut the task branch as the `ship` skill's Branch section says: named after the slug when there's an issue, otherwise `<type>/<slug>`. Keep the current branch only if the user named it for this task or this task's own `status.md` records it; a branch recorded in another task's `status.md` belongs to that task, so cut the new branch from it, with it as the parent. Record the branch and its parent in `status.md`, and mention uncommitted changes that came along. The OK covers the branch only: commits, pushes and PRs still wait until the user asks.

## Build and review, phase by phase
A plan without phases is one phase. For each phase, in order:
1. Run `smith`, which builds test-first with `tdd`, with the paths to `plan.md` and `spec.md` (if any) and the phase to build. It doesn't see this conversation, so anything it needs that isn't in those files goes in the prompt.
2. If it reports Blocked, note it in `status.md` and ask the user, then continue that same `smith` with the answer, or start a new one with the plan, its Blocked report and the answer if it can't be continued (always the case in a new session). If it says the plan doesn't hold, go back to the plan (below).
3. Run `critic` with the same paths and phase, `smith`'s report (especially Deviations), and the files `smith`'s report lists for this phase (or the phase's commit range), not the whole diff, which without commits includes earlier phases. Record its verdict in `status.md`.
4. At most one fix round per phase:
   - a finding marked `[plan]` → back to the plan
   - otherwise, any Critical or Should-fix finding, whatever the verdict → `smith` with the findings, then `critic` again with its findings and `smith`'s report. Nits alone don't need a round.

   If a Critical finding is still open after the round, stop and report; don't start the next phase.

**Back to the plan.** Load the `blueprint` skill again with the finding, or, when `smith` says "The plan doesn't hold", its report and the code it left in the tree, so the revised plan accounts for it. Save the revised `plan.md` and ask for the user's OK again. After the OK, `smith` builds the phase again from the revised plan, on top of the code already in the tree, and `critic` reviews once more. That loop is the phase's fix round: after it, open findings are reported, not fixed. When a `[plan]` finding comes with ordinary Critical or Should-fix findings in the same report, the ordinary ones go to that `smith` run on the revised plan, so none are dropped.

## Finish
Run the `check` skill against the plan's acceptance criteria, update `status.md`, and report:
- **Steps**: the route as it ran, phase by phase
- **Review**: each phase's `critic` verdict
- **Checks**: what ran, and the result
- **Left**: open findings, unmet criteria, follow-ups
- **Task folder**: `docs/conf/tasks/<slug>/`

Commits, pushes and PRs only when the user asks, with the `ship` skill.

## Rules
- Run in the main conversation: the user's OK and answers can't reach a subagent. `scope`, `spec` and `blueprint` run there too, because they ask the user questions.
- Give `smith` and `critic` file paths, not a pasted plan, so they read the full text.
- No code before the user's OK.
