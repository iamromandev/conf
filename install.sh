#!/usr/bin/env bash
# Install the claude-conf agents, skills and CLAUDE.md section.
#
# Usage: install.sh [--project] [--dry-run]
#   (default)  install to ~/.claude for all projects; the section goes in ~/.claude/CLAUDE.md
#   --project  install to .claude/ in the current folder, so run it from your project's folder.
#              The section goes in ./CLAUDE.md, or ./.claude/CLAUDE.md if the project keeps it there
#   --dry-run  show what would change, including a diff of CLAUDE.md, without touching anything
#
# Anything replaced or retired is moved to a timestamped backup folder, never deleted.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
PROJECT=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --project) PROJECT=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

HEADING='## Claude Code subagents'
# The last line of the section. Claude Code drops HTML comments from CLAUDE.md, so it costs nothing,
# and it tells the installer where the section ends: whatever you add below it is kept.
END_MARK='<!-- claude-conf: end of section -->'
SECTION="$SRC/CLAUDE.md"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKED_UP=0
RETIRED=0

# awk helpers for reading a CLAUDE.md, shared by md_plan and the section update; see md_awk.
# Each line arrives as `line`, without its Windows line ending (cr = 1 if it had one; repeated \r
# left by older versions are dropped too) or, on line 1, a UTF-8 byte order mark (bom = 1).
# `fence` is the fence of the innermost code block the line is in: set on an opening line, ""
# again on the closing line of the outermost block. `fence_at` is the latest opening line, and
# `outer_at` the opening line of the outermost block still open.
#
# Inside a block, a fence line of the same character, at least as long, with text after it
# (```bash inside ```md) is ambiguous: Markdown makes it plain text, but people write it either
# as a closer with a typo or to open a nested block. nested=0 reads it as a closer, nested=1 as
# a nested opener; md_plan decides which reading to trust.
MD_AWK='
BEGIN { title = h; sub(/^## /, "", title) }
# The fence ("```", "~~~~", ...) that starts this line, or "", with what follows it in `rest`.
# Backticks after a backtick fence make it inline code, as in "```npm test``` runs the tests".
function fence_run(l) {
  rest = ""
  if (!match(l, /^ ? ? ?(```+|~~~+)/)) return ""
  rest = substr(l, RSTART + RLENGTH); l = substr(l, RSTART, RLENGTH); sub(/^ +/, "", l)
  if (substr(l, 1, 1) == "`" && index(rest, "`")) return ""
  return l
}
# True if the line is the section heading, allowing the extra spaces and closing #s Markdown allows.
function is_heading(l) {
  if (l !~ /^##[ \t]/) return 0
  sub(/^##[ \t]+/, "", l); sub(/[ \t]+#+[ \t]*$/, "", l); sub(/[ \t]+$/, "", l); gsub(/[ \t]+/, " ", l)
  return l == title
}
# True if the line is the end-of-section comment.
function is_mark(l) {
  sub(/[ \t]+$/, "", l)
  return l == mark
}
{ line = $0; cr = sub(/\r+$/, "", line); bom = (NR == 1 && sub(/^\357\273\277/, "", line)) }
{
  r = fence_run(line)
  if (!depth) {
    if (r != "") { depth = 1; stack[1] = r; fence_at = outer_at = NR }
  } else if (r != "" && substr(r, 1, 1) == substr(stack[depth], 1, 1) && length(r) >= length(stack[depth])) {
    if (rest ~ /^[ \t]*$/ || !nested) depth--
    else { stack[++depth] = r; fence_at = NR }
  }
  fence = depth ? stack[depth] : ""
}
'

# Run awk program $2 on Markdown file $1 with the MD_AWK helpers; any further arguments go to awk.
md_awk() {
  local file="$1" prog="$2"
  shift 2
  LC_ALL=C awk -v h="$HEADING" -v mark="$END_MARK" "$@" "$MD_AWK$prog" "$file"
}

# Lists the lines, outside code blocks, that hold the section heading, the end-of-section comment
# and any heading; and the opening line of a code block still open at the end of the file (0 if none).
SCAN='
  fence == "" && is_heading(line) { heads = heads " " NR }
  fence == "" && is_mark(line) { marks = marks " " NR }
  fence == "" && line ~ /^#+([ \t]|$)/ { hds = hds " " NR }
  END { printf "%d|%s|%s|%s\n", (fence != "" ? outer_at : 0), heads, marks, hds }
'

# Read file $1 both ways (see MD_AWK) and decide how to treat it. Sets PLAN to found, missing,
# unclosed (no heading outside code, and a code block that's never closed: the heading may be in
# it) or ambiguous (the two readings put the heading in different places and neither is clearly
# right), plus PLAN_NESTED, PLAN_HEADS, PLAN_MARKS and PLAN_HDS (SCAN's lists) for the update, and
# PLAN_LINE for messages.
md_plan() {
  local lenient nested l_open l_heads l_marks l_hds n_open n_heads n_marks n_hds x
  lenient="$(md_awk "$1" "$SCAN" -v nested=0)" || return 1
  nested="$(md_awk "$1" "$SCAN" -v nested=1)" || return 1
  IFS='|' read -r l_open l_heads l_marks l_hds <<< "$lenient"
  IFS='|' read -r n_open n_heads n_marks n_hds <<< "$nested"
  # Prefer a reading in which every code block is closed
  if [ "$l_heads" = "$n_heads" ]; then
    PLAN_NESTED=0
    if [ "$l_open" != 0 ] && [ "$n_open" = 0 ]; then PLAN_NESTED=1; fi
  elif [ "$l_open" = 0 ] && [ "$n_open" != 0 ]; then
    PLAN_NESTED=0
  elif [ "$n_open" = 0 ] && [ "$l_open" != 0 ]; then
    PLAN_NESTED=1
  else
    PLAN=ambiguous PLAN_LINE=""
    for x in $l_heads; do case " $n_heads " in *" $x "*) ;; *) PLAN_LINE="$PLAN_LINE $x" ;; esac; done
    for x in $n_heads; do case " $l_heads " in *" $x "*) ;; *) PLAN_LINE="$PLAN_LINE $x" ;; esac; done
    PLAN_LINE="${PLAN_LINE# }"
    return 0
  fi
  if [ "$PLAN_NESTED" = 1 ]; then
    PLAN_HEADS="$n_heads" PLAN_MARKS="$n_marks" PLAN_HDS="$n_hds" PLAN_LINE="$n_open"
  else
    PLAN_HEADS="$l_heads" PLAN_MARKS="$l_marks" PLAN_HDS="$l_hds" PLAN_LINE="$l_open"
  fi
  if [ -n "$PLAN_HEADS" ]; then PLAN=found
  elif [ "$PLAN_LINE" != 0 ]; then PLAN=unclosed
  else PLAN=missing
  fi
}

# True if the file has the section heading outside code blocks.
has_section() {
  [ -f "$1" ] && md_plan "$1" && [ "$PLAN" = found ]
}

if [ "$PROJECT" = 1 ]; then
  if [ "$PWD" -ef "$SRC" ]; then
    echo "--project installs into the current folder, and that's the claude-conf package itself." >&2
    echo "Run it from your project's folder instead:" >&2
    echo "  cd /path/to/your/project && \"$SRC/install.sh\" --project" >&2
    exit 1
  fi
  if [ "$PWD" -ef "$HOME" ]; then
    echo "The current folder is your home folder. To install for all projects, run without --project." >&2
    exit 1
  fi
  DEST="$PWD/.claude"
  # Use whichever project CLAUDE.md already has the section, else whichever exists, else ./CLAUDE.md
  CLAUDE_MD="$PWD/CLAUDE.md"
  if has_section "$DEST/CLAUDE.md" && ! has_section "$CLAUDE_MD"; then
    CLAUDE_MD="$DEST/CLAUDE.md"
  elif [ ! -f "$CLAUDE_MD" ] && [ -f "$DEST/CLAUDE.md" ]; then
    CLAUDE_MD="$DEST/CLAUDE.md"
  fi
else
  DEST="$HOME/.claude"
  CLAUDE_MD="$DEST/CLAUDE.md"
fi
BACKUP="$DEST/claude-conf-backup-$STAMP"

run() {
  if [ "$DRY_RUN" = 0 ]; then "$@"; fi
}

# Print a status line. In a dry run, the past-tense verbs become "would ...".
say() {
  local verb="$1"
  shift
  if [ "$DRY_RUN" = 1 ]; then
    case "$verb" in
      installed) verb="would install" ;;
      "backed up") verb="would back up" ;;
      retired) verb="would retire" ;;
      updated) verb="would update" ;;
      appended) verb="would append" ;;
      created) verb="would create" ;;
    esac
  fi
  printf '%-14s %s\n' "$verb" "$*"
}

# Move an existing file or folder under DEST into the backup folder, keeping its relative path.
backup() {
  local path="$1" verb="${2:-backed up}" rel="${1#"$DEST"/}"
  [ -e "$path" ] || return 0
  run mkdir -p "$BACKUP/$(dirname "$rel")"
  run mv "$path" "$BACKUP/$rel"
  BACKED_UP=1
  say "$verb" "$rel"
}

# Print the name: value from a file's frontmatter, without quotes, spaces or a Windows line ending.
frontmatter_name() {
  LC_ALL=C awk '{ sub(/\r+$/, ""); sub(/[ \t]+$/, "") }
    NR == 1 { sub(/^\357\273\277/, ""); if ($0 != "---") exit; next }
    $0 == "---" { exit }
    sub(/^name:[ \t]*/, "") {
      sub(/[ \t]+$/, "")
      if ($0 ~ /^".*"$/ || $0 ~ /^\047.*\047$/) $0 = substr($0, 2, length($0) - 2)
      print; exit
    }' "$1" 2>/dev/null
}

# Retire an agent or skill installed under an earlier name. This goes by the name in its frontmatter
# alone, so a file of your own with that exact name is retired too; the summary at the end says so.
retire() {
  local path="$1" name="$2" file="$1"
  [ -e "$path" ] || return 0
  if [ -d "$path" ]; then file="$path/SKILL.md"; fi
  if [ "$(frontmatter_name "$file")" = "$name" ]; then
    backup "$path" retired
    RETIRED=1
  else
    say left "${path#"$DEST"/} (its name isn't $name)"
  fi
}

# Show a diff of CLAUDE.md, indented and without diff's file-name header.
show_diff() {
  diff -u "$1" "$2" | sed '1,2d; s/^/    /' || true
}

# Temp files: the new CLAUDE.md, and the section without Windows line endings or a byte order mark
# (a package copy saved on Windows would otherwise put them in the middle of your CLAUDE.md).
tmpdir="${TMPDIR:-/tmp}"
if [ ! -d "$tmpdir" ] || [ ! -w "$tmpdir" ]; then tmpdir=/tmp; fi
tmp="" section=""
trap 'rm -f "$tmp" "$section"' EXIT
tmp="$(mktemp "$tmpdir/claude-conf.XXXXXX")"
section="$(mktemp "$tmpdir/claude-conf.XXXXXX")"
LC_ALL=C awk 'NR == 1 { sub(/^\357\273\277/, "") } { sub(/\r+$/, ""); print }' "$SECTION" > "$section"
export CLAUDE_CONF_SECTION="$section"

if [ "$DRY_RUN" = 1 ]; then echo "Dry run: nothing will change."; fi
echo "Agents and skills: $DEST"
echo "CLAUDE.md section: $CLAUDE_MD"
echo

# Check CLAUDE.md before changing anything, so a file the section can't safely go in stops the
# whole install rather than leaving new agents next to old routing.
if [ -f "$CLAUDE_MD" ]; then
  if ! md_plan "$CLAUDE_MD"; then echo "Couldn't read $CLAUDE_MD" >&2; exit 1; fi
  case "$PLAN" in
    unclosed) problem="the code block that starts on line $PLAN_LINE is never closed, and the section heading may be inside it. Close the block" ;;
    ambiguous) problem="the code block fences around line $PLAN_LINE can be read two ways, so it's unclear whether the \"Claude Code subagents\" heading there is your section or part of an example. Use a longer fence for the outer block (\`\`\`\` around \`\`\`)" ;;
    *) problem="" ;;
  esac
  if [ -n "$problem" ]; then
    printf '%-14s %s\n' error "$CLAUDE_MD: $problem, then run this again. Nothing was changed." >&2
    exit 1
  fi
  # Keep the plan for the update below; has_section overwrites PLAN_*
  NESTED="$PLAN_NESTED" MARKS="$PLAN_MARKS" HDS="$PLAN_HDS"
fi

# Agents
for f in "$SRC"/agents/*.md; do
  rel="agents/$(basename "$f")"
  target="$DEST/$rel"
  if [ -f "$target" ] && cmp -s "$f" "$target"; then say unchanged "$rel"; continue; fi
  backup "$target"
  run mkdir -p "$DEST/agents"
  run cp "$f" "$target"
  say installed "$rel"
done

# Skills
for d in "$SRC"/skills/*/; do
  rel="skills/$(basename "$d")"
  target="$DEST/$rel"
  if [ -d "$target" ] && diff -rq "$d" "$target" >/dev/null 2>&1; then say unchanged "$rel"; continue; fi
  backup "$target"
  run mkdir -p "$DEST/skills"
  run cp -R "${d%/}" "$target"
  say installed "$rel"
done

# Earlier names of the same agents and skills
retire "$DEST/agents/plan.md" Plan
retire "$DEST/agents/build.md" build
retire "$DEST/agents/review.md" review
retire "$DEST/agents/spec.md" spec
retire "$DEST/agents/explore.md" Explore
retire "$DEST/skills/brainstorming" brainstorming
retire "$DEST/skills/systematic-debugging" systematic-debugging
retire "$DEST/skills/verify-before-done" verify-before-done
retire "$DEST/skills/test-driven-development" test-driven-development

# CLAUDE.md: replace the section, or append it if it's missing (md_plan above said which). The old
# section runs from its heading to its end-of-section comment, if no other heading comes first.
# Otherwise (a section written by an older version, say) it runs to the next heading of any level,
# ---/***/___ line or code block (the section has none, so a code block there is yours).
# Headings inside code blocks don't count.
if [ -f "$CLAUDE_MD" ]; then
  status=0
  md_awk "$CLAUDE_MD" '
    BEGIN { nh = split(hds, hl, " "); nm = split(marks, ml, " ") }
    # The line of the end-of-section comment that belongs to the heading on line n, or 0
    function mark_after(n,   i, j) {
      for (i = 1; i <= nm; i++) {
        if (ml[i] + 0 <= n) continue
        for (j = 1; j <= nh; j++) if (hl[j] + 0 > n && hl[j] + 0 < ml[i] + 0) return 0
        return ml[i] + 0
      }
      return 0
    }
    fence == "" && is_heading(line) {
      if (!found) {
        if (bom) printf "\357\273\277"
        sec = ENVIRON["CLAUDE_CONF_SECTION"]
        while ((getline s < sec) > 0) printf "%s%s\n", s, (cr ? "\r" : "")
      }
      found = 1; skip = 1; end_at = mark_after(NR); next
    }
    skip && end_at { if (NR == end_at) skip = 0; next }
    skip && ((fence != "" && fence_at == NR) || line ~ /^#+([ \t]|$)/ || line ~ /^(---|\*\*\*|___)[ \t]*$/) {
      printf "%s\n", (cr ? "\r" : ""); skip = 0
    }
    !skip { print }
    END { exit (found ? 0 : 3) }
  ' -v nested="$NESTED" -v marks="$MARKS" -v hds="$HDS" > "$tmp" || status=$?

  case "$status" in
    0) verb=updated ;;
    3)
      # No section yet: append it after a blank line, matching the file's line endings
      verb=appended
      eol=""
      if grep -q $'\r' "$CLAUDE_MD"; then eol=$'\r'; fi
      {
        cat "$CLAUDE_MD"
        if [ -s "$CLAUDE_MD" ]; then
          if [ -n "$(tail -c 1 "$CLAUDE_MD")" ]; then printf '%s\n' "$eol"; fi
          printf '%s\n' "$eol"
        fi
        awk -v eol="$eol" '{ print $0 eol }' "$section"
      } > "$tmp" ;;
    *) echo "Couldn't read $CLAUDE_MD" >&2; exit 1 ;;
  esac

  if cmp -s "$tmp" "$CLAUDE_MD"; then
    say unchanged "$CLAUDE_MD"
  else
    say "$verb" "$CLAUDE_MD"
    show_diff "$CLAUDE_MD" "$tmp"
    run cp "$CLAUDE_MD" "$CLAUDE_MD.bak-$STAMP"
    run cp "$tmp" "$CLAUDE_MD"
    if [ "$DRY_RUN" = 0 ]; then echo "               previous copy: $CLAUDE_MD.bak-$STAMP"; fi
  fi
else
  run mkdir -p "$(dirname "$CLAUDE_MD")"
  if [ "$DRY_RUN" = 0 ]; then cat "$section" > "$CLAUDE_MD"; fi
  say created "$CLAUDE_MD"
fi

# Other CLAUDE.md files with the section: Claude Code loads all of them
for other in "$HOME/.claude/CLAUDE.md" "$PWD/CLAUDE.md" "$PWD/.claude/CLAUDE.md"; do
  [ -f "$other" ] || continue
  if [ "$other" -ef "$CLAUDE_MD" ] || [ "$other" -ef "$SECTION" ]; then continue; fi
  if has_section "$other"; then
    if [ "$other" -ef "$HOME/.claude/CLAUDE.md" ]; then hint="install.sh without --project"; else hint="install.sh --project from that folder"; fi
    say warning "$other also has the \"Claude Code subagents\" section, and Claude Code loads both. Remove one, or run $hint to update it."
  fi
done

# superpowers overlaps with these skills
for settings in "$HOME/.claude/settings.json" "$DEST/settings.json" "$DEST/settings.local.json"; do
  if grep -Eqs '"superpowers@[^"]*"[[:space:]]*:[[:space:]]*true' "$settings"; then
    say warning "superpowers is enabled in $settings. Uninstall it with /plugin in Claude Code; its brainstorming and debugging skills overlap with scope and inspect."
    break
  fi
done

echo
if [ "$DRY_RUN" = 1 ]; then
  if [ "$RETIRED" = 1 ]; then
    echo "Files marked \"would retire\" are matched by their name: alone. To keep one of your own,"
    echo "rename the file (or skill folder) first, e.g. agents/review.md to agents/my-review.md."
  fi
  echo "Dry run finished. Run again without --dry-run to apply."
else
  if [ "$BACKED_UP" = 1 ]; then echo "Backups are in $BACKUP"; fi
  if [ "$RETIRED" = 1 ]; then
    echo "Retired files are matched by their name: alone. To keep one of your own, move it back from the"
    echo "backup under another file (or skill folder) name, e.g. agents/my-review.md, or the next run retires it again."
  fi
  echo "Done. Start a new Claude Code session to load the changes."
fi
