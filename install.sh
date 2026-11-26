#!/usr/bin/env bash
# Install the conf agents, skills and CLAUDE.md section.
#
# Usage: install.sh [--target claude|opencode] [--project] [--dry-run]
#   (default)  install to ~/.claude for all projects; the section goes in ~/.claude/CLAUDE.md
#   --target   claude (default) or opencode. opencode installs to ~/.config/opencode (agents converted to
#              OpenCode's format, skills as they are) and puts the section in ~/.config/opencode/AGENTS.md;
#              with --project, to ./.opencode/ and ./AGENTS.md. Models can be changed with the
#              CONF_MODEL_HAIKU, CONF_MODEL_SONNET and CONF_MODEL_OPUS environment variables
#   --project  install to .claude/ in the current folder, so run it from your project's folder.
#              The section goes in ./CLAUDE.md, or ./.claude/CLAUDE.md if the project keeps it there
#   --dry-run  show what would change, including a diff of CLAUDE.md, without touching anything
#
# Agents and skills that differ from the package's are overwritten, and CLAUDE.md is updated in
# place, all with no backup.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
PROJECT=0
DRY_RUN=0
TARGET=claude

HEADING='## Claude Code subagents'
# The last line of the section. Claude Code drops HTML comments from CLAUDE.md, so it costs nothing,
# and it shows where the section ends.
END_MARK='<!-- conf: end of section -->'
SECTION="$SRC/CLAUDE.md"

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

# OpenCode model names for the agents' haiku, sonnet and opus
MODEL_HAIKU="${CONF_MODEL_HAIKU:-anthropic/claude-haiku-5-5}"
MODEL_SONNET="${CONF_MODEL_SONNET:-anthropic/claude-sonnet-5-5}"
MODEL_OPUS="${CONF_MODEL_OPUS:-anthropic/claude-opus-5-5}"

# The awk program of convert_agent (see below). Its text must stay as is: quoting changes alter the output.
CONVERT_AWK='
    function die(m) { printf "error: %s: %s\n", file, m > "/dev/stderr"; failed = 1; exit 1 }
    function esc(s,   o, i, ch) {
      for (i = 1; i <= length(s); i++) { ch = substr(s, i, 1); o = o (ch == "\\" || ch == "\"" ? "\\" : "") ch }
      return o
    }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function has(list, word,   n, a, i) {
      n = split(list, a, /[ \t]*,[ \t]*/)
      for (i = 1; i <= n; i++) if (a[i] == word) return 1
      return 0
    }
    BEGIN { sq = "\047"; split("name description tools model effort skills color", k, " "); for (i in k) known[k[i]] = 1 }
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") die("no frontmatter"); infm = 1; next }
    infm && $0 == "---" { infm = 0; done = 1; next }
    infm {
      if ($0 ~ /^[A-Za-z][A-Za-z0-9_-]*:/) {
        cur = $0; sub(/:.*/, "", cur)
        if (!(cur in known)) die("unknown frontmatter key \"" cur "\"")
        v = $0; sub(/^[^:]*:/, "", v); val[cur] = trim(v)
      } else if ($0 ~ /^[ \t]+[^ \t]/ && cur != "") {
        v = trim($0); if (cur == "skills") { sub(/^-[ \t]*/, "", v); val[cur] = val[cur] (val[cur] == "" ? "" : ",") v } else val[cur] = val[cur] " " v
      } else if ($0 !~ /^[ \t]*$/) die("cannot read frontmatter line: " $0)
      next
    }
    done { body[++nb] = $0 }
    END {
      if (failed) exit 1
      if (!done) die("frontmatter is not closed")
      if (val["description"] == "") die("no description")
      d = val["description"]
      if (d ~ /^[>|\[{"]/) die("unsupported description form")
      if (substr(d, 1, 1) == sq) {
        if (length(d) < 2 || substr(d, length(d), 1) != sq) die("unsupported description form")
        d = substr(d, 2, length(d) - 2); gsub(sq sq, sq, d)
      }
      if (d == "") die("empty description")
      m = val["model"]
      if (m == "") die("missing model")
      if (m == "haiku") m = haiku; else if (m == "sonnet") m = sonnet; else if (m == "opus") m = opus
      else die("unknown model \"" m "\" (use haiku, sonnet or opus)")
      c = val["color"]
      if (c == "") die("missing color")
      if (c == "cyan") c = "#00bcd4"; else if (c == "orange") c = "#ff9800"; else if (c == "green") c = "#4caf50"
      else die("unknown color \"" c "\"")
      d = esc(d)
      effect = (has(val["tools"], "Edit") || has(val["tools"], "Write")) ? "allow" : "deny"
      print "---"
      print "description: \"" d "\""
      print "mode: subagent"
      print "model: " m
      print "permissions:"
      split("write edit", acts, " ")
      for (i = 1; i <= 2; i++) { print "  - action: " acts[i]; print "    resource: \"*\""; print "    effect: " effect }
      print "color: \"" c "\""
      print "---"
      for (i = 1; i <= nb; i++) print body[i]
      ns = split(val["skills"], sk, /[ \t]*,[ \t]*/)
      for (i = 1; i <= ns; i++) {
        if (sk[i] == "") continue
        print ""
        if (sk[i] == "tdd") print "Before writing code, load the `tdd` skill and follow it."
        else print "Load the `" sk[i] "` skill and follow it."
      }
    }
'

# convert_agent <source> <output>: write a Claude Code agent file in OpenCode's format. The body is
# kept; the frontmatter becomes description, mode: subagent, the mapped model, permissions made from
# tools (write and edit allowed only when tools lists Edit or Write), and a hex color. name is dropped
# (OpenCode uses the file name), and so are effort (OpenCode's variants for each model can't be
# checked offline) and skills (a line in the body tells the agent to load them instead). An unknown
# frontmatter key, model or color is an error, so a half-converted file is never written.
convert_agent() {
  LC_ALL=C awk -v haiku="$MODEL_HAIKU" -v sonnet="$MODEL_SONNET" -v opus="$MODEL_OPUS" -v file="$1" "$CONVERT_AWK" "$1" > "$2"
}

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
      replaced) verb="would replace" ;;
      updated) verb="would update" ;;
      appended) verb="would append" ;;
      created) verb="would create" ;;
    esac
  fi
  printf '%-14s %s\n' "$verb" "$*"
}

# Remove an installed file or folder under DEST before a fresh copy goes in, so a skill folder
# keeps no stale files and a symlink is replaced rather than written through. Sets `copied` to
# replaced, or installed if there was nothing there.
clear_target() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    # A folder copied from a read-only checkout is read-only too; never chmod through a symlink
    if [ -d "$1" ] && [ ! -L "$1" ]; then run chmod -R u+w "$1"; fi
    run rm -rf -- "$1"
    copied=replaced
  else
    copied=installed
  fi
}

# Show a diff of CLAUDE.md, indented and without diff's file-name header.
show_diff() {
  diff -u "$1" "$2" | sed '1,2d; s/^/    /' || true
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) PROJECT=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --target)
        if [ $# -lt 2 ]; then echo "--target needs a value (use claude or opencode)" >&2; exit 1; fi
        TARGET="$2"; shift ;;
      --target=*) TARGET="${1#--target=}" ;;
      -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
      *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
    shift
  done
  case "$TARGET" in
    claude|opencode) ;;
    *) echo "Unknown target: $TARGET (use claude or opencode)" >&2; exit 1 ;;
  esac
}

prepare_section() {
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
}

resolve_paths() {
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
    if [ "$TARGET" = opencode ]; then DEST="$PWD/.opencode"; else DEST="$PWD/.claude"; fi
    # Use whichever project CLAUDE.md already has the section, else whichever exists, else ./CLAUDE.md
    CLAUDE_MD="$PWD/CLAUDE.md"
    if [ "$TARGET" = opencode ]; then
      CLAUDE_MD="$PWD/AGENTS.md"
    elif has_section "$DEST/CLAUDE.md" && ! has_section "$CLAUDE_MD"; then
      CLAUDE_MD="$DEST/CLAUDE.md"
    elif has_heading "$DEST/CLAUDE.md" && ! has_heading "$CLAUDE_MD"; then
      CLAUDE_MD="$DEST/CLAUDE.md"
    elif [ ! -f "$CLAUDE_MD" ] && [ -f "$DEST/CLAUDE.md" ]; then
      CLAUDE_MD="$DEST/CLAUDE.md"
    fi
  elif [ "$TARGET" = opencode ]; then
    DEST="$HOME/.config/opencode"
    CLAUDE_MD="$DEST/AGENTS.md"
  else
    DEST="$HOME/.claude"
    CLAUDE_MD="$DEST/CLAUDE.md"
  fi
  AGENTS_DEST="$DEST/agents"
  SKILLS_DEST="$DEST/skills"
}

print_header() {
  if [ "$DRY_RUN" = 1 ]; then echo "Dry run: nothing will change."; fi
  if [ "$TARGET" = opencode ]; then
    echo "Target: opencode"
    echo "Agents and skills: $DEST"
    echo "AGENTS.md section: $CLAUDE_MD"
  else
    echo "Agents and skills: $DEST"
    echo "CLAUDE.md section: $CLAUDE_MD"
  fi
  echo
}

# CLAUDE.md: work out the new file first, so a problem with it stops the whole install before
# anything changes, rather than leaving new agents next to old routing. The first installed copy
# of the section (see SCAN), heading through end comment, is replaced with the package's section,
# and every other line is kept as it is. If there's no installed copy, the section is appended.
plan_rules_file() {
  local nonl eol
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
}

# Agents
# For opencode, convert every agent first, so an agent that can't be converted stops the install
# before anything is written.
install_agents() {
  local f rel target
  if [ "$TARGET" = opencode ]; then
    converted="$(mktemp -d "$tmpdir/conf.XXXXXX")"
    trap 'rm -rf "$tmp" "$section" "$converted"' EXIT
    for f in "$SRC"/agents/*.md; do
      if ! convert_agent "$f" "$converted/$(basename "$f")"; then echo "Couldn't convert $f. Nothing was changed." >&2; exit 1; fi
    done
  fi
  for f in "$SRC"/agents/*.md; do
    rel="agents/$(basename "$f")"
    target="$AGENTS_DEST/$(basename "$f")"
    if [ "$TARGET" = opencode ]; then f="$converted/$(basename "$f")"; fi
    if [ -f "$target" ] && cmp -s "$f" "$target"; then say unchanged "$rel"; continue; fi
    clear_target "$target"
    run mkdir -p "$AGENTS_DEST"
    run cp "$f" "$target"
    say "$copied" "$rel"
  done
}

# Skills
install_skills() {
  local d rel target
  for d in "$SRC"/skills/*/; do
    rel="skills/$(basename "$d")"
    target="$SKILLS_DEST/$(basename "$d")"
    if [ -d "$target" ] && diff -rq "$d" "$target" >/dev/null 2>&1; then say unchanged "$rel"; continue; fi
    clear_target "$target"
    run mkdir -p "$SKILLS_DEST"
    run cp -R "${d%/}" "$target"
    say "$copied" "$rel"
  done
}

# CLAUDE.md, as worked out above
apply_rules_file() {
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
}

# What the new CLAUDE.md still holds besides the section (line numbers are in the new file)
warn_section_leftovers() {
  local n
  if md_plan "$tmp"; then
    for n in $PLAN_LATER; do
      say warning "$CLAUDE_MD line $n has another copy of the \"Claude Code subagents\" section, and only the first one is updated. Delete it."
    done
    for n in $PLAN_OTHERS; do
      say warning "$CLAUDE_MD line $n has a \"Claude Code subagents\" heading with no end-of-section comment after it (an older copy, or something of yours), so it's left alone. If it's an old copy, delete it; if it's yours, rename the heading to stop this warning."
    done
  fi
}

# True if $PWD or a parent folder of it has an AGENTS.md (OpenCode looks for the project's from the working folder up).
project_agents_exists() {
  local dir="$PWD" parent
  while :; do
    if [ -f "$dir/AGENTS.md" ]; then return 0; fi
    parent="$(dirname "$dir")"
    if [ "$parent" = "$dir" ]; then return 1; fi
    dir="$parent"
  done
}

# Other CLAUDE.md files with the section: Claude Code loads all of them. OpenCode reads CLAUDE.md
# only when there is no AGENTS.md in the same scope (global or project), so for opencode a file is
# skipped when its scope's AGENTS.md exists (the project's may be in a parent folder), counting the one this run writes.
warn_other_rules_files() {
  local other hint who
  for other in "$HOME/.claude/CLAUDE.md" "$PWD/CLAUDE.md" "$PWD/.claude/CLAUDE.md"; do
    [ -f "$other" ] || continue
    if [ "$TARGET" = opencode ]; then
      # OpenCode's CLAUDE.md fallback reads ~/.claude/CLAUDE.md and the project's ./CLAUDE.md only
      if [ "$other" = "$PWD/.claude/CLAUDE.md" ]; then continue; fi
      if [ "$other" = "$HOME/.claude/CLAUDE.md" ]; then
        if [ -f "$HOME/.config/opencode/AGENTS.md" ] || [ "$HOME/.config/opencode/AGENTS.md" = "$CLAUDE_MD" ]; then continue; fi
      elif project_agents_exists || [ "$PWD/AGENTS.md" = "$CLAUDE_MD" ]; then
        continue
      fi
    fi
    if [ "$other" -ef "$CLAUDE_MD" ] || [ "$other" -ef "$SECTION" ]; then continue; fi
    md_plan "$other" || continue
    if [ -n "$PLAN_FIRST" ]; then
      if [ "$TARGET" = opencode ]; then
        say warning "$other also has the \"Claude Code subagents\" section, and OpenCode loads both because that scope has no AGENTS.md. Remove the section from that file, or install the OpenCode rules for that scope too (the section then also appears in the other scope's AGENTS.md)."
      else
        if [ "$other" -ef "$HOME/.claude/CLAUDE.md" ]; then hint="install.sh without --project"; else hint="install.sh --project from that folder"; fi
        say warning "$other also has the \"Claude Code subagents\" section, and Claude Code loads both. Remove one, or run $hint to update it."
      fi
    elif [ -n "$PLAN_OTHERS" ]; then
      if [ "$TARGET" = opencode ]; then who=OpenCode; else who="Claude Code"; fi
      say warning "$other has a \"Claude Code subagents\" heading too, with no end-of-section comment after it, and $who loads that file as well. If it's an old copy, delete it."
    fi
  done
}

# superpowers overlaps with these skills
warn_superpowers() {
  local settings
  for settings in "$HOME/.claude/settings.json" "$DEST/settings.json" "$DEST/settings.local.json"; do
    [ "$TARGET" = opencode ] && break
    if grep -Eqs '"superpowers@[^"]*"[[:space:]]*:[[:space:]]*true' "$settings"; then
      say warning "superpowers is enabled in $settings. Uninstall it with /plugin in Claude Code; its brainstorming and debugging skills overlap with scope and inspect."
      break
    fi
  done
}

print_footer() {
  echo
  if [ "$DRY_RUN" = 1 ]; then
    echo "Dry run finished. Run again without --dry-run to apply."
  else
    if [ "$TARGET" = opencode ]; then echo "Done. Start a new OpenCode session to load the changes."; else echo "Done. Start a new Claude Code session to load the changes."; fi
  fi
}

main() {
  parse_args "$@"
  prepare_section
  resolve_paths
  print_header
  plan_rules_file
  install_agents
  install_skills
  apply_rules_file
  warn_section_leftovers
  warn_other_rules_files
  warn_superpowers
  print_footer
}

main "$@"
