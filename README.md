# claude-conf

Subagents, skills and a CLAUDE.md section that give Claude Code a consistent workflow: agree on scope, write a spec, plan, build test-first, review, and verify before calling anything done.

## What's included

### Agents (`agents/`)

| Agent | Model | Tools | Use it for |
|---|---|---|---|
| `explorer` | haiku | read-only | Broad searches across many files, docs or web pages; "where/how is X" questions |
| `spec-writer` | opus | read-only, plus writing the spec file | Writing agreed scope up as a testable spec |
| `planner` | opus | read-only | A step-by-step implementation plan for a non-trivial change |
| `builder` | sonnet | all except Agent | Carrying out a plan or review findings test-first, running builds, tests and linters |
| `reviewer` | opus | read-only | Reviewing a non-trivial change for bugs, security and design issues |

"Read-only" for agents with Bash is an instruction in the prompt, not enforced by permissions.

### Skills (`skills/`)

| Skill | What it does |
|---|---|
| `scope` | Talks a vague idea through with you, one question at a time, until the scope is agreed, then hands off to `spec-writer` |
| `inspect` | Systematic debugging: reproduce, find the root cause with evidence, then fix with a failing test first |
| `tdd` | Test-driven development: red, green, refactor |
| `check` | Run the real checks and read the output before claiming anything is done, fixed or passing |

### `CLAUDE.md`

A "Claude Code subagents" section that tells the main conversation when to use each agent and skill, and what to pass between them. Subagents load CLAUDE.md too (except the built-in `Explore` and `Plan`), so it also tells them to do their own task and report back instead of following the routing themselves.

## Workflow

```
small, obvious change      → do it directly
vague request              → scope (with you) → spec-writer → planner → builder → reviewer
clear, non-trivial change  → planner → builder → reviewer
something broken           → inspect → small fix directly, or planner → builder → reviewer
reviewer requests changes  → builder → reviewer again (max 2 rounds)
before saying "done"       → check
```

- Subagents can't ask you questions. `spec-writer` and `planner` mark questions that would change the scope or plan as BLOCKING, and Claude asks you those before going on.
- `builder` gets the plan verbatim, plus the spec's acceptance criteria when there is one.
- `reviewer` gets the plan, `builder`'s report (especially Deviations) and the changed files or commit range. In a git repo it also checks `git status`, `git diff` and `git diff --staged` itself, and mentions any uncommitted work of yours that isn't part of the change without reviewing it.
- If `reviewer` requests changes, its findings go back to `builder`. After 2 rounds Claude stops and reports to you.

## Install

Needs bash, so macOS, Linux, or Git Bash/WSL on Windows. If you get "permission denied", run the script with `bash` in front, e.g. `bash install.sh`.

Get the package first. The commands below assume it's in `~/claude-conf`:

```bash
git clone https://github.com/iamromandev/conf.git ~/claude-conf
```

For all projects (`~/.claude`):

```bash
cd ~/claude-conf
./install.sh --dry-run    # preview, including a diff of CLAUDE.md
./install.sh
```

For one project (its `.claude/` folder and CLAUDE.md), run it from the project's folder:

```bash
cd /path/to/your/project
~/claude-conf/install.sh --project --dry-run
~/claude-conf/install.sh --project
```

Start a new Claude Code session afterwards to load the changes.

To update later, pull the latest version and run the installer again the same way:

```bash
git -C ~/claude-conf pull
```

The script:
- Copies the agents and skills, skipping any that are already identical.
- Moves anything it replaces to `.claude/claude-conf-backup-<timestamp>/`. Nothing is deleted.
- Retires older versions of these agents and skills (`plan.md`, `build.md`, `review.md`, `spec.md`, `explore.md`, and the `brainstorming`, `systematic-debugging`, `verify-before-done` and `test-driven-development` skills) to the same backup folder. A file at one of those paths is retired if the `name:` in its frontmatter is the old one (`Plan` for `agents/plan.md`, `review` for `agents/review.md`, and so on), so an agent or skill of your own at that path with that name is retired too. `--dry-run` lists them. To keep one, give it another file or folder name, e.g. `agents/my-review.md`; just moving it back from the backup doesn't last, since the next run retires it again.
- Replaces the "Claude Code subagents" section of CLAUDE.md and leaves the rest alone, or adds the section at the end if it's missing. It prints a diff of the change and saves the previous file as `CLAUDE.md.bak-<timestamp>`.
  - The section ends with a `<!-- claude-conf: end of section -->` comment (Claude Code drops HTML comments, so it costs nothing). Everything from the heading to that comment is replaced, and anything you add after it is kept. A heading of yours between the two is kept too, along with everything after it.
  - A section without the comment, from an older version, is taken to run to the next heading of any level, `---`, `***` or `___` line, or code block (the section has none, so a code block there is yours and is kept). A bullet or `@import` right after it is replaced along with it, so check the diff in `--dry-run` the first time. Headings inside code blocks don't count.
  - If it can't tell safely where the section is, it stops before changing anything, agents and skills included, and names the line to fix. That happens when a code block is never closed and no section comes before it, or when nested code-block fences (```` ```bash ```` inside ```` ```md ````) can be read two ways around a "Claude Code subagents" heading.
  - With `--project`, it uses `./CLAUDE.md`, or `./.claude/CLAUDE.md` if that's where the project keeps it.
- Warns if another CLAUDE.md it can see (yours in `~/.claude`, or the current folder's) also has the section, since Claude Code loads all of them.
- Warns if the superpowers plugin is still enabled in your settings. Uninstall it with `/plugin` in Claude Code; its brainstorming and debugging skills overlap with `scope` and `inspect`.

Running it again is safe: unchanged files are reported as unchanged.

**If your old section lives in a project's CLAUDE.md**, run the script with `--project` from that project too, or delete the section there. Otherwise that project keeps routing to the old agent names, some of which the script retires.

### Editing the files

If you change an agent's or skill's `description`, keep it plain, unquoted text that starts with a letter. Avoid ` #`: YAML reads it as the start of a comment, so the rest of the description is silently dropped. Avoid a colon followed by a space (e.g. "step by step: write…") or at the end, too, which isn't valid YAML. If you need either, wrap the description in single quotes and double any apostrophe inside (`it''s`). Don't wrap it in double quotes: `explorer`'s and `scope`'s descriptions contain double quotes, so the frontmatter would stop parsing. Claude Code then skips the agent, or loads the skill without a description.

### Manual install

Copy `agents/*.md` to `~/.claude/agents/`, each folder in `skills/` to `~/.claude/skills/`, and paste `CLAUDE.md`, including its last line (the end-of-section comment), into your own CLAUDE.md in place of any existing "Claude Code subagents" section.

## Undo

Move the files back from `.claude/claude-conf-backup-<timestamp>/` (in `~/.claude` or your project), and restore `CLAUDE.md.bak-<timestamp>` over `CLAUDE.md`. Then delete the installed agents and skills you no longer want.

## Tests

`tests/regress.sh` runs `install.sh` through about 120 checks: fresh installs and re-runs, `--dry-run`, `--project`, retiring old names, and CLAUDE.md edge cases such as code blocks around the section, the end-of-section comment, Windows line endings and byte order marks. It compares the resulting files byte for byte.

```bash
bash tests/regress.sh
```

Every run works in a new temp folder with its own `HOME`, so your `~/.claude` is never touched. The folder is deleted when all checks pass and kept when one fails (or always, with `KEEP=1`). It needs bash and the usual Unix tools; with Ruby installed it also checks that every agent's and skill's frontmatter parses. To test another copy of the package, pass its folder: `bash tests/regress.sh path/to/claude-conf`.

## Naming

The names avoid clashes with Claude Code's built-ins:
- `explorer` and `planner`, not `Explore` and `Plan`. Built-in agents use those names, and plan mode uses the built-in `Plan` for its research.
- `reviewer`, not `review`, because of the built-in `/review` command.
- `inspect`, not `debug`, and `check`, not `verify`, because `/debug` and `/verify` are built-in.

Because `explorer` doesn't replace the built-in `Explore`, Claude can still use `Explore` on its own, which may run on a larger model than haiku and returns its own report format. That's an accepted trade-off for consistent `-er` names; naming the agent `Explore` instead would make your haiku version replace the built-in everywhere.
