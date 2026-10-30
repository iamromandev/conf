#!/usr/bin/env bash
# Install the conf agents, skills and CLAUDE.md section.
#
# Usage: install.sh [--project] [--dry-run]
#   (default)  install to ~/.claude for all projects; the section goes in ~/.claude/CLAUDE.md
#   --project  install to .claude/ in the current folder, so run it from your project's folder.
#              The section goes in ./CLAUDE.md, or ./.claude/CLAUDE.md if the project keeps it there
#   --dry-run  show what would change, including a diff of CLAUDE.md, without touching anything
#
# Agents and skills it replaces are moved to a timestamped backup folder, never deleted.
# CLAUDE.md is updated in place, with no backup; the diff it prints shows what changed.
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
# and it shows where the section ends.
END_MARK='<!-- conf: end of section -->'
SECTION="$SRC/CLAUDE.md"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKED_UP=0

# awk helpers for reading a CLAUDE.md, shared by md_plan, the section update and the check of the
# package's own section; see md_awk. Each line arrives as `line`, without trailing spaces, its
# Windows line ending (cr = 1 if it had one) or, on line 1, a UTF-8 byte order mark (bom = 1).
MD_AWK='
BEGIN { title = h; sub(/^## /, "", title) }
# True if the line is the section heading, allowing the extra spaces and closing #s Markdown allows.
function is_heading(l) {
  if (l !~ /^##[ \t]/) return 0
  sub(/^##[ \t]+/, "", l); sub(/[ \t]+#+[ \t]*$/, "", l); sub(/[ \t]+$/, "", l); gsub(/[ \t]+/, " ", l)
  return l == title
}
# True if the line is the end-of-section comment.
function is_mark(l) {
  sub(/^[ \t]+/, "", l)
  return l == mark
}
{ line = $0; cr = sub(/\r+$/, "", line); bom = (NR == 1 && sub(/^\357\273\277/, "", line)); sub(/[ \t]+$/, "", line) }
'

# Run awk program $2 on Markdown file $1 with the MD_AWK helpers; any further arguments go to awk.
md_awk() {
  local file="$1" prog="$2"
  shift 2
  LC_ALL=C awk -v h="$HEADING" -v mark="$END_MARK" "$@" "$MD_AWK$prog" "$file"
}

# Finds the copies of the section in a CLAUDE.md. An installed copy is a section heading and the
# first end-of-section comment after it, with no other section heading and no other # or ##
# heading between them; everything from the heading through the comment is the package's, and gets
# replaced (### subsections included). Code fences aren't parsed. Any other section heading (an old
# copy without the comment, or something of yours) is left alone.
# Prints "first|later|others": the first installed copy as "heading line:end comment line", the
# heading lines of later installed copies, and the lines of the other section headings.
SCAN='
  is_heading(line) { if (at) others = others " " at; at = NR; next }
  at && line ~ /^ ? ? ?##?([ \t]|$)/ { others = others " " at; at = 0; next }
  at && is_mark(line) { if (first == "") first = at ":" NR; else later = later " " at; at = 0 }
  END { if (at) others = others " " at; printf "%s|%s|%s\n", first, later, others }
'

# Sets PLAN_FIRST, PLAN_LATER and PLAN_OTHERS to SCAN's results for file $1.
md_plan() {
  local out
  out="$(md_awk "$1" "$SCAN")" || return 1
  IFS='|' read -r PLAN_FIRST PLAN_LATER PLAN_OTHERS <<< "$out"
}

# True if the file has an installed copy of the section.
has_section() {
  [ -f "$1" ] && md_plan "$1" && [ -n "$PLAN_FIRST" ]
}

# True if the file has a section heading at all, installed copy or not.
has_heading() {
  [ -f "$1" ] && md_plan "$1" && [ -n "$PLAN_FIRST$PLAN_OTHERS" ]
}

# Temp files: the new CLAUDE.md, and the package's section without Windows line endings, trailing
# spaces, a byte order mark or blank lines around it (a copy saved on Windows would otherwise put
# them in the middle of your CLAUDE.md).
tmpdir="${TMPDIR:-/tmp}"
if [ ! -d "$tmpdir" ] || [ ! -w "$tmpdir" ]; then tmpdir=/tmp; fi
tmp="" section=""
trap 'rm -f "$tmp" "$section"' EXIT
tmp="$(mktemp "$tmpdir/conf.XXXXXX")"
section="$(mktemp "$tmpdir/conf.XXXXXX")"
LC_ALL=C awk 'NR == 1 { sub(/^\357\273\277/, "") } { sub(/\r+$/, ""); sub(/[ \t]+$/, ""); l[NR] = $0 } END {
  s = 1; while (s <= NR && l[s] == "") s++
  e = NR; while (e >= s && l[e] == "") e--
  for (i = s; i <= e; i++) print l[i]
}' "$SECTION" > "$section"
export CLAUDE_CONF_SECTION="$section"

# The package's section must be the heading, then lines of its own, then the end-of-section
# comment, with no other headings or end comments; finding it again in CLAUDE.md relies on that.
if ! md_awk "$section" 'NR == 1 && !is_heading(line) { bad = 1 } NR > 1 && line ~ /^ ? ? ?#+([ \t]|$)/ { bad = 1 }
    is_mark(line) { marks++ } { last = line } END { sub(/^[ \t]+/, "", last); exit (bad || marks != 1 || last != mark) }'; then
  printf '%-14s %s\n' error "The package's CLAUDE.md must start with the \"$HEADING\" heading, end with the line $END_MARK, and have no other headings or end comments. Nothing was changed." >&2
  exit 1
fi

if [ "$PROJECT" = 1 ]; then
  if [ "$PWD" -ef "$SRC" ]; then
    echo "--project installs into the current folder, and that's the conf package itself." >&2
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
  elif has_heading "$DEST/CLAUDE.md" && ! has_heading "$CLAUDE_MD"; then
    CLAUDE_MD="$DEST/CLAUDE.md"
  elif [ ! -f "$CLAUDE_MD" ] && [ -f "$DEST/CLAUDE.md" ]; then
    CLAUDE_MD="$DEST/CLAUDE.md"
  fi
else
  DEST="$HOME/.claude"
  CLAUDE_MD="$DEST/CLAUDE.md"
fi
BACKUP="$DEST/conf-backup-$STAMP"

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
      updated) verb="would update" ;;
      appended) verb="would append" ;;
      created) verb="would create" ;;
    esac
  fi
  printf '%-14s %s\n' "$verb" "$*"
}

# Move an existing file or folder under DEST into the backup folder, keeping its relative path.
backup() {
  local path="$1" rel="${1#"$DEST"/}"
  [ -e "$path" ] || return 0
  run mkdir -p "$BACKUP/$(dirname "$rel")"
  run mv "$path" "$BACKUP/$rel"
  BACKED_UP=1
  say "backed up" "$rel"
}

# Show a diff of CLAUDE.md, indented and without diff's file-name header.
show_diff() {
  diff -u "$1" "$2" | sed '1,2d; s/^/    /' || true
}

if [ "$DRY_RUN" = 1 ]; then echo "Dry run: nothing will change."; fi
echo "Agents and skills: $DEST"
echo "CLAUDE.md section: $CLAUDE_MD"
echo

# CLAUDE.md: work out the new file first, so a problem with it stops the whole install before
# anything changes, rather than leaving new agents next to old routing. The first installed copy
# of the section (see SCAN), heading through end comment, is replaced with the package's section,
# and every other line is kept as it is. If there's no installed copy, the section is appended.
if [ -f "$CLAUDE_MD" ]; then
  if ! md_plan "$CLAUDE_MD"; then echo "Couldn't read $CLAUDE_MD" >&2; exit 1; fi
  if [ -n "$PLAN_FIRST" ]; then
    verb=updated
    # Each line is printed with the newline before it, so a file without a final newline keeps it that way
    nonl=0
    if [ -n "$(tail -c 1 "$CLAUDE_MD")" ]; then nonl=1; fi
    md_awk "$CLAUDE_MD" '
      BEGIN { from += 0; to += 0 }
      function out(s) { printf "%s%s", nl, s; nl = "\n" }
      NR == from {
        if (bom) printf "\357\273\277"
        sec = ENVIRON["CLAUDE_CONF_SECTION"]
        while ((getline s < sec) > 0) out(s (cr ? "\r" : ""))
        next
      }
      NR > from && NR <= to { next }
      { out($0) }
      END { if (!(nonl && NR > to)) printf "%s", nl }
    ' -v from="${PLAN_FIRST%:*}" -v to="${PLAN_FIRST#*:}" -v nonl="$nonl" > "$tmp" || { echo "Couldn't read $CLAUDE_MD" >&2; exit 1; }
  else
    # No installed copy yet: append it after a blank line, matching the file's line endings
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
    } > "$tmp"
  fi
  if cmp -s "$tmp" "$CLAUDE_MD"; then verb=unchanged; fi
else
  cat "$section" > "$tmp"
  verb=created
fi
md_dir="$(dirname "$CLAUDE_MD")"
if [ "$verb" != unchanged ] && { { [ -f "$CLAUDE_MD" ] && [ ! -w "$CLAUDE_MD" ]; } || { [ -d "$md_dir" ] && [ ! -w "$md_dir" ]; }; }; then
  printf '%-14s %s\n' error "$CLAUDE_MD: can't write to it or to its folder, so the section can't be updated. Nothing was changed." >&2
  exit 1
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

# CLAUDE.md, as worked out above
case "$verb" in
  unchanged) say unchanged "$CLAUDE_MD" ;;
  created)
    run mkdir -p "$md_dir"
    if [ "$DRY_RUN" = 0 ]; then cat "$tmp" > "$CLAUDE_MD"; fi
    say created "$CLAUDE_MD" ;;
  *)
    say "$verb" "$CLAUDE_MD"
    show_diff "$CLAUDE_MD" "$tmp"
    run cp "$tmp" "$CLAUDE_MD" ;;
esac
# What the new CLAUDE.md still holds besides the section (line numbers are in the new file)
if md_plan "$tmp"; then
  for n in $PLAN_LATER; do
    say warning "$CLAUDE_MD line $n has another copy of the \"Claude Code subagents\" section, and only the first one is updated. Delete it."
  done
  for n in $PLAN_OTHERS; do
    say warning "$CLAUDE_MD line $n has a \"Claude Code subagents\" heading with no end-of-section comment after it (an older copy, or something of yours), so it's left alone. If it's an old copy, delete it; if it's yours, rename the heading to stop this warning."
  done
fi

# Other CLAUDE.md files with the section: Claude Code loads all of them
for other in "$HOME/.claude/CLAUDE.md" "$PWD/CLAUDE.md" "$PWD/.claude/CLAUDE.md"; do
  [ -f "$other" ] || continue
  if [ "$other" -ef "$CLAUDE_MD" ] || [ "$other" -ef "$SECTION" ]; then continue; fi
  md_plan "$other" || continue
  if [ -n "$PLAN_FIRST" ]; then
    if [ "$other" -ef "$HOME/.claude/CLAUDE.md" ]; then hint="install.sh without --project"; else hint="install.sh --project from that folder"; fi
    say warning "$other also has the \"Claude Code subagents\" section, and Claude Code loads both. Remove one, or run $hint to update it."
  elif [ -n "$PLAN_OTHERS" ]; then
    say warning "$other has a \"Claude Code subagents\" heading too, with no end-of-section comment after it, and Claude Code loads that file as well. If it's an old copy, delete it."
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
  echo "Dry run finished. Run again without --dry-run to apply."
else
  if [ "$BACKED_UP" = 1 ]; then echo "Backups are in $BACKUP"; fi
  echo "Done. Start a new Claude Code session to load the changes."
fi
