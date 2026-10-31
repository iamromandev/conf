# conf

Subagents, skills and a CLAUDE.md section that give Claude Code a consistent workflow: agree on scope, write a spec, plan, build test-first, review, and verify before calling anything done.

## What's included

### Agents (`agents/`)

| Agent | Model | Effort | Tools | Use it for |
|---|---|---|---|---|
| `scout` | haiku | low | read-only | Broad searches across many files, docs or web pages; "where/how is X" questions |
| `critic` | sonnet | high | read-only | Reviewing a non-trivial change for bugs, security and design issues |

"Read-only" for agents with Bash is an instruction in the prompt, not enforced by permissions.

### Skills (`skills/`)

| Skill | What it does |
|---|---|
| `scope` | Talks a vague idea through with you, one question at a time, until the scope is agreed, then hands off to `spec` |
| `spec` | Writes agreed scope up as a testable spec, then hands off to `blueprint` |
| `blueprint` | A step-by-step implementation plan for a non-trivial change, then hands off to `build` |
| `build` | Carries out a plan or review findings test-first, running builds, tests and linters |
| `inspect` | Systematic debugging: reproduce, find the root cause with evidence, then fix with a failing test first |
| `tdd` | Test-driven development: red, green, refactor |
| `critic` | Lets you run the `critic` agent yourself with `/critic`, optionally followed by what to review. Claude doesn't use it; it calls the agent directly |
| `scout` | Lets you run the `scout` agent yourself with `/scout` followed by a question, optionally saying how thoroughly to look. Claude doesn't use it; it calls the agent directly |
| `check` | Run the real checks and read the output before claiming anything is done, fixed or passing |
| `ship` | Commits, pushes, opens a PR or merges when you ask, up to the stage you name, following the branch, commit, PR and merge rules, which take precedence over Claude Code's defaults where they conflict |

### `CLAUDE.md`

A "Claude Code subagents" section that tells the main conversation when to use each agent and skill, and what to pass between them. `spec`, `blueprint` and `build` are skills, so they run one after another in the main conversation, which skips a subagent's cold start and re-reading, and lets them ask you questions directly. Subagents load CLAUDE.md too (except the built-in `Explore` and `Plan`), so it also tells them to do their own task and report back instead of following the routing themselves. Because every session and subagent loads it, it stays short: the git rules live in the `ship` skill, which loads only when you ask for git work.

## Workflow

```
small, obvious change      → do it directly
mechanical change          → do it directly, tests first (renames, config values, wording)
vague request              → scope (with you) → spec → blueprint → build (tdd) → critic
clear, non-trivial change  → blueprint → build (tdd) → critic
something broken           → inspect → fix test-first (tdd), or blueprint → build (tdd) → critic
critic finds issues        → build → critic again (max 1 round)
before saying "done"       → check
git, only when you ask     → ship: branch → commit → PR → merge (+ cleanup, issue to Done)
```

- `build` and `inspect` write code test-first with `tdd`: a failing test, then the code that makes it pass. Small, obvious changes skip it, along with the rest of the workflow.
- Mechanical changes skip `blueprint` and `critic` however many files they touch: renames with every reference updated, config values, doc edits and rewording that keeps the meaning, as long as they don't touch logic, security, auth or data. Claude updates the tests that cover them first, if any, makes the change and runs `check`. A review costs a subagent re-reading the files from scratch, which is rarely worth it for a change with no logic in it.
- `scope`, `spec`, `blueprint` and `build` run in the main conversation, so Claude asks you questions that would change the scope or plan as they come up.
- `critic` is still a subagent, so it reviews the change with fresh eyes. It gets the plan, the build report (especially Deviations) and the changed files or commit range. In a git repo it also checks `git status`, `git diff` and `git diff --staged` itself, and mentions any uncommitted work of yours that isn't part of the change without reviewing it.
- To review a change yourself, type `/critic`, optionally followed by what to review: files, a commit range, a plan or an earlier review's findings. The skill starts the `critic` agent in a fresh context, at its model and effort, and waits for its report. Claude never runs that skill itself: it calls the agent directly, so it can raise the model or effort for a risky change.
- If `critic` reports any Critical or Should-fix finding, whatever its verdict (so "Approve with changes" counts too), Claude fixes them with `build` and runs `critic` again, which checks each finding was fixed. Nits alone don't start a fix round. After 1 round Claude stops and reports to you.
- Claude commits, opens PRs and merges only when you ask, and stops at the stage you name, following the `ship` skill. It stays on the branch made for the task, or cuts one from the current branch (`123-short-name`, or `fix/short-name` without an issue), writes Conventional Commits that end in `(#123)` when there's an issue, and opens the PR against that parent branch with Summary, Changes and Testing sections. It merges once CI has passed, the branch is rebased onto its base and no review requests changes or has unresolved threads: a rebase merge for 1 commit, a squash merge for more. Then it deletes the remote and local branch, switches back to the parent and pulls. If there's an issue, it closes it or moves it to Done in whatever tracker it lives in (GitHub, Jira, Linear…), unless the merge already did, and comments with a link to the merged PR.

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
- Warns if the superpowers plugin is still enabled in your settings. Uninstall it with `/plugin` in Claude Code; its brainstorming and debugging skills overlap with `scope` and `inspect`.

Running it again is safe: unchanged files are reported as unchanged.

**If your old section lives in a project's CLAUDE.md**, run the script with `--project` from that project too, or delete the section there. Otherwise that project keeps its old routing.

### Editing the files

If you change an agent's or skill's `description`, keep it plain, unquoted text that starts with a letter. Avoid ` #`: YAML reads it as the start of a comment, so the rest of the description is silently dropped. Avoid a colon followed by a space (e.g. "step by step: write…") or at the end, too, which isn't valid YAML. If you need either, wrap the description in single quotes and double any apostrophe inside (`it''s`). Don't wrap it in double quotes: `scout`'s and `scope`'s descriptions contain double quotes, so the frontmatter would stop parsing. Claude Code then skips the agent, or loads the skill without a description.

`CLAUDE.md` must start with the `## Claude Code subagents` heading, end with the end-of-section comment, and have no other headings or end-of-section comments; the installer stops if it doesn't. Reword, add or remove lines freely: installs get the new wording on their next run, since the whole section is replaced. Leave the heading and the end-of-section comment as they are (`HEADING` and `END_MARK` in `install.sh`): the installer finds installed sections by them.

### Manual install

Copy `agents/*.md` to `~/.claude/agents/`, each folder in `skills/` to `~/.claude/skills/`, and paste `CLAUDE.md`, including its last line (the end-of-section comment), into your own CLAUDE.md in place of any existing "Claude Code subagents" section.

## Undo

Delete the "Claude Code subagents" section from `CLAUDE.md` (it ends at the `<!-- conf: end of section -->` comment), and the installed agents and skills you no longer want. The installer keeps no backups of what it replaced.

## Tests

`tests/regress.sh` runs `install.sh` through about 100 checks: fresh installs and re-runs, `--dry-run`, `--project`, replacing an installed section with your own lines around and inside it and after a line is reworded, and CLAUDE.md edge cases such as code blocks, headings without an end comment, duplicate copies, Windows line endings and byte order marks. It compares the resulting files byte for byte, and checks the agents' models, the routing in CLAUDE.md and the README against each other, and that `/critic` and `/scout` start their agents.

```bash
bash tests/regress.sh
```

Every run works in a new temp folder with its own `HOME`, so your `~/.claude` is never touched. The folder is deleted when all checks pass and kept when one fails (or always, with `KEEP=1`). It needs bash and the usual Unix tools; with Ruby installed it also checks that every agent's and skill's frontmatter parses. To test another copy of the package, pass its folder: `bash tests/regress.sh path/to/conf`.

## Naming

The names avoid clashes with Claude Code's built-ins:
- `scout`, not `Explore`, because a built-in agent uses that name. A clearly different name also makes the two easier to tell apart. The `scout` skill starts the agent of the same name through `agent: scout` in its frontmatter, so `/scout` runs the agent.
- `blueprint`, not `plan`, because of the built-in `/plan` command and `Plan` agent.
- `critic`, not `review`, because `/review` is a built-in alias of `/code-review`, and a skill named `review` would never run from it. The `critic` skill starts the agent of the same name through `agent: critic` in its frontmatter, so `/critic` runs the agent.
- `inspect`, not `debug`, and `check`, not `verify`, because `/debug` and `/verify` are built-in.

Because `scout` doesn't replace the built-in `Explore`, Claude can still use `Explore` on its own, which may run on a different model and returns its own report format. That's an accepted trade-off; naming the agent `Explore` instead would make your version replace the built-in everywhere.
