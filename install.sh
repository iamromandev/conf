#!/usr/bin/env bash
# Install the conf agents, skills and CLAUDE.md section.
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
# and it shows where the section ends.
END_MARK='<!-- conf: end of section -->'
# The end comment from before the package was renamed from claude-conf. An installed copy that ends
# with it is found and updated like a current one; the package's own CLAUDE.md must end with END_MARK.
OLD_END_MARK='<!-- claude-conf: end of section -->'
SECTION="$SRC/CLAUDE.md"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKED_UP=0
RETIRED=0

# awk helpers for reading a CLAUDE.md, shared by md_plan, the section update and the check of the
# package's own section; see md_awk. Each line arrives as `line`, without trailing spaces, its
# Windows line ending (cr = 1 if it had one; repeated \r left by older versions are dropped too)
# or, on line 1, a UTF-8 byte order mark (bom = 1).
#
# The installed section is found by its content, not by Markdown structure: it's the section
# heading followed by lines of the package's section (`stock`: the current one, plus earlier ones
# saved in old-sections/ when a line is reworded; see README). Code fences aren't parsed, so a
# malformed one can't throw it off, and any line that isn't from the package is yours and is kept.
# A # line inside a code block still counts as a heading where SCAN looks for one.
MD_AWK='
BEGIN {
  title = h; sub(/^## /, "", title)
  stockf = ENVIRON["CLAUDE_CONF_STOCK"]
  while ((getline s < stockf) > 0) if (s != "" && !is_heading(s)) stock[s] = 1
}
# True if the line is the section heading, allowing the extra spaces and closing #s Markdown allows.
function is_heading(l) {
  if (l !~ /^##[ \t]/) return 0
  sub(/^##[ \t]+/, "", l); sub(/[ \t]+#+[ \t]*$/, "", l); sub(/[ \t]+$/, "", l); gsub(/[ \t]+/, " ", l)
  return l == title
}
# True if the line is the end-of-section comment, or the one from before the rename.
function is_mark(l) {
  sub(/^[ \t]+/, "", l)
  return l == mark || l == oldmark
}
# True if the line is a # or ## heading, which ends an old copy of the section without its end comment.
function is_top(l) {
  return l ~ /^ ? ? ?##?([ \t]|$)/
}
{ line = $0; cr = sub(/\r+$/, "", line); bom = (NR == 1 && sub(/^\357\273\277/, "", line)); sub(/[ \t]+$/, "", line) }
'

# Run awk program $2 on Markdown file $1 with the MD_AWK helpers; any further arguments go to awk.
md_awk() {
  local file="$1" prog="$2"
  shift 2
  LC_ALL=C awk -v h="$HEADING" -v mark="$END_MARK" -v oldmark="$OLD_END_MARK" "$@" "$MD_AWK$prog" "$file"
}

# Finds the copies of the section in a CLAUDE.md. A section heading is an installed copy if lines
# of the package's section come right under it, before any other heading; other section headings
# are an older or edited copy, or something of yours. An installed copy runs to its end-of-section
# comment (the current one or the one from before the rename), if one comes before the next section
# heading, and otherwise to the next # or ## heading.
# Prints "installed|others|stray line|strays": the installed copies as "heading line:last line",
# the other headings' lines, and the first and number of package lines outside the installed copies.
SCAN='
  function done_heading(last) {
    if (!at) return
    if (mark_at) last = mark_at; else if (top_at) last = top_at - 1
    if (hits) { installed = installed " " at ":" last; from[++copies] = at; to[copies] = last }
    else others = others " " at
    at = 0
  }
  is_heading(line) { done_heading(NR - 1); at = NR; sub_at = top_at = mark_at = hits = 0; next }
  at && is_mark(line) { mark_at = NR; done_heading(NR); next }
  at && !sub_at && line ~ /^ ? ? ?#+([ \t]|$)/ { sub_at = NR }
  at && !top_at && is_top(line) { top_at = NR }
  (line in stock) && !is_mark(line) {
    pkg[++pkgs] = NR
    if (at && !sub_at) hits++
  }
  END {
    done_heading(NR)
    for (i = 1; i <= pkgs; i++) {
      inside = 0
      for (j = 1; j <= copies; j++) if (pkg[i] > from[j] && pkg[i] <= to[j]) inside = 1
      if (!inside) { if (!stray) stray = pkg[i]; strays++ }
    }
    printf "%s|%s|%d|%d\n", installed, others, stray, strays
  }
'

# Sets PLAN_INSTALLED, PLAN_OTHERS, PLAN_STRAY and PLAN_STRAYS to SCAN's results for file $1.
md_plan() {
  local out
  out="$(md_awk "$1" "$SCAN")" || return 1
  IFS='|' read -r PLAN_INSTALLED PLAN_OTHERS PLAN_STRAY PLAN_STRAYS <<< "$out"
}

# True if the file has an installed copy of the section.
has_section() {
  [ -f "$1" ] && md_plan "$1" && [ -n "$PLAN_INSTALLED" ]
}

# True if the file has a section heading at all, installed copy or not.
has_heading() {
  [ -f "$1" ] && md_plan "$1" && [ -n "$PLAN_INSTALLED$PLAN_OTHERS" ]
}

# Temp files: the new CLAUDE.md; the package's section without Windows line endings, trailing
# spaces, a byte order mark or blank lines around it (a copy saved on Windows would otherwise put
# them in the middle of your CLAUDE.md); and the lines of every version of the section (see MD_AWK).
tmpdir="${TMPDIR:-/tmp}"
if [ ! -d "$tmpdir" ] || [ ! -w "$tmpdir" ]; then tmpdir=/tmp; fi
tmp="" section="" stock=""
trap 'rm -f "$tmp" "$section" "$stock"' EXIT
tmp="$(mktemp "$tmpdir/conf.XXXXXX")"
section="$(mktemp "$tmpdir/conf.XXXXXX")"
stock="$(mktemp "$tmpdir/conf.XXXXXX")"
clean() {
  LC_ALL=C awk 'NR == 1 { sub(/^\357\273\277/, "") } { sub(/\r+$/, ""); sub(/[ \t]+$/, ""); print }' "$1"
}
clean "$SECTION" | LC_ALL=C awk '{ l[NR] = $0 } END {
  s = 1; while (s <= NR && l[s] == "") s++
  e = NR; while (e >= s && l[e] == "") e--
  for (i = s; i <= e; i++) print l[i]
}' > "$section"
{
  cat "$section"
  for f in "$SRC"/old-sections/*.md; do if [ -f "$f" ]; then clean "$f"; fi; done
} > "$stock"
export CLAUDE_CONF_SECTION="$section" CLAUDE_CONF_STOCK="$stock"

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

if [ "$DRY_RUN" = 1 ]; then echo "Dry run: nothing will change."; fi
echo "Agents and skills: $DEST"
echo "CLAUDE.md section: $CLAUDE_MD"
echo

# CLAUDE.md: work out the new file first, so a problem with it stops the whole install before
# anything changes, rather than leaving new agents next to old routing. The first installed copy
# of the section (see SCAN) becomes the new section, and later copies are merged into it: in each
# copy, the package's own lines and the blank lines between them are dropped, and every other line
# is kept where it is. If there's no installed copy, the section is appended.
if [ -f "$CLAUDE_MD" ]; then
  if ! md_plan "$CLAUDE_MD"; then echo "Couldn't read $CLAUDE_MD" >&2; exit 1; fi
  status=0
  md_awk "$CLAUDE_MD" '
    BEGIN { n = split(installed, il, " "); for (i = 1; i <= n; i++) { split(il[i], p, ":"); stop[p[1] + 0] = p[2] + 0 } }
    function flush() { printf "%s", blanks; blanks = "" }
    in_old && NR > end_at && !(NR in stop) { flush(); in_old = 0 }
    (NR in stop) {
      if (!found) {
        if (bom) printf "\357\273\277"
        sec = ENVIRON["CLAUDE_CONF_SECTION"]
        while ((getline s < sec) > 0) printf "%s%s\n", s, (cr ? "\r" : "")
        found = 1
      }
      in_old = 1; end_at = stop[NR]; next
    }
    in_old && (is_mark(line) || (line in stock)) { blanks = ""; next }
    in_old && line == "" { blanks = blanks (cr ? "\r" : "") "\n"; next }
    in_old { flush() }
    { print }
    END { flush(); exit (found ? 0 : 3) }
  ' -v installed="$PLAN_INSTALLED" > "$tmp" || status=$?

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

# Earlier names of the same agents and skills
retire "$DEST/agents/plan.md" Plan
retire "$DEST/agents/build.md" build
retire "$DEST/agents/review.md" review
retire "$DEST/agents/spec.md" spec
retire "$DEST/agents/spec-writer.md" spec-writer
retire "$DEST/agents/explore.md" Explore
retire "$DEST/skills/brainstorming" brainstorming
retire "$DEST/skills/systematic-debugging" systematic-debugging
retire "$DEST/skills/verify-before-done" verify-before-done
retire "$DEST/skills/test-driven-development" test-driven-development

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
    run cp "$CLAUDE_MD" "$CLAUDE_MD.bak-$STAMP"
    run cp "$tmp" "$CLAUDE_MD"
    if [ "$DRY_RUN" = 0 ]; then echo "               previous copy: $CLAUDE_MD.bak-$STAMP"; fi ;;
esac
# What the new CLAUDE.md still holds besides the section (line numbers are in the new file)
if md_plan "$tmp"; then
  for n in $PLAN_OTHERS; do
    say warning "$CLAUDE_MD line $n has a \"Claude Code subagents\" heading with none of this package's lines under it (an older or edited copy, or something of yours), so it's left alone. If it's an old copy, delete it; if it's yours, rename the heading to stop this warning."
  done
  if [ "$PLAN_STRAYS" -gt 0 ]; then
    if [ "$PLAN_STRAYS" = 1 ]; then what="line $PLAN_STRAY repeats a line"; else what="line $PLAN_STRAY and $((PLAN_STRAYS - 1)) more repeat lines"; fi
    say warning "$CLAUDE_MD $what of this package's section outside the section, e.g. under an edited heading or after a # line inside it. If they're left over, delete them."
  fi
fi

# Other CLAUDE.md files with the section: Claude Code loads all of them
for other in "$HOME/.claude/CLAUDE.md" "$PWD/CLAUDE.md" "$PWD/.claude/CLAUDE.md"; do
  [ -f "$other" ] || continue
  if [ "$other" -ef "$CLAUDE_MD" ] || [ "$other" -ef "$SECTION" ]; then continue; fi
  md_plan "$other" || continue
  if [ -n "$PLAN_INSTALLED" ]; then
    if [ "$other" -ef "$HOME/.claude/CLAUDE.md" ]; then hint="install.sh without --project"; else hint="install.sh --project from that folder"; fi
    say warning "$other also has the \"Claude Code subagents\" section, and Claude Code loads both. Remove one, or run $hint to update it."
  elif [ -n "$PLAN_OTHERS" ]; then
    say warning "$other has a \"Claude Code subagents\" heading too, with none of this package's lines under it, and Claude Code loads that file as well. If it's an old copy, delete it."
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
