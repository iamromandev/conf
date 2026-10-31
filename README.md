# conf

Subagents, skills and a CLAUDE.md section that give Claude Code a consistent workflow, run by the `foreman` skill for every non-trivial task: agree on scope, write a spec, plan, build test-first, review, and verify before calling anything done.

## What's included

### Agents (`agents/`)

| Agent | Model | Effort | Tools | Use it for |
|---|---|---|---|---|
| `scout` | haiku | low | read-only | Broad searches across many files, docs or web pages; "where/how is X" questions |
| `critic` | sonnet | high | read-only | Reviewing a non-trivial change for bugs, security and design issues |
| `smith` | sonnet | medium | edits code | Carrying out a plan or review findings test-first; preloads the `tdd` skill |

"Read-only" for agents with Bash is an instruction in the prompt, not enforced by permissions.

### Skills (`skills/`)

| Skill | What it does |
|---|---|
| `foreman` | Runs every non-trivial task through the whole chain: prints the route, reads the issue, loads `scope`, `spec` and `blueprint` for those steps, keeps them and its progress in `docs/conf/tasks/<slug>/`, stops once for your OK, builds and reviews phase by phase, and ends with a report. Run it yourself as `/foreman <task>`, or `/foreman <slug>` to resume |
| `scope` | Talks a vague idea through with you, one question at a time, until the scope is agreed. `foreman` loads it; run it yourself as `/scope` to settle an idea without going on to a spec |
| `spec` | Writes agreed scope or a behavior change up as a testable spec with acceptance criteria. `foreman` loads it; run it yourself as `/spec` to get only a spec |
| `blueprint` | Plans a change step by step, with acceptance criteria and phases, for `smith` to build. `foreman` loads it; run it yourself as `/blueprint` to get only a plan |
| `inspect` | Systematic debugging: reproduce, find the root cause with evidence, then fix with a failing test first |
| `tdd` | Test-driven development: red, green, refactor |
| `check` | Run the real checks and read the output before claiming anything is done, fixed or passing |
| `ship` | Commits, pushes, opens a PR or merges when you ask, up to the stage you name, following the branch, commit, PR and merge rules, which take precedence over Claude Code's defaults where they conflict |

### `CLAUDE.md`

A "Claude Code subagents" section that tells the main conversation when to use each agent and skill. Non-trivial work goes to the `foreman` skill, which holds the chain's details (what `smith` and `critic` get, the fix round, the stop for your OK), so they load only when a task needs them. Scope, spec and plan are the `scope`, `spec` and `blueprint` skills, which `foreman` loads, so they run in the main conversation, which skips a subagent's cold start and lets them ask you questions directly. Building is the `smith` subagent instead: its file reads, diffs and test output stay out of the main conversation, and it runs on its own model and effort, which Claude can raise for a risky change. Subagents load CLAUDE.md too (except the built-in `Explore` and `Plan`), so it also tells them to do their own task and report back instead of following the routing themselves. Because every session and subagent loads it, it stays short: the git rules live in the `ship` skill, which loads only when you ask for git work.

## Workflow

```
small, obvious change      → do it directly
mechanical change          → do it directly, tests first (renames, config values, wording)
non-trivial change         → foreman: route → issue → [scope →] [spec →] blueprint → your OK → branch
                                 → per phase: smith (tdd) → critic → one fix round → check → report
something broken           → inspect → fix test-first (tdd), or foreman from the plan
before saying "done"       → check
git, only when you ask     → ship: branch → commit → PR → merge (+ cleanup, issue to Done)
```

- `smith` and `inspect` write code test-first with `tdd`: a failing test, then the code that makes it pass. Small, obvious changes skip it, along with the rest of the workflow.
- Mechanical changes skip `foreman` and `critic` however many files they touch: renames with every reference updated, config values, doc edits and rewording that keeps the meaning, as long as they don't touch logic, security, auth or data. Claude updates the tests that cover them first, if any, makes the change and runs `check`. A review costs a subagent re-reading the files from scratch, which is rarely worth it for a change with no logic in it.
- `foreman` starts with a route line you can correct, such as `Route: issue #42 → spec → blueprint → your OK → smith → critic → check`. It reads the issue if you name one (GitHub, Jira…). A vague request goes to the scope step then the spec, new or changed behavior to the spec, and a refactor or a fix with a known cause straight to the plan, which writes its own acceptance criteria.
- The `scope`, `spec` and `blueprint` skills run in the main conversation, so Claude asks you questions that would change the scope or plan as they come up.
- Each task's files live in `docs/conf/tasks/<slug>/`, with a slug like `42-csv-export`: `spec.md` (when there's a spec), `plan.md` and `status.md`. They're kept out of git through `.git/info/exclude`, so no tracked file changes. `/foreman <slug>` resumes a task in a new session, and `/foreman` alone lists them.
- There is one stop, after the plan, for your OK. The OK also cuts the task branch, named the way `ship` names them; commits, pushes and PRs still wait until you ask. Saying "just do it" up front skips the stop.
- A big plan is split into phases, each with its own `smith` run and `critic` review.
- `smith` gets the paths to `plan.md` and `spec.md` and the phase to build, so the plan is written for someone who hasn't seen the conversation. `smith` can't ask you anything: if it's blocked, it stops and reports what it needs, Claude asks you, then continues the same `smith` with your answer, or starts a new one with the plan, its report and your answer if it can't be continued. If the plan can't be followed without a design change, it reports "The plan doesn't hold" instead of redesigning.
- `critic` is a subagent too, so it reviews the change with fresh eyes. It gets the plan and spec paths, the phase, `smith`'s report (especially Deviations) and the changed files or commit range. It reports each acceptance criterion as met, not met or not checkable, and marks a finding `[plan]` when fixing it needs a change to the plan. In a git repo it also checks `git status`, `git diff` and `git diff --staged` itself, and mentions any uncommitted work of yours that isn't part of the change without reviewing it.
- Each phase gets one fix round. If `critic` reports any Critical or Should-fix finding, whatever its verdict (so "Approve with changes" counts too), Claude fixes them with `smith` and runs `critic` again, which checks each finding was fixed. Nits alone don't start a round. A `[plan]` finding, or a plan that doesn't hold, goes back to the plan and waits for your OK again; that is the round. A Critical still open after it stops Claude before the next phase.
- After the last phase Claude runs `check` against the acceptance criteria and reports the steps, each `critic` verdict, the checks, what's left and the task folder.
- Claude commits, opens PRs and merges only when you ask, and stops at the stage you name, following the `ship` skill. It stays on the branch made for the task (`foreman` cuts it when you give the OK), or cuts one from the current branch (`123-short-name`, or `fix/short-name` without an issue), writes Conventional Commits that end in `(#123)` when there's an issue, and opens the PR against that parent branch with Summary, Changes and Testing sections. It merges once CI has passed, the branch is rebased onto its base and no review requests changes or has unresolved threads: a rebase merge for 1 commit, a squash merge for more. Then it deletes the remote and local branch, switches back to the parent and pulls. If there's an issue, it closes it or moves it to Done in whatever tracker it lives in (GitHub, Jira, Linear…), unless the merge already did, and comments with a link to the merged PR.

## Install

Needs bash, so macOS, Linux, or Git Bash/WSL on Windows. If you get "permission denied", run the script with `bash` in front, e.g. `bash install.sh`.

Get the package first. The commands below assume it's in `~/conf`:

```bash
git clone https://github.com/iamromandev/conf.git ~/conf
```

For all projects (`~/.claude`):

```bash
cd ~/conf
./install.sh --dry-run    # preview, including a diff of CLAUDE.md
./install.sh
```

For one project (its `.claude/` folder and CLAUDE.md), run it from the project's folder:

```bash
cd /path/to/your/project
~/conf/install.sh --project --dry-run
~/conf/install.sh --project
```

Start a new Claude Code session afterwards to load the changes.

To update later, pull the latest version and run the installer again the same way:

```bash
git -C ~/conf pull
```

The script:
- Copies the agents and skills, skipping any that are already identical.
- Replaces any installed agent or skill that differs from the package's, with no backup, so edits you made to one are lost. A skill folder is replaced whole, files you added to it included. Run with `--dry-run` first to see what would be replaced.
- Replaces the "Claude Code subagents" section of CLAUDE.md and leaves the rest alone, or adds the section at the end if it's missing. It prints a diff of the change and keeps no backup of the previous file.
  - The section runs from the `## Claude Code subagents` heading to the `<!-- conf: end of section -->` comment (Claude Code drops HTML comments, so it costs nothing). Everything in between is replaced, so keep your own rules and `@import`s outside it; lines before and after it are kept as they are. Code blocks aren't parsed, so a heading and end comment inside one count too.
  - A "Claude Code subagents" heading with no end comment after it, or with a `#` or `##` heading before its end comment, such as an older copy or an example of yours, is left alone. The section is added at the end, and the script warns about that line on every run until you delete or rename it.
  - If CLAUDE.md has more than one copy of the section, only the first is updated, and the script warns about the others so you can delete them.
  - Windows line endings and a byte order mark in your CLAUDE.md are kept.
  - If CLAUDE.md needs a change but it or its folder isn't writable, it stops before changing anything, agents and skills included.
  - With `--project`, it uses `./CLAUDE.md`, or `./.claude/CLAUDE.md` if that's where the project keeps it.
- Warns if another CLAUDE.md it can see (yours in `~/.claude`, or the current folder's) also has the section, or a heading of it without the end comment, since Claude Code loads all of them.
- Removes the skills the package no longer ships (critic, scout and smith, shortcuts for the agents of the same name), but only when the installed folder is an unedited copy of what the package shipped. An edited copy, one with extra files or a symlink is left alone with a warning. `--dry-run` shows what would be removed.
- Warns if the superpowers plugin is still enabled in your settings. Uninstall it with `/plugin` in Claude Code; its brainstorming and debugging skills overlap with `foreman` and `inspect`.

Running it again is safe: unchanged files are reported as unchanged.

**If your old section lives in a project's CLAUDE.md**, run the script with `--project` from that project too, or delete the section there. Otherwise that project keeps its old routing.

### Editing the files

If you change an agent's or skill's `description`, keep it plain, unquoted text that starts with a letter. Avoid ` #`: YAML reads it as the start of a comment, so the rest of the description is silently dropped. Avoid a colon followed by a space (e.g. "step by step: write…") or at the end, too, which isn't valid YAML. If you need either, wrap the description in single quotes and double any apostrophe inside (`it''s`). Don't wrap it in double quotes: `scout`'s description contains double quotes, so the frontmatter would stop parsing. Claude Code then skips the agent, or loads the skill without a description.

`CLAUDE.md` must start with the `## Claude Code subagents` heading, end with the end-of-section comment, and have no other headings or end-of-section comments; the installer stops if it doesn't. Reword, add or remove lines freely: installs get the new wording on their next run, since the whole section is replaced. Leave the heading and the end-of-section comment as they are (`HEADING` and `END_MARK` in `install.sh`): the installer finds installed sections by them.

### Manual install

Copy `agents/*.md` to `~/.claude/agents/`, each folder in `skills/` to `~/.claude/skills/`, and paste `CLAUDE.md`, including its last line (the end-of-section comment), into your own CLAUDE.md in place of any existing "Claude Code subagents" section.

## Undo

Delete the "Claude Code subagents" section from `CLAUDE.md` (it ends at the `<!-- conf: end of section -->` comment), and the installed agents and skills you no longer want. The installer keeps no backups of what it replaced. Task folders live in each project's `docs/conf/tasks/`; delete them, and the `**/docs/conf/tasks/` line in that repo's `.git/info/exclude`, if you no longer want them.

## Tests

`tests/regress.sh` runs `install.sh` through about 100 checks: fresh installs and re-runs, `--dry-run`, `--project`, replacing an installed section with your own lines around and inside it and after a line is reworded, and CLAUDE.md edge cases such as code blocks, headings without an end comment, duplicate copies, Windows line endings and byte order marks. It compares the resulting files byte for byte, and checks the agents' models, the routing in CLAUDE.md and the README against each other, that the installer removes unedited copies of the dropped skills and leaves edited ones alone, that `foreman`, `scope`, `spec` and `blueprint` are model-invocable and inline, and that CLAUDE.md routes non-trivial work to it.

```bash
bash tests/regress.sh
```

Every run works in a new temp folder with its own `HOME`, so your `~/.claude` is never touched. The folder is deleted when all checks pass and kept when one fails (or always, with `KEEP=1`). It needs bash and the usual Unix tools; with Ruby installed it also checks that every agent's and skill's frontmatter parses. To test another copy of the package, pass its folder: `bash tests/regress.sh path/to/conf`.

## Naming

The names avoid clashes with Claude Code's built-ins:
- `scout`, not `Explore`, because a built-in agent uses that name. A clearly different name also makes the two easier to tell apart.
- `critic`, not `review`, because `/review` is a built-in alias of `/code-review`.
- `smith` has no built-in to avoid; it's a one-word role like `critic` and `scout`.
- `foreman`, not `task` or `plan`, because Claude Code has its own task tools and a `/plan` command. It's a one-word role like `smith`: the one who runs the job.
- `blueprint`, not `plan`, because Claude Code has a `/plan` command.
- `inspect`, not `debug`, and `check`, not `verify`, because `/debug` and `/verify` are built-in.

Because `scout` doesn't replace the built-in `Explore`, Claude can still use `Explore` on its own, which may run on a different model and returns its own report format. That's an accepted trade-off; naming the agent `Explore` instead would make your version replace the built-in everywhere.
