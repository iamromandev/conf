#!/usr/bin/env bash
# Regression tests for install.sh.
#
# Usage: bash tests/regress.sh [package folder]
#   The package folder defaults to the one this script is in. Each run works in a new temp folder,
#   with its own HOME and TMPDIR, so your real ~/.claude is never touched. The folder is deleted when
#   every check passes, and kept for a look when one fails (or always, with KEEP=1).
set -u
here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PKG_SRC="$(CDPATH='' cd -- "${1:-$here/..}" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/conf-test.XXXXXX")"
mkdir -p "$T/tmp"
cp -R "$PKG_SRC" "$T/pkg"
PKG="$T/pkg"
SEC="$(cat "$PKG/CLAUDE.md")"                  # the section as installed now
NOEND_F="$T/noend-section.md"                   # the section without its end comment, as left when the comment
sed '$d' "$PKG/CLAUDE.md" > "$NOEND_F"          # is deleted or the section is pasted without its last line
NOEND="$(cat "$NOEND_F")"
NOEND_BODY="$(sed 1d "$NOEND_F")"               # everything under its heading
MARK='<!-- conf: end of section -->'
PASS=0 FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }
# inst <home> [pkg] [args...]: run the installer with a sandboxed HOME; prints its output
inst() { local h="$1" p="${2:-$PKG}"; shift; [ $# -gt 0 ] && shift; env HOME="$h" TMPDIR="$T/tmp" bash "$p/install.sh" "$@" 2>&1; }
newhome() { local h="$T/$1"; rm -rf "$h"; mkdir -p "$h/.claude"; printf '%s' "$h"; }
heads() { grep -c '^## Claude Code subagents' "$1" | tr -d ' '; }
sum() { cksum < "$1"; }
treesum() { (cd "$1" && find . -type f | LC_ALL=C sort | while read -r f; do cksum "$f"; done; find . | LC_ALL=C sort) | cksum; }
# same <case> <file> <expected text>: the file must be exactly the expected text plus a final newline
same() {
  printf '%s\n' "$3" > "$T/expected"
  if cmp -s "$T/expected" "$2"; then ok "$1"; else bad "$1" "content differs"; diff "$T/expected" "$2" | head -20 | sed 's/^/      /'; fi
}
# idem <case> <home>: a second run leaves CLAUDE.md byte-identical and reports it unchanged
idem() { local f="$2/.claude/CLAUDE.md" a out; a=$(sum "$f"); out=$(inst "$2"); if [ "$a" = "$(sum "$f")" ] && printf '%s' "$out" | grep -q "unchanged .*CLAUDE.md"; then ok "$1 (idempotent)"; else bad "$1 (idempotent)" "second run changed CLAUDE.md"; fi; }
# refused <case> <home> <expected words> [pkg] [args]: the run exits 1, says nothing changed, and leaves HOME as it was
refused() {
  local a out rc; a=$(treesum "$2"); out=$(inst "$2" "${4:-}" ${5:-}); rc=$?
  if [ $rc = 1 ] && [ "$a" = "$(treesum "$2")" ] && printf '%s' "$out" | grep -q "$3" && printf '%s' "$out" | grep -q 'Nothing was changed'; then ok "$1"
  else bad "$1" "rc=$rc, changed=$([ "$a" = "$(treesum "$2")" ] && echo no || echo yes), output: $(printf '%s' "$out" | grep -m1 -i 'error\|warning')"; fi
}
# put <home> <printf format> [args...]: write CLAUDE.md in that HOME
put() { local h="$1" fmt="$2"; shift 2; printf "$fmt" "$@" > "$h/.claude/CLAUDE.md"; }

echo "== Installing and re-running"
H=$(newhome b1); rmdir "$H/.claude"; inst "$H" >/dev/null
[ "$(ls "$H/.claude/agents" | wc -l | tr -d ' ')" = 5 ] && [ "$(ls "$H/.claude/skills" | wc -l | tr -d ' ')" = 4 ] && ok "B1 fresh install copies 5 agents, 4 skills" || bad B1 "missing files"
same "B1 fresh CLAUDE.md is the section" "$H/.claude/CLAUDE.md" "$SEC"
out=$(inst "$H"); [ "$(printf '%s\n' "$out" | grep -c '^unchanged')" = 10 ] && ok "B1 rerun reports 10 unchanged" || bad B1 "rerun: $(printf '%s' "$out" | head -3)"
H=$(newhome b2); put "$H" '# Mine\n\n%s\n' "$NOEND"
mkdir -p "$H/.claude/agents"; printf 'my edit\n' > "$H/.claude/agents/builder.md"
a=$(treesum "$H"); out=$(inst "$H" "" --dry-run); [ "$a" = "$(treesum "$H")" ] && ok "B2 --dry-run changes nothing" || bad B2 "tree changed"
printf '%s\n' "$out" | grep -q '^would back up  *agents/builder.md$' && ok "B2 --dry-run says it would back up a changed agent" || bad B2 "no 'would back up' line: $(printf '%s' "$out" | grep -m1 builder)"
H=$(newhome b6); out=$(cd "$H" && inst "$H" "" --project); rc=$?; [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "home folder" && ok "B6 --project refused in HOME (exit $rc)" || bad B6 "not refused in HOME (exit $rc)"
out=$(cd "$PKG" && inst "$H" "" --project); rc=$?; [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "that's the conf package itself" && ok "B6 --project refused in package (exit $rc)" || bad B6 "not refused in package (exit $rc)"
H=$(newhome b7); put "$H" 'abc'; inst "$H" >/dev/null
same "B7 append after a file with no final newline" "$H/.claude/CLAUDE.md" "$(printf 'abc\n\n%s' "$SEC")"; idem B7 "$H"
H=$(newhome b8); mkdir -p "$H/.claude/agents" "$H/.claude/skills/check"; printf 'my edit\n' > "$H/.claude/agents/builder.md"; printf 'my skill edit\n' > "$H/.claude/skills/check/SKILL.md"; out=$(inst "$H")
cmp -s "$PKG/agents/builder.md" "$H/.claude/agents/builder.md" && [ "$(cat "$H"/.claude/conf-backup-*/agents/builder.md)" = 'my edit' ] && printf '%s' "$out" | grep -q '^backed up      agents/builder.md$' && printf '%s' "$out" | grep -q '^Backups are in ' && ok "B8 a changed agent is replaced, the old copy moved to the conf-backup folder" || bad B8 "not backed up: $(printf '%s' "$out" | grep -m1 builder)"
[ "$(cat "$H"/.claude/conf-backup-*/skills/check/SKILL.md)" = 'my skill edit' ] && diff -rq "$PKG/skills/check" "$H/.claude/skills/check" >/dev/null && printf '%s' "$out" | grep -q '^backed up      skills/check$' && ok "B8 a changed skill folder is replaced, the old copy moved to the conf-backup folder" || bad B8 "skill not backed up: $(printf '%s' "$out" | grep -m1 skills/check)"
H=$(newhome b9); put "$H" '# Mine\n\nstuff\n'; inst "$H" >/dev/null
same "B9 section appended to a file without one" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\nstuff\n\n%s' "$SEC")"; idem B9 "$H"

echo "== Updating a section without its end comment (deleted, or pasted without it)"
H=$(newhome u1); put "$H" '# Mine\n\n%s\n- My own rule.\n@docs/team.md\n' "$NOEND"; inst "$H" >/dev/null
same "U1 lines appended after the old section are kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s\n- My own rule.\n@docs/team.md' "$SEC")"; idem U1 "$H"
H=$(newhome u2); put "$H" '# Mine\n\nstuff\n\n%s\n\n## Other\n\nkeep\n' "$NOEND"; inst "$H" >/dev/null
same "U2 section in the middle: replaced, the rest kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\nstuff\n\n%s\n\n## Other\n\nkeep' "$SEC")"; idem U2 "$H"
H=$(newhome u3); { sed -n 1,5p "$NOEND_F"; echo '- Use pnpm, never npm.'; sed -n '6,$p' "$NOEND_F"; } > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "U3 a line of yours between the old bullets is kept, after the section" "$H/.claude/CLAUDE.md" "$(printf '%s\n- Use pnpm, never npm.' "$SEC")"; idem U3 "$H"
H=$(newhome u4); sed '4s/$/ (my edit)/' "$NOEND_F" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "U4 an edited bullet is kept, the others replaced" "$H/.claude/CLAUDE.md" "$(printf '%s\n%s (my edit)' "$SEC" "$(sed -n 4p "$NOEND_F")")"; idem U4 "$H"
H=$(newhome u5); put "$H" '%s\n\nbetween\n\n%s\n\n## End\n' "$NOEND" "$NOEND"; inst "$H" >/dev/null
same "U5 two copies are merged, what's between them kept" "$H/.claude/CLAUDE.md" "$(printf '%s\n\nbetween\n\n## End' "$SEC")"; idem U5 "$H"
H=$(newhome u6); awk '{ printf "%s\r\n", $0 }' "$NOEND_F" > "$H/.claude/CLAUDE.md"; printf -- '- mine\r\n' >> "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(wc -l < "$f" | tr -d ' ')" = "$(grep -c $'\r$' "$f")" ] && [ "$(grep -c $'\r\r' "$f")" = 0 ] && [ "$(heads "$f")" = 1 ] && grep -q $'^- mine\r$' "$f" && ok "U6 CRLF file stays CRLF, your line kept" || bad U6 "heads=$(heads "$f")"; idem U6 "$H"
H=$(newhome u6b); { awk '{ printf "%s\r\r\n", $0 }' "$NOEND_F"; awk '{ printf "%s\r\r\n", $0 }' "$NOEND_F"; printf '\r\n## Other\r\n'; } > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(heads "$f")" = 1 ] && [ "$(grep -c $'\r\r' "$f")" = 0 ] && grep -q '^## Other' "$f" && ok "U6b copies with \\r\\r line endings from older versions are repaired and merged" || bad U6b "heads=$(heads "$f") dbl=$(grep -c $'\r\r' "$f")"; idem U6b "$H"
H=$(newhome u7); put "$H" '\357\273\277%s\n\n## Other\n' "$NOEND"; inst "$H" >/dev/null
same "U7 BOM before the heading is kept" "$H/.claude/CLAUDE.md" "$(printf '\357\273\277%s\n\n## Other' "$SEC")"; idem U7 "$H"
for t in '-----\nmy note' 'Notes\n=====\nmore' '```bash\nmake\n```' '* * *\nx' '<!-- note -->\ny' '  ## Indented\nz' '> quote\n| a | b |'; do
  H=$(newhome "u8$(printf '%s' "$t" | cksum | cut -d' ' -f1)"); put "$H" "%s\n$t\n" "$NOEND"; inst "$H" >/dev/null
  same "U8 kept right after the old section: '$t'" "$H/.claude/CLAUDE.md" "$(printf "%s\n$t" "$SEC")"
done
for hv in '## Claude Code subagents  ' '## Claude Code subagents ##' '##\tClaude  Code subagents'; do
  H=$(newhome "u9$(printf '%s' "$hv" | cksum | cut -d' ' -f1)"); put "$H" "$hv\n%s\n" "$NOEND_BODY"; inst "$H" >/dev/null
  same "U9 heading written as '$hv' is recognized" "$H/.claude/CLAUDE.md" "$SEC"
done
H=$(newhome u11); put "$H" '# Mine\n\n%s\n- Use pnpm.\n@docs/x.md\n' "$SEC"; inst "$H" >/dev/null
same "U11 a current section: lines after the end comment are kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s\n- Use pnpm.\n@docs/x.md' "$SEC")"; idem U11 "$H"
H=$(newhome u12); rmdir "$H/.claude"; inst "$H" >/dev/null; printf -- '- Added later by Claude.\n' >> "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "U12 a line appended after a fresh install survives the next run" "$H/.claude/CLAUDE.md" "$(printf '%s\n- Added later by Claude.' "$SEC")"
H=$(newhome u13); put "$H" '%s\n\n## Notes\n%s\n' "$NOEND" "$(sed -n 3p "$NOEND_F")"; inst "$H" >/dev/null
same "U13 a copy of a section line under another heading isn't touched" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n## Notes\n%s' "$SEC" "$(sed -n 3p "$NOEND_F")")"
H=$(newhome u14); put "$H" '%s\n\n### My notes\n- mine\n%s\n' "$NOEND" "$(sed -n 3p "$NOEND_F")"; inst "$H" >/dev/null
same "U14 a ### subsection inside the old section is kept, its package lines still replaced" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n### My notes\n- mine' "$SEC")"; idem U14 "$H"
BLOCK='```bash\n# fast checks\nmake check\n```'
H=$(newhome u15); { sed -n 1,6p "$NOEND_F"; printf "$BLOCK\n"; sed -n '7,$p' "$NOEND_F"; } > "$H/.claude/CLAUDE.md"; out=$(inst "$H")
printf '%s' "$out" | grep -q 'line 19 and 6 more repeat' && ok "U15 a # line in a code block ends a section without the end comment, and the leftover lines get a warning" || bad U15 "no warning about line 19: $(printf '%s' "$out" | grep -m1 repeat)"
H=$(newhome u15b); { sed -n 1,6p "$PKG/CLAUDE.md"; printf "$BLOCK\n"; sed -n '7,$p' "$PKG/CLAUDE.md"; } > "$H/.claude/CLAUDE.md"; out=$(inst "$H")
same "U15b with the end comment, the section runs to it: code block kept, no leftovers" "$H/.claude/CLAUDE.md" "$(printf "%s\n$BLOCK" "$SEC")"
printf '%s' "$out" | grep -q 'repeat' && bad U15b "unexpected leftover warning" || ok "U15b no leftover warning"
H=$(newhome u16); put "$H" '%s\n## Other\nkeep\n\n%s\n- extra\n' "$SEC" "$NOEND"; inst "$H" >/dev/null
same "U16 a later copy after another heading is merged, its own line kept in place" "$H/.claude/CLAUDE.md" "$(printf '%s\n## Other\nkeep\n\n- extra' "$SEC")"; idem U16 "$H"
H=$(newhome u17); sed 's/^- .*/&  /' "$NOEND_F" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "U17 package lines with trailing spaces are still recognized" "$H/.claude/CLAUDE.md" "$SEC"
H=$(newhome u16b); put "$H" '%s\n## Other\nkeep\n\n%s\n- extra\n' "$SEC" "$SEC"; inst "$H" >/dev/null
same "U16b a second current copy is merged, a line after its end comment kept" "$H/.claude/CLAUDE.md" "$(printf '%s\n## Other\nkeep\n\n- extra' "$SEC")"; idem U16b "$H"
# (runs from $T where there's no CLAUDE.md, so the "also has" warning for the repo's own doesn't show)
H=$(newhome u18); put "$H" '%s\n' "$NOEND"; a=$(treesum "$H"); out=$(cd "$T" && inst "$H" "" --dry-run); chg=$(printf '%s\n' "$out" | grep '^    [-+]')
[ "$chg" = "    +$MARK" ] && ! printf '%s' "$out" | grep -q warning && [ "$a" = "$(treesum "$H")" ] && ok "U18 dry run on a section without its end comment: the diff only adds it, no warning, nothing written" || bad U18 "changes: $chg"

echo "== Code blocks don't change where the section is"
H=$(newhome k1); put "$H" '# Notes\n```md\n```bash\nx\n```\n```\n\n%s\n' "$SEC"; inst "$H" >/dev/null
same "K1 naively nested example before the section" "$H/.claude/CLAUDE.md" "$(printf '# Notes\n```md\n```bash\nx\n```\n```\n\n%s' "$SEC")"; idem K1 "$H"
H=$(newhome k2); put "$H" '# Mine\n\n```bash\nx\n\n%s\n' "$SEC"; inst "$H" >/dev/null
same "K2 a code block that's never closed before the section" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```bash\nx\n\n%s' "$SEC")"; idem K2 "$H"
H=$(newhome k3); put "$H" '%s\n```bash\n# build it\nmake\n' "$NOEND"; inst "$H" >/dev/null
same "K3 a code block that's never closed after the section is kept" "$H/.claude/CLAUDE.md" "$(printf '%s\n```bash\n# build it\nmake' "$SEC")"; idem K3 "$H"
H=$(newhome k4); put "$H" '# Mine\n\n```text\nStart blocks like:\n```python\n```\n\n%s\n' "$SEC"; inst "$H" >/dev/null
same "K4 a fence shown as text inside a block" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```text\nStart blocks like:\n```python\n```\n\n%s' "$SEC")"
H=$(newhome k5); put "$H" '# Mine\n```bash\nnpm test\n```bash\n\n%s\n## Build\n```\nmake\n```\n' "$NOEND"; inst "$H" >/dev/null
same "K5 a closing fence typed as \`\`\`bash before the section" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n```bash\nnpm test\n```bash\n\n%s\n## Build\n```\nmake\n```' "$SEC")"

echo "== Headings that aren't this package's section"
H=$(newhome w1); put "$H" '# Mine\n\n```md\n## Claude Code subagents\n- my team rule\n```\n'; out=$(inst "$H")
same "W1 an example with the heading: section appended, example untouched" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```md\n## Claude Code subagents\n- my team rule\n```\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'line 4 .*left alone' && ok "W1 warns about line 4" || bad W1 "no warning naming line 4"
out=$(inst "$H"); printf '%s' "$out" | grep -q 'unchanged .*CLAUDE.md' && printf '%s' "$out" | grep -q 'line 4 .*left alone' && ok "W1 rerun: unchanged, still warns" || bad W1 "rerun"
H=$(newhome w2); put "$H" '# Mine\n\n```md\n## Claude Code subagents\n- my team rule\n```\n\n%s\n' "$SEC"; out=$(inst "$H")
same "W2 real section replaced, the example left alone" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```md\n## Claude Code subagents\n- my team rule\n```\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'line 4 .*left alone' && ok "W2 warns about the example" || bad W2 "no warning"
H=$(newhome w3); put "$H" '## Claude Code subagents\n\n- old routing to Plan\n'; out=$(inst "$H")
same "W3 a section with none of this package's lines is kept, the section appended" "$H/.claude/CLAUDE.md" "$(printf '## Claude Code subagents\n\n- old routing to Plan\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'line 1 .*left alone' && ok "W3 warns about line 1" || bad W3 "no warning"
H=$(newhome w4); put "$H" '### Claude Code subagents\n- a\n## Claude Code subagents and more\n- b\n  ## Claude Code subagents\n- c\n'; out=$(inst "$H")
same "W4 ###, longer and indented headings aren't the section" "$H/.claude/CLAUDE.md" "$(printf '### Claude Code subagents\n- a\n## Claude Code subagents and more\n- b\n  ## Claude Code subagents\n- c\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'left alone' && bad W4 "unexpected warning" || ok "W4 no warning for them"
H=$(newhome w5); put "$H" '%s\n\n```md\n## Claude Code subagents\n- my team rule\n```\n' "$NOEND"; out=$(inst "$H"); f="$H/.claude/CLAUDE.md"
same "W5 an example after the real section is left alone" "$f" "$(printf '%s\n\n```md\n## Claude Code subagents\n- my team rule\n```' "$SEC")"; idem W5 "$H"
n=$(grep -n '^## Claude Code subagents$' "$f" | sed -n 2p | cut -d: -f1)
printf '%s' "$out" | grep -q "line $n .*left alone" && ok "W5 the warning names the example's line in the updated file ($n)" || bad W5 "warning doesn't name line $n: $(printf '%s' "$out" | grep -m1 'left alone')"
H=$(newhome w6); put "$H" '## Claude Code subagents\n- my own note\n%s\n' "$MARK"; out=$(inst "$H")
same "W6 a heading over only an end comment isn't an installed copy" "$H/.claude/CLAUDE.md" "$(printf '## Claude Code subagents\n- my own note\n%s\n\n%s' "$MARK" "$SEC")"; idem W6 "$H"
H=$(newhome w7); put "$H" '## Workflow\n\n### Claude Code subagents\n%s\n' "$NOEND_BODY"; out=$(inst "$H")
printf '%s' "$out" | grep -q 'line 5 and 10 more repeat' && ok "W7 package lines under an edited heading get a warning" || bad W7 "no warning: $(printf '%s' "$out" | grep -m1 'repeat\|warning')"
# A section heading with none of the package's lines right under it must not take the lines of an
# edited copy further down, even across a ### heading or up to that copy's end comment.
for c in \
  "W8|# Mine\n\n<!--\n## Claude Code subagents\n- Old routing I turned off.\n-->\n\n### Claude Code subagents\n\n%s\n|$(sed 1,2d "$NOEND_F")" \
  "W9|## Workflow\n\nTeam doc format:\n\`\`\`md\n## Claude Code subagents\n- your rules here\n\`\`\`\n\n### Claude Code subagents\n%s\n|$NOEND_BODY" \
  "W10|# Notes\n\`\`\`md\n## Claude Code subagents\n- my rule\n\`\`\`\n\n# Workflow\n### Claude Code subagents\n%s\n\n## After\ny\n|$(sed 1,2d "$PKG/CLAUDE.md")"; do
  name="${c%%|*}"; rest="${c#*|}"; fmt="${rest%%|*}"; arg="${rest#*|}"
  H=$(newhome "$name"); put "$H" "$fmt" "$arg"; before="$(cat "$H/.claude/CLAUDE.md")"; out=$(inst "$H")
  same "$name a commented-out or example heading above an edited copy: both left alone, section appended" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n%s' "$before" "$SEC")"
  printf '%s' "$out" | grep -q 'left alone' && printf '%s' "$out" | grep -q 'repeat' && ok "$name warns about both" || bad "$name" "missing warning"
done

echo "== The package's own CLAUDE.md"
PB="$T/pkgblank"; cp -R "$PKG" "$PB"; printf '\n\n' >> "$PB/CLAUDE.md"
H=$(newhome p2); rmdir "$H/.claude"; inst "$H" "$PB" >/dev/null; inst "$H" "$PB" >/dev/null
same "P2 trailing blank lines in the package section are ignored" "$H/.claude/CLAUDE.md" "$SEC"
PH="$T/pkghead"; cp -R "$PKG" "$PH"; awk 'NR == 3 { print "### Notes" } { print }' "$PKG/CLAUDE.md" > "$PH/CLAUDE.md"
H=$(newhome p3); put "$H" '# Mine\n'; refused "P3 a package section with another heading: refused before any change" "$H" "package's CLAUDE.md" "$PH"
PM="$T/pkgnomark"; cp -R "$PKG" "$PM"; sed '$d' "$PKG/CLAUDE.md" > "$PM/CLAUDE.md"
H=$(newhome p4); put "$H" '# Mine\n'; refused "P4 a package section without the end comment: refused" "$H" "package's CLAUDE.md" "$PM"
PE="$T/pkgmidmark"; cp -R "$PKG" "$PE"; awk -v m="$MARK" 'NR == 6 { print m } { print }' "$PKG/CLAUDE.md" > "$PE/CLAUDE.md"
H=$(newhome p6); put "$H" '# Mine\n'; refused "P6 a package section with an end comment in the middle: refused" "$H" "package's CLAUDE.md" "$PE"
# Rewording a line the way README describes: save the current section in old-sections/ first
PW="$T/pkgreword"; cp -R "$PKG" "$PW"; mkdir -p "$PW/old-sections"; cp "$PKG/CLAUDE.md" "$PW/old-sections/previous.md"
sed '5s/.*/- A reworded rule./' "$PKG/CLAUDE.md" > "$PW/CLAUDE.md"
H=$(newhome p5); put "$H" '%s\n- mine\n' "$SEC"; inst "$H" "$PW" >/dev/null
same "P5 a reworded line: the old wording is still recognized through old-sections/" "$H/.claude/CLAUDE.md" "$(printf '%s\n- mine' "$(cat "$PW/CLAUDE.md")")"
[ ! -d "$PKG/old-sections" ] && ok "P5 the package ships no old-sections/ folder until a line is reworded" || bad P5 "old-sections/ exists"

echo "== Windows line endings and byte order marks in the package"
CR="$T/pkgcr"; cp -R "$PKG" "$CR"; awk '{ printf "%s\r\n", $0 }' "$PKG/CLAUDE.md" > "$CR/CLAUDE.md"
H=$(newhome c1); put "$H" '# Mine\n\n%s\n' "$NOEND"; inst "$H" "$CR" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(grep -c $'\r' "$f")" = 0 ] && ok "C1 CRLF section into an LF file: no CRs" || bad C1 "$(grep -c $'\r' "$f") lines with CR"
a=$(sum "$f"); inst "$H" "$CR" >/dev/null; [ "$a" = "$(sum "$f")" ] && [ "$(heads "$f")" = 1 ] && ok "C1 (idempotent)" || bad "C1 (idempotent)" "heads=$(heads "$f")"
H=$(newhome c2); awk '{ printf "%s\r\n", $0 }' "$NOEND_F" > "$H/.claude/CLAUDE.md"; inst "$H" "$CR" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(grep -c $'\r\r' "$f")" = 0 ] && [ "$(wc -l < "$f" | tr -d ' ')" = "$(grep -c $'\r$' "$f")" ] && ok "C2 CRLF section into a CRLF file: single CRs" || bad C2 "double CRs: $(grep -c $'\r\r' "$f")"
a=$(sum "$f"); inst "$H" "$CR" >/dev/null; [ "$a" = "$(sum "$f")" ] && [ "$(heads "$f")" = 1 ] && ok "C2 (idempotent)" || bad "C2 (idempotent)" "heads=$(heads "$f")"
H=$(newhome c3); rmdir "$H/.claude"; inst "$H" "$CR" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(grep -c $'\r' "$f")" = 0 ] && ok "C3 CRLF section, new CLAUDE.md: no CRs" || bad C3 "$(grep -c $'\r' "$f") lines with CR"
H=$(newhome c4); printf '# Mine\r\n' > "$H/.claude/CLAUDE.md"; inst "$H" "$CR" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(grep -c $'\r\r' "$f")" = 0 ] && [ "$(wc -l < "$f" | tr -d ' ')" = "$(grep -c $'\r$' "$f")" ] && ok "C4 CRLF section appended to a CRLF file: single CRs" || bad C4 "double CRs: $(grep -c $'\r\r' "$f")"
[ -f "$PKG/.gitattributes" ] && grep -q 'eol=lf' "$PKG/.gitattributes" && ok "C5 .gitattributes forces LF" || bad C5 "no .gitattributes with eol=lf"
BM="$T/pkgbom"; cp -R "$PKG" "$BM"; { printf '\357\273\277'; cat "$PKG/CLAUDE.md"; } > "$BM/CLAUDE.md"
H=$(newhome c7); put "$H" '# Mine\n\n%s\n' "$NOEND"; inst "$H" "$BM" >/dev/null; inst "$H" "$BM" >/dev/null
same "C7 BOM in the package's CLAUDE.md isn't copied mid-file" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s' "$SEC")"
H=$(newhome c8); rmdir "$H/.claude"; inst "$H" "$BM" >/dev/null; inst "$H" "$BM" >/dev/null
same "C8 BOM in the package: new CLAUDE.md has none, rerun unchanged" "$H/.claude/CLAUDE.md" "$SEC"

echo "== Finding the section in --project mode"
P=$T/proj1; rm -rf "$P"; mkdir -p "$P/.claude"; H=$(newhome hs1)
printf '# Proj\n\n```md\n## Claude Code subagents\n- example\n```\n' > "$P/CLAUDE.md"; printf '%s\n' "$NOEND" > "$P/.claude/CLAUDE.md"; a=$(sum "$P/CLAUDE.md")
(cd "$P" && inst "$H" "" --project >/dev/null)
[ "$a" = "$(sum "$P/CLAUDE.md")" ] && same "S1 --project picks the file with the real section" "$P/.claude/CLAUDE.md" "$SEC" || bad S1 "./CLAUDE.md changed"
P=$T/proj2; rm -rf "$P"; mkdir -p "$P"; H=$(newhome hs2); printf '# Proj\n\n```md\n## Claude Code subagents\n- example\n```\n' > "$P/CLAUDE.md"
out=$(cd "$P" && inst "$H"); printf '%s' "$out" | grep -q 'also has' && bad S2 "false duplicate warning" || ok "S2 no duplicate warning for an example"
P=$T/proj3; rm -rf "$P"; mkdir -p "$P"; H=$(newhome hs3); printf '# Proj\n\n%s\n' "$SEC" > "$P/CLAUDE.md"
out=$(cd "$P" && inst "$H"); printf '%s' "$out" | grep -q 'proj3/CLAUDE.md also has' && ok "S3 duplicate warning for a real section elsewhere" || bad S3 "no warning"
P=$T/proj5; rm -rf "$P"; mkdir -p "$P"; H=$(newhome hs5); printf '# Proj\n\n## Claude Code subagents\n\n- Old routing to the Plan agent.\n' > "$P/CLAUDE.md"
out=$(cd "$P" && inst "$H"); printf '%s' "$out" | grep -q 'proj5/CLAUDE.md has a "Claude Code subagents" heading too' && ok "S5 warning for an edited copy in another CLAUDE.md" || bad S5 "no warning"
P=$T/proj6; rm -rf "$P"; mkdir -p "$P/.claude"; H=$(newhome hs6); printf '# Proj\n\n- Use pnpm.\n' > "$P/CLAUDE.md"; sed 's/^- /* /' "$NOEND_F" > "$P/.claude/CLAUDE.md"; a=$(sum "$P/CLAUDE.md")
(cd "$P" && inst "$H" "" --project >/dev/null)
[ "$a" = "$(sum "$P/CLAUDE.md")" ] && [ "$(heads "$P/.claude/CLAUDE.md")" = 2 ] && ok "S6 --project picks the file with an edited copy, not the one without" || bad S6 "picked ./CLAUDE.md"

echo "== Refusals stop the whole install"
if [ "$(id -u)" != 0 ]; then
  H=$(newhome x1); put "$H" '# Mine\n'; chmod a-w "$H/.claude/CLAUDE.md"
  refused "X1 a read-only CLAUDE.md that needs a change: refused before anything is installed" "$H" "can't write"; chmod u+w "$H/.claude/CLAUDE.md"
  H=$(newhome x3); rmdir "$H/.claude"; inst "$H" >/dev/null; rm "$H/.claude/agents/builder.md"; chmod a-w "$H/.claude/CLAUDE.md"; out=$(inst "$H"); rc=$?; chmod u+w "$H/.claude/CLAUDE.md"
  [ $rc = 0 ] && [ -f "$H/.claude/agents/builder.md" ] && printf '%s' "$out" | grep -q 'unchanged .*CLAUDE.md' && ok "X3 a read-only CLAUDE.md that's already current: install goes ahead" || bad X3 "rc=$rc $(printf '%s' "$out" | grep -m1 error)"
else
  echo "skip X1, X3 read-only CLAUDE.md (running as root)"
fi
H=$(newhome x2); out=$(inst "$H"); rc=$?; [ $rc = 0 ] && printf '%s' "$out" | grep -q '^Done' && ok "X2 a normal install exits 0 and says Done" || bad X2 "rc=$rc"

echo "== Temp folder, dry run, permissions"
H=$(newhome d1); rmdir "$H/.claude"; inst "$H" "" --dry-run >/dev/null; [ ! -e "$H/.claude" ] && ok "D1 --dry-run on a fresh HOME creates nothing" || bad D1 "created $(find "$H" | head -3)"
H=$(newhome p1); rmdir "$H/.claude"; (umask 022; inst "$H" >/dev/null); m=$(stat -c %a "$H/.claude/CLAUDE.md" 2>/dev/null || stat -f %Lp "$H/.claude/CLAUDE.md"); [ "$m" = 644 ] && ok "P1 new CLAUDE.md gets normal permissions (644)" || bad P1 "mode $m"
H=$(newhome t1); rmdir "$H/.claude"; out=$(env HOME="$H" TMPDIR="$T/no/such/dir" bash "$PKG/install.sh" 2>&1); rc=$?
[ $rc = 0 ] && [ -f "$H/.claude/CLAUDE.md" ] && ok "T1 unusable TMPDIR falls back to /tmp" || bad T1 "rc=$rc $(printf '%s' "$out" | tail -1)"

echo "== Agent, skill and README checks"
head -5 "$PKG/agents/builder.md" | grep -qx 'disallowedTools: Agent' && ok "Q1 builder denies the Agent tool" || bad Q1 "no disallowedTools: Agent"
sed -n 3p "$PKG/CLAUDE.md" | grep -q 'for the main conversation' && ok "Q2 CLAUDE.md starts with the subagent rule" || bad Q2 "rule missing"
grep -q 'git status --short' "$PKG/agents/reviewer.md" && ok "Q3 reviewer checks untracked files" || bad Q3 "no git status"
! grep -q 'wrap the whole description in double quotes' "$PKG/README.md" && grep -q "Don't wrap it in double quotes" "$PKG/README.md" && ok "Q4 README no longer suggests double quotes" || bad Q4 "old advice"
if command -v ruby >/dev/null; then
  broken=""
  for f in "$PKG"/agents/*.md "$PKG"/skills/*/SKILL.md; do
    ruby -ryaml -e 'y = YAML.safe_load(File.read(ARGV[0]).split(/^---\s*$/)[1]); exit(y["name"] && y["description"] ? 0 : 1)' "$f" 2>/dev/null || broken="$broken ${f#"$PKG"/}"
  done
  [ -z "$broken" ] && ok "Q5 all agent and skill frontmatter parses (checked with Ruby)" || bad Q5 "frontmatter doesn't parse:$broken"
else
  echo "skip Q5 frontmatter parse check (needs Ruby)"
fi

[ "$(tail -n 1 "$PKG/CLAUDE.md")" = "$MARK" ] && ok "Q6 CLAUDE.md ends with the end-of-section comment" || bad Q6 "wrong last line"
missing=""; for n in $(grep -o '`[a-z-]*`' "$PKG/CLAUDE.md" | tr -d '`' | sort -u); do [ -f "$PKG/agents/$n.md" ] || [ -d "$PKG/skills/$n" ] || missing="$missing $n"; done
[ -z "$missing" ] && ok "Q7 every agent and skill CLAUDE.md names is in the package" || bad Q7 "not in agents/ or skills/:$missing"

echo
echo "passed $PASS, failed $FAIL"
if [ "$FAIL" = 0 ] && [ -z "${KEEP:-}" ]; then rm -rf "$T"; else echo "Test files kept in $T"; fi
[ "$FAIL" = 0 ]
