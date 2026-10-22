# conf

Subagents, skills and a CLAUDE.md section that give Claude Code a consistent workflow: agree on scope, write a spec, plan, build test-first, review, and verify before calling anything done.

## What's included

### Agents (`agents/`)

| Agent | Model | Effort | Tools | Use it for |
|---|---|---|---|---|
| `explorer` | haiku | low | read-only | Broad searches across many files, docs or web pages; "where/how is X" questions |
| `reviewer` | sonnet | medium | read-only | Reviewing a non-trivial change for bugs, security and design issues |

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
| `check` | Run the real checks and read the output before claiming anything is done, fixed or passing |

### `CLAUDE.md`

A "Claude Code subagents" section that tells the main conversation when to use each agent and skill, and what to pass between them. `spec`, `blueprint` and `build` were agents (`specifier`, `planner`, `builder`); as skills they run one after another in the main conversation, which skips each agent's cold start and re-reading, and lets them ask you questions directly. Subagents load CLAUDE.md too (except the built-in `Explore` and `Plan`), so it also tells them to do their own task and report back instead of following the routing themselves.

## Workflow

```
small, obvious change      → do it directly
vague request              → scope (with you) → spec → blueprint → build → reviewer
clear, non-trivial change  → blueprint → build → reviewer
something broken           → inspect → small fix directly, or blueprint → build → reviewer
reviewer finds issues      → build → reviewer again (max 1 round)
before saying "done"       → check
git, only when you ask     → branch → commit → PR → merge (+ cleanup, issue to Done)
```

- `scope`, `spec`, `blueprint` and `build` run in the main conversation, so Claude asks you questions that would change the scope or plan as they come up.
- `reviewer` is still a subagent, so it reviews the change with fresh eyes. It gets the plan, the build report (especially Deviations) and the changed files or commit range. In a git repo it also checks `git status`, `git diff` and `git diff --staged` itself, and mentions any uncommitted work of yours that isn't part of the change without reviewing it.
- If `reviewer` reports any Critical or Should-fix finding, whatever its verdict (so "Approve with changes" counts too), Claude fixes them with `build` and runs `reviewer` again, which checks each finding was fixed. Nits alone don't start a fix round. After 1 round Claude stops and reports to you.
- Claude commits, opens PRs and merges only when you ask, and stops at the stage you name. It stays on the branch made for the task, or cuts one from the current branch (`123-short-name`, or `fix/short-name` without an issue), writes Conventional Commits that end in `(#123)` when there's an issue, and opens the PR against that parent branch with Summary, Changes and Testing sections. It merges once CI has passed, the branch is rebased onto its base and no review requests changes or has unresolved threads: a rebase merge for 1 commit, a squash merge for more. Then it deletes the remote and local branch, switches back to the parent and pulls. If there's an issue, it closes it or moves it to Done in whatever tracker it lives in (GitHub, Jira, Linear…), unless the merge already did, and comments with a link to the merged PR.

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

**Installs from before `spec-writer` was renamed to `specifier`** (they have `.claude/agents/spec-writer.md`) aren't upgraded cleanly. The installer updates the section but keeps its two old lines that name `spec-writer`, after the new section, and leaves `agents/spec-writer.md` in place, so Claude Code loads both agents. To upgrade one, run the installer, then delete the two `spec-writer` lines it leaves right after the `<!-- conf: end of section -->` comment (the diff it prints shows them), the old `<!-- claude-conf: end of section -->` line if there is one (installs from before the package was renamed to conf), and `agents/spec-writer.md`.

**Installs from before `specifier`, `planner` and `builder` became skills** keep the old routing lines that name them, after the new section, because the package ships no `old-sections/` for that wording. The installer moves the three agents to the backup folder itself. To finish the upgrade, delete the old lines it leaves right after the `<!-- conf: end of section -->` comment; the diff it prints shows them.

The script:
- Copies the agents and skills, skipping any that are already identical.
- Moves `agents/builder.md`, `agents/planner.md` and `agents/specifier.md`, which earlier versions installed, to the backup folder, since they're now skills. An agent of yours with one of those names is moved too.
- Moves anything it replaces to `.claude/conf-backup-<timestamp>/`. Nothing is deleted.
- Replaces the "Claude Code subagents" section of CLAUDE.md and leaves the rest alone, or adds the section at the end if it's missing. It prints a diff of the change and saves the previous file as `CLAUDE.md.bak-<timestamp>`.
  - It recognizes the section by its content: the heading, followed by lines from this package's section, or from an earlier wording saved in `old-sections/` (see "Editing the files" below). Code blocks around it don't matter.
  - Only the package's own lines are replaced. Any other line under the old section, such as a bullet or `@import` you added, a rule you edited or a `###` subsection, is kept where it is, so it ends up after the new section. Several copies of the section are merged into one.
  - The section ends with a `<!-- conf: end of section -->` comment (Claude Code drops HTML comments, so it costs nothing), and the installed section is taken to run to that comment. Without it (if it was deleted, or the section was pasted without its last line), it runs to the next `#` or `##` heading, and a `#` line inside a code block counts too.
  - It warns about lines of the package's section it finds outside the section, such as old bullets under a heading you edited or after a `#` line, so you can delete leftovers.
  - A "Claude Code subagents" heading with none of the package's lines under it, such as a much older or heavily edited copy or an example of yours, is left alone. The section is added as usual, and the script warns about that line on every run until you delete or rename it.
  - If CLAUDE.md needs a change but it or its folder isn't writable, it stops before changing anything, agents and skills included.
  - With `--project`, it uses `./CLAUDE.md`, or `./.claude/CLAUDE.md` if that's where the project keeps it.
- Warns if another CLAUDE.md it can see (yours in `~/.claude`, or the current folder's) also has the section, or an older or edited copy of it, since Claude Code loads all of them.
- Warns if the superpowers plugin is still enabled in your settings. Uninstall it with `/plugin` in Claude Code; its brainstorming and debugging skills overlap with `scope` and `inspect`.

Running it again is safe: unchanged files are reported as unchanged.

**If your old section lives in a project's CLAUDE.md**, run the script with `--project` from that project too, or delete the section there. Otherwise that project keeps its old routing.

### Editing the files

If you change an agent's or skill's `description`, keep it plain, unquoted text that starts with a letter. Avoid ` #`: YAML reads it as the start of a comment, so the rest of the description is silently dropped. Avoid a colon followed by a space (e.g. "step by step: write…") or at the end, too, which isn't valid YAML. If you need either, wrap the description in single quotes and double any apostrophe inside (`it''s`). Don't wrap it in double quotes: `explorer`'s and `scope`'s descriptions contain double quotes, so the frontmatter would stop parsing. Claude Code then skips the agent, or loads the skill without a description.

`CLAUDE.md` must start with the `## Claude Code subagents` heading, end with the end-of-section comment, and have no other headings or end-of-section comments; the installer stops if it doesn't. The installer recognizes an installed section by its lines, so before you reword or remove a line, save the current `CLAUDE.md` in an `old-sections/` folder next to it (e.g. as `old-sections/2026-11.md`). The installer reads every file there, so installs of the old wording are still recognized and updated, instead of being kept as your own lines. Until a line is reworded the package ships no `old-sections/` folder, and `tests/regress.sh` checks that (P5), so update that check when you add one. Leave the end-of-section comment itself as it is (`END_MARK` in `install.sh`): the installer finds where an installed section ends by it.

### Manual install

Copy `agents/*.md` to `~/.claude/agents/`, each folder in `skills/` to `~/.claude/skills/`, and paste `CLAUDE.md`, including its last line (the end-of-section comment), into your own CLAUDE.md in place of any existing "Claude Code subagents" section. If an older install left `agents/spec-writer.md`, `agents/specifier.md`, `agents/planner.md` or `agents/builder.md`, delete them, since they're now the `spec`, `blueprint` and `build` skills.

## Undo

Move the files back from `.claude/conf-backup-<timestamp>/` (in `~/.claude` or your project), and restore `CLAUDE.md.bak-<timestamp>` over `CLAUDE.md`. Then delete the installed agents and skills you no longer want.

## Tests

`tests/regress.sh` runs `install.sh` through about 115 checks: fresh installs and re-runs, `--dry-run`, `--project`, updating an installed section with your own lines around and inside it, with or without its end-of-section comment and after a line is reworded, and CLAUDE.md edge cases such as code blocks, other "Claude Code subagents" headings, Windows line endings and byte order marks. It compares the resulting files byte for byte.

```bash
bash tests/regress.sh
```

Every run works in a new temp folder with its own `HOME`, so your `~/.claude` is never touched. The folder is deleted when all checks pass and kept when one fails (or always, with `KEEP=1`). It needs bash and the usual Unix tools; with Ruby installed it also checks that every agent's and skill's frontmatter parses. To test another copy of the package, pass its folder: `bash tests/regress.sh path/to/conf`.

## Naming

The names avoid clashes with Claude Code's built-ins:
- `explorer`, not `Explore`, because a built-in agent uses that name.
- `blueprint`, not `plan`, because of the built-in `/plan` command and `Plan` agent.
- `reviewer`, not `review`, because of the built-in `/review` command.
- `inspect`, not `debug`, and `check`, not `verify`, because `/debug` and `/verify` are built-in.

Because `explorer` doesn't replace the built-in `Explore`, Claude can still use `Explore` on its own, which may run on a larger model than haiku and returns its own report format. That's an accepted trade-off for consistent `-er` names; naming the agent `Explore` instead would make your haiku version replace the built-in everywhere.
