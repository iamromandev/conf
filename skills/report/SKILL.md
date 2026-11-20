---
name: report
description: Report what a change did and how it solves the feature or bug, or explain any task, feature or function and how it got there. Run it only when the user asks for it, as /report or in words; after a change, suggest it.
argument-hint: a task, feature, function or file, or nothing for the latest change
---
# Report
Explains a change or code from evidence; edits no code.

## Pick the subject
- No argument: the latest change in this conversation. If there is none, say so and ask what to report on.
- An argument matching `docs/conf/tasks/<arg>/`: that task. Read its `spec.md`, `plan.md` and any other files there, and find its commits by branch name, commit messages or the files the plan names.
- Otherwise: code (a feature, function or file).
- If it matches both a task and code, ask which. If it matches nothing, say so and name the closest task folders or symbols.
- Broad searches go to `scout`; it can't ask the user, so ask any question yourself.

## Change report
For no argument or a task. If critic requested changes or smith is Blocked, say so first, before the sections. Sections in this order, each saying "none" when empty:
- **Problem**: the feature or bug, with spec IDs when there are any.
- **Changes**: grouped by purpose, as `file` or `file:line`; mark uncommitted changes uncommitted.
- **How it solves it**: each R/NFR, or the root cause for a fix without a spec, then the change, then the test or check that shows it.
- **Verification**: commands and results, naming who ran them (smith, critic, inspect, or this skill).
- **Deviations & open items**: smith deviations, critic findings not fixed, criteria not met or not checked.

## Code report
For a feature, function or file:
- **How it works**: entry points, flow, `file:line`.
- **How it got here**: commits and PRs from `git log` and `git blame`, plus a matching task folder if any. It works without a task folder. Outside git, say history isn't available.

## Evidence
Every result comes from a run or report earlier in this conversation (name who ran it), a saved file, or a run this skill makes with the narrowest command that covers it. Anything else is written `not verified` with the command that would check it. Never reproduce secrets, credentials, tokens or `.env` values; name the file and say a secret changed.

## Save
The report stays in chat. Only when the user asks to save it, write `docs/conf/tasks/<slug>/report.md` with the same content. Slug rules and the `.git/info/exclude` step (`**/docs/conf/tasks/`, never `.gitignore`) are exactly as in `skills/spec/SKILL.md` "## Save". For a code report with no task, ask for the slug. If `report.md` exists, ask before overwriting.

## Rules
- Run only when the user asks, by `/report` or in words.
- Never edit code, commit, stage or push.
- Keep a change report to about 40 lines for a one-phase change, and follow the session's output style.
