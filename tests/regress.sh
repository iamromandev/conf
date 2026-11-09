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
MARK='<!-- conf: end of section -->'
SEC="$(cat "$PKG/CLAUDE.md")"                   # the section as installed now
OLD_BODY="$(printf -- '- An old rule.\n- Another old rule, since reworded.')"
OLD="$(printf '## Claude Code subagents\n\n%s\n%s' "$OLD_BODY" "$MARK")"   # an install of an earlier wording
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
[ "$(ls "$H/.claude/agents" | wc -l | tr -d ' ')" = 3 ] && [ "$(ls "$H/.claude/skills" | wc -l | tr -d ' ')" = 6 ] && ok "B1 fresh install copies 3 agents, 6 skills" || bad B1 "missing files"
same "B1 fresh CLAUDE.md is the section" "$H/.claude/CLAUDE.md" "$SEC"
out=$(inst "$H"); [ "$(printf '%s\n' "$out" | grep -c '^unchanged')" = 10 ] && ok "B1 rerun reports 10 unchanged" || bad B1 "rerun: $(printf '%s' "$out" | head -3)"
H=$(newhome b2); put "$H" '# Mine\n\n%s\n' "$OLD"
mkdir -p "$H/.claude/agents"; printf 'my edit\n' > "$H/.claude/agents/critic.md"
a=$(treesum "$H"); out=$(inst "$H" "" --dry-run); [ "$a" = "$(treesum "$H")" ] && ok "B2 --dry-run changes nothing" || bad B2 "tree changed"
printf '%s\n' "$out" | grep -q '^would replace  *agents/critic.md$' && ok "B2 --dry-run says it would replace a changed agent" || bad B2 "no 'would replace' line: $(printf '%s' "$out" | grep -m1 critic)"
H=$(newhome b6); out=$(cd "$H" && inst "$H" "" --project); rc=$?; [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "home folder" && ok "B6 --project refused in HOME (exit $rc)" || bad B6 "not refused in HOME (exit $rc)"
out=$(cd "$PKG" && inst "$H" "" --project); rc=$?; [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "that's the conf package itself" && ok "B6 --project refused in package (exit $rc)" || bad B6 "not refused in package (exit $rc)"
H=$(newhome b7); put "$H" 'abc'; inst "$H" >/dev/null
same "B7 append after a file with no final newline" "$H/.claude/CLAUDE.md" "$(printf 'abc\n\n%s' "$SEC")"; idem B7 "$H"
H=$(newhome b8); mkdir -p "$H/.claude/agents" "$H/.claude/skills/tdd"; printf 'my edit\n' > "$H/.claude/agents/critic.md"; printf 'my skill edit\n' > "$H/.claude/skills/tdd/SKILL.md"; printf 'mine\n' > "$H/.claude/skills/tdd/extra.md"
chmod a-w "$H/.claude/agents/critic.md"; out=$(inst "$H")
cmp -s "$PKG/agents/critic.md" "$H/.claude/agents/critic.md" && printf '%s' "$out" | grep -q '^replaced       agents/critic.md$' && ok "B8 a changed agent is replaced in place, even if it's read-only" || bad B8 "not replaced: $(printf '%s' "$out" | grep -m1 critic)"
diff -rq "$PKG/skills/tdd" "$H/.claude/skills/tdd" >/dev/null && printf '%s' "$out" | grep -q '^replaced       skills/tdd$' && ok "B8 a changed skill folder is replaced whole, extra files included" || bad B8 "skill not replaced: $(printf '%s' "$out" | grep -m1 skills/tdd)"
if ls -d "$H"/.claude/conf-backup-* >/dev/null 2>&1 || printf '%s' "$out" | grep -qi 'backup'; then bad B8 "a backup was made: $(ls "$H/.claude")"; else ok "B8 nothing is backed up"; fi
if [ "$(id -u)" != 0 ]; then
  H=$(newhome b10); mkdir -p "$H/.claude/skills/tdd"; printf 'my skill edit\n' > "$H/.claude/skills/tdd/SKILL.md"; chmod -R a-w "$H/.claude/skills/tdd"; out=$(inst "$H"); rc=$?; chmod -R u+w "$H/.claude/skills"
  [ $rc = 0 ] && diff -rq "$PKG/skills/tdd" "$H/.claude/skills/tdd" >/dev/null && ok "B10 a read-only skill folder is replaced too" || bad B10 "rc=$rc $(printf '%s' "$out" | grep -m1 -i 'rm:\|error')"
else
  echo "skip B10 read-only skill folder (running as root)"
fi
H=$(newhome b11); mkdir -p "$T/b11-mine" "$H/.claude/skills"; printf 'keep\n' > "$T/b11-mine/KEEP"; ln -s "$T/b11-mine" "$H/.claude/skills/tdd"; inst "$H" >/dev/null
[ ! -L "$H/.claude/skills/tdd" ] && diff -rq "$PKG/skills/tdd" "$H/.claude/skills/tdd" >/dev/null && [ "$(ls "$T/b11-mine")" = KEEP ] && ok "B11 a symlinked skill folder is replaced by a copy, the folder it pointed to untouched" || bad B11 "link=$([ -L "$H/.claude/skills/tdd" ] && echo yes || echo no) target=$(ls "$T/b11-mine" | tr '\n' ' ')"
H=$(newhome b12); mkdir -p "$H/.claude/agents"; printf 'mine\n' > "$T/b12-mine.md"; ln -s "$T/b12-mine.md" "$H/.claude/agents/critic.md"; inst "$H" >/dev/null
[ ! -L "$H/.claude/agents/critic.md" ] && cmp -s "$PKG/agents/critic.md" "$H/.claude/agents/critic.md" && [ "$(cat "$T/b12-mine.md")" = mine ] && ok "B12 a symlinked agent file is replaced by a copy, the file it pointed to untouched" || bad B12 "link=$([ -L "$H/.claude/agents/critic.md" ] && echo yes || echo no) target=$(cat "$T/b12-mine.md" | head -1)"
H=$(newhome b9); put "$H" '# Mine\n\nstuff\n'; inst "$H" >/dev/null
same "B9 section appended to a file without one" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\nstuff\n\n%s' "$SEC")"; idem B9 "$H"

echo "== Replacing an installed section, heading through end comment"
H=$(newhome u1); put "$H" '# Mine\n\n%s\n- My own rule.\n@docs/team.md\n' "$OLD"; inst "$H" >/dev/null
same "U1 an earlier wording is replaced, lines after its end comment kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s\n- My own rule.\n@docs/team.md' "$SEC")"; idem U1 "$H"
ls "$H/.claude" | grep -q 'CLAUDE.md.bak' && bad U1b "a CLAUDE.md backup was saved: $(ls "$H/.claude" | grep bak)" || ok "U1b updating CLAUDE.md saves no backup of it"
H=$(newhome u2); put "$H" '# Mine\n\nstuff\n\n%s\n\n## Other\n\nkeep\n' "$OLD"; inst "$H" >/dev/null
same "U2 section in the middle: replaced, the rest kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\nstuff\n\n%s\n\n## Other\n\nkeep' "$SEC")"; idem U2 "$H"
H=$(newhome u3); put "$H" '## Claude Code subagents\n- Use pnpm.\n%s\n%s\n' "$OLD_BODY" "$MARK"; out=$(inst "$H")
same "U3 a line of yours inside the section is replaced with the rest" "$H/.claude/CLAUDE.md" "$SEC"
printf '%s\n' "$out" | grep -qxF -- '    -- Use pnpm.' && ok "U3 the printed diff shows the dropped line" || bad U3 "diff doesn't show it"; idem U3 "$H"
H=$(newhome u5); put "$H" '%s\n\nbetween\n\n%s\n\n## End\n' "$OLD" "$OLD"; out=$(inst "$H"); f="$H/.claude/CLAUDE.md"
same "U5 two copies: the first replaced, the second left as it is" "$f" "$(printf '%s\n\nbetween\n\n%s\n\n## End' "$SEC" "$OLD")"
n=$(grep -n '^## Claude Code subagents$' "$f" | sed -n 2p | cut -d: -f1)
printf '%s' "$out" | grep -q "line $n has another copy" && ok "U5 warns about the second copy at its line in the updated file ($n)" || bad U5 "no warning naming line $n: $(printf '%s' "$out" | grep -m1 warning)"; idem U5 "$H"
H=$(newhome u6); awk '{ printf "%s\r\n", $0 }' <<< "$OLD" > "$H/.claude/CLAUDE.md"; printf -- '- mine\r\n' >> "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(wc -l < "$f" | tr -d ' ')" = "$(grep -c $'\r$' "$f")" ] && [ "$(grep -c $'\r\r' "$f")" = 0 ] && [ "$(heads "$f")" = 1 ] && grep -q $'^- mine\r$' "$f" && ! grep -q 'An old rule' "$f" && ok "U6 CRLF file stays CRLF, your line kept" || bad U6 "heads=$(heads "$f")"; idem U6 "$H"
H=$(newhome u7); put "$H" '\357\273\277%s\n\n## Other\n' "$OLD"; inst "$H" >/dev/null
same "U7 BOM before the heading is kept" "$H/.claude/CLAUDE.md" "$(printf '\357\273\277%s\n\n## Other' "$SEC")"; idem U7 "$H"
for hv in '## Claude Code subagents  ' '## Claude Code subagents ##' '##\tClaude  Code subagents'; do
  H=$(newhome "u9$(printf '%s' "$hv" | cksum | cut -d' ' -f1)"); put "$H" "$hv\n%s\n%s\n" "$OLD_BODY" "$MARK"; inst "$H" >/dev/null
  same "U9 heading written as '$hv' is recognized" "$H/.claude/CLAUDE.md" "$SEC"
done
H=$(newhome u12); rmdir "$H/.claude"; inst "$H" >/dev/null; printf -- '- Added later by Claude.\n' >> "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "U12 a line appended after a fresh install survives the next run" "$H/.claude/CLAUDE.md" "$(printf '%s\n- Added later by Claude.' "$SEC")"
# (runs from $T where there's no CLAUDE.md, so the "also has" warning for the repo's own doesn't show)
H=$(newhome u18); put "$H" '%s\n' "$OLD"; a=$(treesum "$H"); out=$(cd "$T" && inst "$H" "" --dry-run)
printf '%s\n' "$out" | grep -qxF -- '    -- An old rule.' && printf '%s\n' "$out" | grep -q '^    +' && ! printf '%s' "$out" | grep -q warning && [ "$a" = "$(treesum "$H")" ] && ok "U18 dry run: the diff shows old and new lines, no warning, nothing written" || bad U18 "output: $(printf '%s' "$out" | grep -m3 '^    [-+]')"
PW="$T/pkgreword"; cp -R "$PKG" "$PW"; sed '5s/.*/- A reworded rule./' "$PKG/CLAUDE.md" > "$PW/CLAUDE.md"
H=$(newhome r1); put "$H" '%s\n- mine\n' "$SEC"; inst "$H" "$PW" >/dev/null
same "R1 a reworded line in the package replaces the installed wording, nothing else needed" "$H/.claude/CLAUDE.md" "$(printf '%s\n- mine' "$(cat "$PW/CLAUDE.md")")"
H=$(newhome e1); put "$H" '# Mine\n%s\n' "$MARK"; inst "$H" >/dev/null
same "E1 an end comment with no heading before it is an ordinary line" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n%s\n\n%s' "$MARK" "$SEC")"; idem E1 "$H"
H=$(newhome u19); put "$H" '%s\nafter' "$OLD"; inst "$H" >/dev/null; printf '%s\nafter' "$SEC" > "$T/expected"
cmp -s "$T/expected" "$H/.claude/CLAUDE.md" && ok "U19 a file without a final newline still has none after the update" || bad U19 "last bytes: $(tail -c 6 "$H/.claude/CLAUDE.md" | od -c | head -1)"; idem U19 "$H"

echo "== Code fences aren't parsed"
H=$(newhome k1); put "$H" '# Notes\n```md\n```bash\nx\n```\n```\n\n%s\n' "$OLD"; inst "$H" >/dev/null
same "K1 naively nested example before the section" "$H/.claude/CLAUDE.md" "$(printf '# Notes\n```md\n```bash\nx\n```\n```\n\n%s' "$SEC")"; idem K1 "$H"
H=$(newhome k2); put "$H" '# Mine\n\n```bash\nx\n\n%s\n' "$OLD"; inst "$H" >/dev/null
same "K2 a code block that's never closed before the section" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```bash\nx\n\n%s' "$SEC")"; idem K2 "$H"
H=$(newhome k4); put "$H" '# Mine\n\n```text\nStart blocks like:\n```python\n```\n\n%s\n' "$OLD"; inst "$H" >/dev/null
same "K4 a fence shown as text inside a block" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```text\nStart blocks like:\n```python\n```\n\n%s' "$SEC")"
H=$(newhome k6); put "$H" '# Mine\n```md\n%s\n```\n' "$OLD"; inst "$H" >/dev/null
same "K6 a heading and end comment inside a fence are replaced too" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n```md\n%s\n```' "$SEC")"

echo "== Headings that aren't an installed copy"
H=$(newhome w1); put "$H" '# Mine\n\n```md\n## Claude Code subagents\n- my team rule\n```\n'; out=$(inst "$H")
same "W1 an example with the heading: section appended, example untouched" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```md\n## Claude Code subagents\n- my team rule\n```\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'line 4 .*left alone' && ok "W1 warns about line 4" || bad W1 "no warning naming line 4"
out=$(inst "$H"); printf '%s' "$out" | grep -q 'unchanged .*CLAUDE.md' && printf '%s' "$out" | grep -q 'line 4 .*left alone' && ok "W1 rerun: unchanged, still warns" || bad W1 "rerun"
H=$(newhome w2); put "$H" '# Mine\n\n```md\n## Claude Code subagents\n- my team rule\n```\n\n%s\n' "$OLD"; out=$(inst "$H")
same "W2 real section replaced, the example left alone" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```md\n## Claude Code subagents\n- my team rule\n```\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'line 4 .*left alone' && ok "W2 warns about the example" || bad W2 "no warning"
H=$(newhome w3); put "$H" '## Claude Code subagents\n\n- old routing to Plan\n'; out=$(inst "$H")
same "W3 a heading with no end comment after it is kept, the section appended" "$H/.claude/CLAUDE.md" "$(printf '## Claude Code subagents\n\n- old routing to Plan\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'line 1 .*left alone' && ok "W3 warns about line 1" || bad W3 "no warning"
H=$(newhome w4); put "$H" '### Claude Code subagents\n- a\n## Claude Code subagents and more\n- b\n  ## Claude Code subagents\n- c\n'; out=$(inst "$H")
same "W4 ###, longer and indented headings aren't the section" "$H/.claude/CLAUDE.md" "$(printf '### Claude Code subagents\n- a\n## Claude Code subagents and more\n- b\n  ## Claude Code subagents\n- c\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'left alone' && bad W4 "unexpected warning" || ok "W4 no warning for them"
H=$(newhome w5); put "$H" '%s\n\n```md\n## Claude Code subagents\n- my team rule\n```\n' "$OLD"; out=$(inst "$H"); f="$H/.claude/CLAUDE.md"
same "W5 an example after the real section is left alone" "$f" "$(printf '%s\n\n```md\n## Claude Code subagents\n- my team rule\n```' "$SEC")"; idem W5 "$H"
n=$(grep -n '^## Claude Code subagents$' "$f" | sed -n 2p | cut -d: -f1)
printf '%s' "$out" | grep -q "line $n .*left alone" && ok "W5 the warning names the example's line in the updated file ($n)" || bad W5 "warning doesn't name line $n: $(printf '%s' "$out" | grep -m1 'left alone')"
H=$(newhome w6); put "$H" '## Claude Code subagents\n- an old note\n\n%s\n' "$OLD"; out=$(inst "$H")
same "W6 a heading right above an installed copy is left alone, the copy replaced" "$H/.claude/CLAUDE.md" "$(printf '## Claude Code subagents\n- an old note\n\n%s' "$SEC")"
printf '%s' "$out" | grep -q 'line 1 .*left alone' && ok "W6 warns about line 1" || bad W6 "no warning"; idem W6 "$H"
H=$(newhome w7); put "$H" '## Claude Code subagents\n- old\n## Other\nkeep\n%s\n' "$MARK"; out=$(inst "$H")
same "W7 a # or ## heading before the end comment: nothing replaced, the section appended" "$H/.claude/CLAUDE.md" "$(printf '## Claude Code subagents\n- old\n## Other\nkeep\n%s\n\n%s' "$MARK" "$SEC")"
printf '%s' "$out" | grep -q 'line 1 .*left alone' && ok "W7 warns about line 1" || bad W7 "no warning"; idem W7 "$H"
H=$(newhome w8); put "$H" '## Claude Code subagents\n### My notes\n- mine\n%s\n' "$MARK"; inst "$H" >/dev/null
same "W8 a ### subsection inside an installed copy is replaced with it" "$H/.claude/CLAUDE.md" "$SEC"

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

echo "== Windows line endings and byte order marks in the package"
CR="$T/pkgcr"; cp -R "$PKG" "$CR"; awk '{ printf "%s\r\n", $0 }' "$PKG/CLAUDE.md" > "$CR/CLAUDE.md"
H=$(newhome c1); put "$H" '# Mine\n\n%s\n' "$OLD"; inst "$H" "$CR" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(grep -c $'\r' "$f")" = 0 ] && ok "C1 CRLF section into an LF file: no CRs" || bad C1 "$(grep -c $'\r' "$f") lines with CR"
a=$(sum "$f"); inst "$H" "$CR" >/dev/null; [ "$a" = "$(sum "$f")" ] && [ "$(heads "$f")" = 1 ] && ok "C1 (idempotent)" || bad "C1 (idempotent)" "heads=$(heads "$f")"
H=$(newhome c2); awk '{ printf "%s\r\n", $0 }' <<< "$OLD" > "$H/.claude/CLAUDE.md"; inst "$H" "$CR" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(grep -c $'\r\r' "$f")" = 0 ] && [ "$(wc -l < "$f" | tr -d ' ')" = "$(grep -c $'\r$' "$f")" ] && ok "C2 CRLF section into a CRLF file: single CRs" || bad C2 "double CRs: $(grep -c $'\r\r' "$f")"
a=$(sum "$f"); inst "$H" "$CR" >/dev/null; [ "$a" = "$(sum "$f")" ] && [ "$(heads "$f")" = 1 ] && ok "C2 (idempotent)" || bad "C2 (idempotent)" "heads=$(heads "$f")"
H=$(newhome c3); rmdir "$H/.claude"; inst "$H" "$CR" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(grep -c $'\r' "$f")" = 0 ] && ok "C3 CRLF section, new CLAUDE.md: no CRs" || bad C3 "$(grep -c $'\r' "$f") lines with CR"
H=$(newhome c4); printf '# Mine\r\n' > "$H/.claude/CLAUDE.md"; inst "$H" "$CR" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(grep -c $'\r\r' "$f")" = 0 ] && [ "$(wc -l < "$f" | tr -d ' ')" = "$(grep -c $'\r$' "$f")" ] && ok "C4 CRLF section appended to a CRLF file: single CRs" || bad C4 "double CRs: $(grep -c $'\r\r' "$f")"
[ -f "$PKG/.gitattributes" ] && grep -q 'eol=lf' "$PKG/.gitattributes" && ok "C5 .gitattributes forces LF" || bad C5 "no .gitattributes with eol=lf"
BM="$T/pkgbom"; cp -R "$PKG" "$BM"; { printf '\357\273\277'; cat "$PKG/CLAUDE.md"; } > "$BM/CLAUDE.md"
H=$(newhome c7); put "$H" '# Mine\n\n%s\n' "$OLD"; inst "$H" "$BM" >/dev/null; inst "$H" "$BM" >/dev/null
same "C7 BOM in the package's CLAUDE.md isn't copied mid-file" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s' "$SEC")"
H=$(newhome c8); rmdir "$H/.claude"; inst "$H" "$BM" >/dev/null; inst "$H" "$BM" >/dev/null
same "C8 BOM in the package: new CLAUDE.md has none, rerun unchanged" "$H/.claude/CLAUDE.md" "$SEC"

echo "== Finding the section in --project mode"
P=$T/proj1; rm -rf "$P"; mkdir -p "$P/.claude"; H=$(newhome hs1)
printf '# Proj\n\n```md\n## Claude Code subagents\n- example\n```\n' > "$P/CLAUDE.md"; printf '%s\n' "$OLD" > "$P/.claude/CLAUDE.md"; a=$(sum "$P/CLAUDE.md")
(cd "$P" && inst "$H" "" --project >/dev/null)
[ "$a" = "$(sum "$P/CLAUDE.md")" ] && same "S1 --project picks the file with the installed copy" "$P/.claude/CLAUDE.md" "$SEC" || bad S1 "./CLAUDE.md changed"
P=$T/proj2; rm -rf "$P"; mkdir -p "$P"; H=$(newhome hs2); printf '# Proj\n\n```md\n## Claude Code subagents\n- example\n```\n' > "$P/CLAUDE.md"
out=$(cd "$P" && inst "$H"); printf '%s' "$out" | grep -q 'also has' && bad S2 "false duplicate warning" || ok "S2 no duplicate warning for an example"
P=$T/proj3; rm -rf "$P"; mkdir -p "$P"; H=$(newhome hs3); printf '# Proj\n\n%s\n' "$SEC" > "$P/CLAUDE.md"
out=$(cd "$P" && inst "$H"); printf '%s' "$out" | grep -q 'proj3/CLAUDE.md also has' && ok "S3 duplicate warning for a real section elsewhere" || bad S3 "no warning"
P=$T/proj5; rm -rf "$P"; mkdir -p "$P"; H=$(newhome hs5); printf '# Proj\n\n## Claude Code subagents\n\n- Old routing to the Plan agent.\n' > "$P/CLAUDE.md"
out=$(cd "$P" && inst "$H"); printf '%s' "$out" | grep -q 'proj5/CLAUDE.md has a "Claude Code subagents" heading too' && ok "S5 warning for a heading without an end comment in another CLAUDE.md" || bad S5 "no warning"
P=$T/proj6; rm -rf "$P"; mkdir -p "$P/.claude"; H=$(newhome hs6); printf '# Proj\n\n- Use pnpm.\n' > "$P/CLAUDE.md"; printf '## Claude Code subagents\n- old\n' > "$P/.claude/CLAUDE.md"; a=$(sum "$P/CLAUDE.md")
(cd "$P" && inst "$H" "" --project >/dev/null)
[ "$a" = "$(sum "$P/CLAUDE.md")" ] && [ "$(heads "$P/.claude/CLAUDE.md")" = 2 ] && ok "S6 --project picks the file with a section heading, not the one without" || bad S6 "picked ./CLAUDE.md"

echo "== Refusals stop the whole install"
if [ "$(id -u)" != 0 ]; then
  H=$(newhome x1); put "$H" '# Mine\n'; chmod a-w "$H/.claude/CLAUDE.md"
  refused "X1 a read-only CLAUDE.md that needs a change: refused before anything is installed" "$H" "can't write"; chmod u+w "$H/.claude/CLAUDE.md"
  H=$(newhome x3); rmdir "$H/.claude"; inst "$H" >/dev/null; rm "$H/.claude/agents/critic.md"; chmod a-w "$H/.claude/CLAUDE.md"; out=$(inst "$H"); rc=$?; chmod u+w "$H/.claude/CLAUDE.md"
  [ $rc = 0 ] && [ -f "$H/.claude/agents/critic.md" ] && printf '%s' "$out" | grep -q 'unchanged .*CLAUDE.md' && ok "X3 a read-only CLAUDE.md that's already current: install goes ahead" || bad X3 "rc=$rc $(printf '%s' "$out" | grep -m1 error)"
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
sed -n 3p "$PKG/CLAUDE.md" | grep -q 'for the main conversation' && ok "Q2 CLAUDE.md starts with the subagent rule" || bad Q2 "rule missing"
grep -q 'git status --short' "$PKG/agents/critic.md" && ok "Q3 critic checks untracked files" || bad Q3 "no git status"
! grep -q 'wrap the whole description in double quotes' "$PKG/README.md" && grep -q "Don't wrap it in double quotes" "$PKG/README.md" && ok "Q4 README no longer suggests double quotes" || bad Q4 "old advice"
if command -v ruby >/dev/null; then
  broken=""
  for f in "$PKG"/agents/*.md "$PKG"/skills/*/SKILL.md; do
    ruby -ryaml -e 'y = YAML.safe_load(File.read(ARGV[0], encoding: "UTF-8").split(/^---\s*$/)[1]); exit(y["name"] && y["description"] ? 0 : 1)' "$f" 2>/dev/null || broken="$broken ${f#"$PKG"/}"
  done
  [ -z "$broken" ] && ok "Q5 all agent and skill frontmatter parses (checked with Ruby)" || bad Q5 "frontmatter doesn't parse:$broken"
else
  echo "skip Q5 frontmatter parse check (needs Ruby)"
fi

[ "$(tail -n 1 "$PKG/CLAUDE.md")" = "$MARK" ] && ok "Q6 CLAUDE.md ends with the end-of-section comment" || bad Q6 "wrong last line"
missing=""; for n in $(grep -o '`[a-z-]*`' "$PKG/CLAUDE.md" | tr -d '`' | sort -u); do [ -f "$PKG/agents/$n.md" ] || [ -d "$PKG/skills/$n" ] || missing="$missing $n"; done
[ -z "$missing" ] && ok "Q7 every agent and skill CLAUDE.md names is in the package" || bad Q7 "not in agents/ or skills/:$missing"
g="$PKG/skills/ship/SKILL.md"; missing=""
grep '^- Git work' "$PKG/CLAUDE.md" | grep 'push' | grep 'only when I ask' | grep 'Load the `ship` skill first' | grep -q 'take precedence over the default git instructions where they conflict' || missing="$missing [CLAUDE.md: a git line covering push, only when I ask, loading ship first, taking precedence over the defaults only where they conflict]"
sed -n 's/^description: //p' "$g" 2>/dev/null | grep -q 'push' || missing="$missing [ship description: push]"
for s in '<short-kebab-name>' 'Closes #<issue>' 'squash if more'; do grep -q -- "$s" "$PKG/CLAUDE.md" && missing="$missing [CLAUDE.md still has: $s]"; done
for s in "run the project's tests" '^## Branch' '<short-kebab-name>' '^## Commit' 'Conventional Commits' '^## PR' 'Closes #<issue>' '^## Merge' 'squash if more' '^## After merging' 'remote and local branch' 'link to the merged PR'; do grep -qi -- "$s" "$g" 2>/dev/null || missing="$missing [ship: $s]"; done
[ -z "$missing" ] && ok "Q8 the git rules (branch, commit, PR, merge, cleanup, issue update) are in the ship skill, and CLAUDE.md only says to use it when asked" || bad Q8 "missing:$missing"
grep '^- Non-trivial change' "$PKG/CLAUDE.md" | grep -q '`tdd`' && grep '^- Something broken' "$PKG/CLAUDE.md" | grep -q '`tdd`' && ok "Q9 the non-trivial and bug-fix routes in CLAUDE.md name tdd" || bad Q9 "tdd missing from a route"
a="$PKG/agents"; grep -qx 'model: sonnet' "$a/critic.md" && grep -qx 'effort: medium' "$a/critic.md" && grep -qx 'model: haiku' "$a/scout.md" && grep -qx 'effort: low' "$a/scout.md" \
  && grep -qx 'model: sonnet' "$a/smith.md" && grep -qx 'effort: low' "$a/smith.md" \
  && grep -q '^| `critic` | sonnet | medium |' "$PKG/README.md" && grep -q '^| `scout` | haiku | low |' "$PKG/README.md" && grep -q '^| `smith` | sonnet | low |' "$PKG/README.md" \
  && ok "Q10 critic is sonnet/medium, scout haiku/low and smith sonnet/low, in the agents and README" || bad Q10 "model or effort differs"
# (bracketed so this line doesn't match itself)
legacy='old-[s]ections|spec-[w]riter|[s]pecifier|[p]lanner|[b]uilder|[r]etire|claude-[c]onf|[r]eviewer|[e]xplorer|`[b]uild`'
hits=$(cd "$PKG" && grep -nE "$legacy|[b]uild (report|skill)" README.md install.sh tests/regress.sh CLAUDE.md skills/*/SKILL.md)
# The agents only get the build checks: critic's prompt names its role (code review) with a word on the list above
hits="$hits$(cd "$PKG" && grep -nE '`[b]uild`|[b]uild (report|skill)' agents/*.md)"
[ -z "$hits" ] && ok "Q11 no earlier names or upgrade paths are left" || bad Q11 "$(printf '%s' "$hits" | head -3 | cut -c1-80)"
[ "$(ls "$PKG/skills" | tr '\n' ' ')" = "blueprint inspect scope ship spec tdd " ] && ok "Q12 the package ships exactly the skills blueprint, inspect, scope, ship, spec and tdd" || bad Q12 "skills/ holds: $(ls "$PKG/skills" | tr '\n' ' ')"
grep '^- Mechanical changes' "$PKG/CLAUDE.md" | grep '`critic`' | grep 'logic, security, auth or data' | grep -q 'keeps the meaning' && ok "Q13 mechanical changes skip the plan steps and critic, unless they touch logic, security, auth or data" || bad Q13 "no mechanical-changes route with its limits"
s="$PKG/agents/smith.md"; fm=$(sed -n '2,/^---$/p' "$s" 2>/dev/null); missing=""
for t in Edit Write Bash; do printf '%s\n' "$fm" | grep '^tools:' | grep -q "$t" || missing="$missing [tools: $t]"; done
printf '%s\n' "$fm" | grep -A3 -x 'skills:' | grep -qx '  - tdd' || missing="$missing [skills: - tdd]"
for p in "can't ask the user" 'report Blocked' 'leave the code building' 'files you touched'; do sed '1,/^---$/d' "$s" 2>/dev/null | grep -q "$p" || missing="$missing [$p]"; done
sed '1,/^---$/d' "$s" 2>/dev/null | grep -qF 'as text' || missing="$missing [smith: a plan can arrive as text]"
sed -n 's/^description: //p' "$s" 2>/dev/null | grep -qF '/blueprint' || missing="$missing [smith description: usually from /blueprint]"
[ -z "$missing" ] && ok "Q15 smith can edit and run commands, preloads tdd, and reports Blocked instead of asking, leaving work a new run can pick up" || bad Q15 "agents/smith.md:$missing"

c="$PKG/CLAUDE.md"; missing=""
nt=$(grep '^- Non-trivial change' "$c")
for t in '`/scope`' '`/spec`' '`/blueprint`' '`smith`' '`critic`' '`tdd`' 'known cause' 'only the step I ask for'; do printf '%s\n' "$nt" | grep -qF -- "$t" || missing="$missing [Non-trivial line: $t]"; done
grep -q '^- Vague' "$c" && missing="$missing [still has a Vague line]"
grep -q '^- Give `critic`' "$c" && missing="$missing [still has the Give critic line]"
printf '%s\n' "$nt" | grep -qF 'multi-file' && missing="$missing [Non-trivial line still says multi-file fix]"
sed -n 3p "$c" | grep -qF 'without dispatching other agents unless that task says to' || missing="$missing [line 3 says subagents dispatch no other agents]"
grep '^- Before saying work is done' "$c" | grep -qF 'run the tests or checks and read their output' && grep '^- Before saying work is done' "$c" | grep -qF 'confirm a subagent' || missing="$missing [verify-before-done line]"
# 2654 bytes was CLAUDE.md's size before foreman. It mustn't grow: it loads into every session and every subagent.
[ "$(wc -c < "$c")" -le 2654 ] || missing="$missing [over 2654 bytes]"
[ -z "$missing" ] && ok "Q17 CLAUDE.md sends non-trivial work down the user-run chain, asks to verify before done and keeps subagents out of it" || bad Q17 "CLAUDE.md:$missing"
# nothing shipped names the removed orchestrator or check skill, or the task status file
hits=$(cd "$PKG" && grep -niE 'foreman|`check`|the check skill|(^|[ (])/check\b|status\.md' CLAUDE.md README.md agents/*.md skills/*/SKILL.md | grep -v '^README.md:[0-9]*:- Removes the skills the package no longer ships')  # the README's install note names the removed skills
[ -z "$hits" ] && ok "Q22 no shipped file names foreman, the check skill, /check or status.md" || bad Q22 "$(printf '%s' "$hits" | head -3 | cut -c1-80)"
missing=""
has() { grep -qF -- "$2" "$PKG/$1" 2>/dev/null || missing="$missing [$1: $2]"; }
has skills/blueprint/SKILL.md '**Acceptance criteria**'; has skills/blueprint/SKILL.md '**Phases**'; has skills/spec/SKILL.md '**Goals / Non-goals**'; has skills/scope/SKILL.md 'one question at a time'
has skills/inspect/SKILL.md '`/blueprint`'
has agents/smith.md "The plan doesn't hold"; has agents/smith.md 'acceptance criteria'
has agents/critic.md '**Acceptance criteria'; has agents/critic.md '[plan]'; has agents/critic.md 'as text'
has skills/ship/SKILL.md '`docs/conf/tasks/` is never committed'
grep -q '^| `foreman` |' "$PKG/README.md" && missing="$missing [README still has a foreman row]"
grep -q '^| `check` |' "$PKG/README.md" && missing="$missing [README still has a check row]"
has README.md 'docs/conf/tasks/<slug>/'
# the dropped skills and their slash commands are named nowhere (this file is left out, since it names them)
hits=$(cd "$PKG" && grep -nE '(^|[ `(])/(critic|scout|smith|foreman|check)\b' CLAUDE.md README.md agents/*.md skills/*/SKILL.md)
[ -z "$hits" ] || missing="$missing [still names a dropped skill or its slash command: $(printf '%s' "$hits" | head -2 | cut -c1-60 | tr '\n' ' ')]"
[ -z "$missing" ] && ok "Q18 acceptance criteria and plan-level findings are named in blueprint, smith, critic, inspect, ship and the README, and no dropped skill is named" || bad Q18 "missing:$missing"

# ship runs the tests itself, keeps a task branch without a status file, and finds the PR base without one
missing=""; g="$PKG/skills/ship/SKILL.md"
for t in "Run the project's tests" 'stop and report if they fail' 'keep it' '`docs/conf/tasks/` is never committed' "the PR's existing base"; do grep -qF -- "$t" "$g" 2>/dev/null || missing="$missing [ship: $t]"; done
for t in 'status.md' '`- Parent:`' 'Run the `check` skill'; do grep -qF -- "$t" "$g" 2>/dev/null && missing="$missing [ship still has: $t]"; done
[ -z "$missing" ] && ok "Q19 ship runs the project's tests before committing and no longer reads a status file" || bad Q19 "missing:$missing"

# scope, spec and blueprint are loadable on their own, run by the user, and each names the next step
missing=""
for n in scope spec blueprint; do
  s="$PKG/skills/$n/SKILL.md"; fm=$(sed -n '2,/^---$/p' "$s" 2>/dev/null)
  [ "$(sed -n 1p "$s" 2>/dev/null)" = '---' ] && [ "$(printf '%s\n' "$fm" | tail -n 1)" = '---' ] || missing="$missing [$n: frontmatter between --- lines]"
  printf '%s\n' "$fm" | grep -qx "name: $n" || missing="$missing [$n: name]"
  printf '%s\n' "$fm" | grep -q '^description: .' || missing="$missing [$n: description]"
  printf '%s\n' "$fm" | grep -qE '^(disable-model-invocation|context|agent):' && missing="$missing [$n: sets disable-model-invocation, context or agent]"
  printf '%s\n' "$fm" | grep '^description: ' | grep -qE ': .*: | #|:$' && missing="$missing [$n: description is not plain YAML]"
done
has skills/scope/SKILL.md 'vague'; has skills/scope/SKILL.md 'Play it back'
has skills/scope/SKILL.md 'Next: `/spec`.'; has skills/spec/SKILL.md 'Next: `/blueprint`.'; has skills/blueprint/SKILL.md 'Next: ask `smith` to build it'
for n in spec blueprint; do
  s="$PKG/skills/$n/SKILL.md"
  has "skills/$n/SKILL.md" '## Save'; has "skills/$n/SKILL.md" '.git/info/exclude'; has "skills/$n/SKILL.md" '**/docs/conf/tasks/'; has "skills/$n/SKILL.md" 'keep'
  has "skills/$n/SKILL.md" 'docs/conf/tasks/<slug>/'; has "skills/$n/SKILL.md" 'the folder will show up in `git status`'; has "skills/$n/SKILL.md" 'next free number'
  grep -qF 'Where it goes' "$s" 2>/dev/null && missing="$missing [$n: still has Where it goes]"
done
has skills/spec/SKILL.md 'spec.md'; has skills/blueprint/SKILL.md 'plan.md'; has skills/blueprint/SKILL.md "path, or the plan text if it wasn't saved"
sed -n 's/^description: //p' "$PKG/skills/scope/SKILL.md" | grep -qF '/spec' || missing="$missing [scope description names /spec]"
sed -n 's/^description: //p' "$PKG/skills/spec/SKILL.md" | grep -qF '/blueprint' || missing="$missing [spec description names /blueprint]"
sed -n 's/^description: //p' "$PKG/skills/blueprint/SKILL.md" | grep -qF 'smith' || missing="$missing [blueprint description names smith]"
# fix round: blueprint's input, slug reuse, revising a plan, ship's base, bare requests
for n in spec blueprint; do
  has "skills/$n/SKILL.md" 'argument-hint: the request, or a task folder to save to'
  has "skills/$n/SKILL.md" 'is for the same task (same summary or issue), update it in place'
done
has skills/blueprint/SKILL.md 'Start from the spec agreed in this conversation, or the `spec.md` the request names; without either, write your own acceptance criteria.'
has skills/blueprint/SKILL.md 'revise the existing plan (the saved `plan.md`, or the one in this conversation)'
grep -q '^Every route\.' "$PKG/skills/blueprint/SKILL.md" && missing="$missing [blueprint still says Every route.]"
grep -q ' $' "$PKG/skills/spec/SKILL.md" && missing="$missing [spec has trailing spaces]"
has skills/ship/SKILL.md "isn't known"; has skills/ship/SKILL.md 'ask the user which base to use'
grep '^- Non-trivial change' "$PKG/CLAUDE.md" | grep -qF 'For a bare request, suggest `/scope`.' || missing="$missing [CLAUDE.md: bare request suggests /scope]"
has README.md 'run `/blueprint` again'
# phase content: scope (AC5), spec (AC6), blueprint (AC7), tdd and smith (AC8), critic (AC9)
for t in 'single pass' 'Risks & feasibility' '**Size**' 'smallest version worth shipping' 'spike'; do has skills/scope/SKILL.md "$t"; done
grep -qF 'Only for a vague request' "$PKG/skills/scope/SKILL.md" && missing="$missing [scope still says Only for a vague request]"
for t in 'R1, R2' 'NFR1, NFR2' 'other than the NFRs' '**Data & interfaces**' '**Open questions**' 'requirement IDs' 'measurable target'; do has skills/spec/SKILL.md "$t"; done
for t in '**Architecture**' '**Interfaces & data models**' '**Test strategy**' '**Rollout & rollback**' 'n/a' 'requirement IDs'; do has skills/blueprint/SKILL.md "$t"; done
for t in 'integration' 'end-to-end' 'test strategy' 'outside-in'; do has skills/tdd/SKILL.md "$t"; done
has agents/smith.md 'test strategy'
for t in 'Always run the tests' 'end-to-end' "A criterion you can't check is a **Should fix**" 'each requirement ID this phase covers' 'when the spec has IDs' 'no passing test or check' 'Acceptance criteria & requirements' '**Acceptance criteria'; do has agents/critic.md "$t"; done
grep '^- Read-only' "$PKG/agents/critic.md" | grep -qF 'run the app or the end-to-end path' || missing="$missing [critic Rules: may run the app or end-to-end path]"
sed -n 's/^description: //p' "$PKG/skills/scope/SKILL.md" | grep -qF 'vague idea' && missing="$missing [scope description still says vague idea]"
sed -n 's/^description: //p' "$PKG/skills/scope/SKILL.md" | grep -qF 'any request' || missing="$missing [scope description says any request]"
has skills/scope/SKILL.md "clear request, ask only what's missing, then go to step 6"; has skills/scope/SKILL.md 'applies to a vague request'
has skills/blueprint/SKILL.md "spec's Open questions"
has skills/tdd/SKILL.md 'may stay red while'
grep -qi 'not checkable' "$PKG/agents/critic.md" "$PKG/README.md" && missing="$missing [critic or README still offers not checkable as a status]"
[ -z "$missing" ] && ok "Q21 scope, spec and blueprint are model-invocable inline skills that name their next step, spec and blueprint ask whether to save, and the scope, spec, blueprint, tdd, smith and critic content covers the SDLC phases" || bad Q21 "missing:$missing"

echo "== Skills the package no longer ships"
# Real copies of the dropped skills come from the package's git history
old=""; new=""; cur=""
if command -v git >/dev/null 2>&1; then
  old=$(git -C "$PKG" rev-parse -q --verify b1d9b06 2>/dev/null) || old=""
  new=$(git -C "$PKG" rev-parse -q --verify 7e339b4 2>/dev/null) || new=""
  cur=$(git -C "$PKG" rev-parse -q --verify 8badc4a 2>/dev/null) || cur=""
fi
if [ -z "$old" ]; then
  echo "skip Q20 installer removes dropped skills (needs git and the package's history)"
else
  # plant <home> <name> [commit]: an installed copy of a dropped skill as the package shipped it
  plant() { mkdir -p "$1/.claude/skills/$2"; git -C "$PKG" show "${3:-$old}:skills/$2/SKILL.md" > "$1/.claude/skills/$2/SKILL.md"; }
  H=$(newhome q20a); inst "$H" >/dev/null; plant "$H" scout; plant "$H" smith; out=$(inst "$H"); rc=$?
  [ $rc = 0 ] && [ ! -e "$H/.claude/skills/scout" ] && [ ! -e "$H/.claude/skills/smith" ] && printf '%s\n' "$out" | grep -q '^removed .*skills/scout' && printf '%s\n' "$out" | grep -q '^removed .*skills/smith' && ok "Q20 unedited copies of dropped skills are removed, and the output says so" || bad Q20 "rc=$rc left=$(ls "$H/.claude/skills" | tr '\n' ' ') output: $(printf '%s' "$out" | grep -m1 'scout')"
  [ "$(ls "$H/.claude/skills" | tr '\n' ' ')" = "blueprint inspect scope ship spec tdd " ] && ok "Q20 the skills the package ships stay" || bad Q20 "skills: $(ls "$H/.claude/skills" | tr '\n' ' ')"
  out=$(inst "$H"); printf '%s\n' "$out" | grep -qE '^(removed|would remove|warning) .*skills/(check|critic|foreman|scout|smith)' && bad Q20 "second run: $(printf '%s' "$out" | grep -m1 skills/)" || ok "Q20 a second run says nothing about dropped skills"
  H=$(newhome q20b); inst "$H" >/dev/null; plant "$H" scout; plant "$H" smith; a=$(treesum "$H"); out=$(inst "$H" "" --dry-run)
  [ "$a" = "$(treesum "$H")" ] && [ -f "$H/.claude/skills/scout/SKILL.md" ] && printf '%s\n' "$out" | grep -q '^would remove .*skills/scout' && ok "Q20 --dry-run says it would remove them, and removes nothing" || bad Q20 "dry run: changed=$([ "$a" = "$(treesum "$H")" ] && echo no || echo yes) output: $(printf '%s' "$out" | grep -m1 'scout')"
  H=$(newhome q20c); inst "$H" >/dev/null; plant "$H" scout; printf 'my line\n' >> "$H/.claude/skills/scout/SKILL.md"; out=$(inst "$H"); rc=$?
  [ $rc = 0 ] && grep -q 'my line' "$H/.claude/skills/scout/SKILL.md" && printf '%s\n' "$out" | grep -q '^warning .*skills/scout.*differs from every copy this package shipped' && ! printf '%s\n' "$out" | grep -q '^removed' && ok "Q20 an edited copy is kept, with a warning" || bad Q20 "edited: rc=$rc output: $(printf '%s' "$out" | grep -m1 'scout')"
  H=$(newhome q20d); inst "$H" >/dev/null; plant "$H" scout; printf 'mine\n' > "$H/.claude/skills/scout/notes.md"; out=$(inst "$H"); rc=$?
  [ $rc = 0 ] && [ -f "$H/.claude/skills/scout/notes.md" ] && [ -f "$H/.claude/skills/scout/SKILL.md" ] && printf '%s\n' "$out" | grep -q '^warning .*skills/scout' && ok "Q20 a copy with an extra file is kept, with a warning" || bad Q20 "extra file: rc=$rc output: $(printf '%s' "$out" | grep -m1 'scout')"
  H=$(newhome q20e); inst "$H" >/dev/null; mkdir -p "$T/q20-mine"; git -C "$PKG" show "$old:skills/critic/SKILL.md" > "$T/q20-mine/SKILL.md"; ln -s "$T/q20-mine" "$H/.claude/skills/critic"; out=$(inst "$H"); rc=$?
  [ $rc = 0 ] && [ -L "$H/.claude/skills/critic" ] && [ -f "$T/q20-mine/SKILL.md" ] && printf '%s\n' "$out" | grep -q '^warning .*skills/critic' && ok "Q20 a symlinked folder and its target are kept, with a warning" || bad Q20 "symlink: rc=$rc output: $(printf '%s' "$out" | grep -m1 'critic')"
  H=$(newhome q20g); inst "$H" >/dev/null; plant "$H" scout; mv "$H/.claude/skills/scout/SKILL.md" "$T/q20-link.md"; ln -s "$T/q20-link.md" "$H/.claude/skills/scout/SKILL.md"; out=$(inst "$H"); rc=$?
  [ $rc = 0 ] && [ -L "$H/.claude/skills/scout/SKILL.md" ] && [ -f "$T/q20-link.md" ] && printf '%s\n' "$out" | grep -q '^warning .*skills/scout' && ok "Q20 a copy whose SKILL.md is a link is kept, with a warning" || bad Q20 "linked SKILL.md: rc=$rc output: $(printf '%s' "$out" | grep -m1 'scout')"
  H=$(newhome q20h); inst "$H" >/dev/null; plant "$H" scout; : > "$H/.claude/skills/scout/.DS_Store"; out=$(inst "$H"); rc=$?
  [ $rc = 0 ] && [ ! -e "$H/.claude/skills/scout" ] && printf '%s\n' "$out" | grep -q '^removed .*skills/scout' && ok "Q20 a copy with only SKILL.md and .DS_Store is removed" || bad Q20 ".DS_Store: rc=$rc left=$(ls -A "$H/.claude/skills/scout" 2>/dev/null | tr '\n' ' ') output: $(printf '%s' "$out" | grep -m1 'scout')"
  H=$(newhome q20m); inst "$H" >/dev/null; plant "$H" scout; mkdir "$H/.claude/skills/scout/.DS_Store"; : > "$H/.claude/skills/scout/.DS_Store/data"; out=$(inst "$H")
  [ -f "$H/.claude/skills/scout/.DS_Store/data" ] && printf '%s\n' "$out" | grep -q '^warning .*skills/scout' && ok "Q20 a .DS_Store folder counts as an extra file: kept, with a warning" || bad Q20 ".DS_Store folder removed"
  P2=$T/pkg-reuse; rm -rf "$P2"; cp -R "$PKG" "$P2"; mkdir -p "$P2/skills/scout"; git -C "$PKG" show "$old:skills/scout/SKILL.md" > "$P2/skills/scout/SKILL.md"
  H=$(newhome q20n); out=$(inst "$H" "$P2")
  [ -f "$H/.claude/skills/scout/SKILL.md" ] && ! printf '%s\n' "$out" | grep -qE '^(removed|warning) .*skills/scout' && ok "Q20 a dropped name the package ships again is installed, not removed" || bad Q20 "shipped scout removed or warned about"
  if [ -n "$cur" ] && git -C "$PKG" cat-file -e "$cur:skills/foreman/SKILL.md" 2>/dev/null && git -C "$PKG" cat-file -e "$cur:skills/check/SKILL.md" 2>/dev/null; then
    H=$(newhome q20p); inst "$H" >/dev/null; plant "$H" foreman "$cur"; plant "$H" check "$cur"; out=$(inst "$H"); rc=$?
    [ $rc = 0 ] && [ ! -e "$H/.claude/skills/foreman" ] && [ ! -e "$H/.claude/skills/check" ] && printf '%s\n' "$out" | grep -q '^removed .*skills/foreman' && printf '%s\n' "$out" | grep -q '^removed .*skills/check' && ok "Q20 unedited foreman and check are removed, and the output says so" || bad Q20 "foreman/check: rc=$rc left=$(ls "$H/.claude/skills" | tr '\n' ' ')"
    for n in foreman check; do
      H=$(newhome q20q$n); inst "$H" >/dev/null; plant "$H" "$n" "$cur"; printf 'my line\n' >> "$H/.claude/skills/$n/SKILL.md"; out=$(inst "$H"); rc=$?
      [ $rc = 0 ] && grep -q 'my line' "$H/.claude/skills/$n/SKILL.md" && printf '%s\n' "$out" | grep -q "^warning .*skills/$n.*differs from every copy this package shipped" && ok "Q20 an edited $n is kept, with a warning" || bad Q20 "edited $n: rc=$rc output: $(printf '%s' "$out" | grep -m1 "$n")"
    done
  else
    echo "skip Q20 foreman and check (commit 8badc4a isn't in the history)"
  fi
  # A CLAUDE.md that can't be written stops the install before anything is removed
  if [ "$(id -u)" != 0 ]; then
    H=$(newhome q20i); inst "$H" >/dev/null; plant "$H" scout; put "$H" '# Mine\n'; chmod a-w "$H/.claude/CLAUDE.md"
    refused "Q20 a read-only CLAUDE.md that needs a change: refused before a dropped skill is removed" "$H" "can't write"; chmod u+w "$H/.claude/CLAUDE.md"
    [ -f "$H/.claude/skills/scout/SKILL.md" ] && ok "Q20 the dropped skill is still there after that refusal" || bad Q20 "scout was removed despite the refusal"
  else
    echo "skip Q20 refusal before removal (running as root)"
  fi
  # Every committed version of a dropped skill is in install.sh's table, and is removed when installed
  table=$(sed -n "/^DROPPED_SUMS='/,/'\$/p" "$PKG/install.sh" | sed "s/^DROPPED_SUMS='//; s/'\$//")
  H=$(newhome q20j); inst "$H" >/dev/null; versions=0; notin=""; kept=""
  for n in check critic foreman scout smith; do
    for h in $(git -C "$PKG" log --all --format=%H -- "skills/$n/SKILL.md" 2>/dev/null); do
      git -C "$PKG" cat-file -e "$h:skills/$n/SKILL.md" 2>/dev/null || continue
      versions=$((versions + 1)); c=$(git -C "$PKG" show "$h:skills/$n/SKILL.md" | cksum | awk -v n="$n" '{print n, $1, $2}')
      printf '%s\n' "$table" | grep -qxF "$c" || notin="$notin [$c]"
      plant "$H" "$n" "$h"; inst "$H" >/dev/null; [ -e "$H/.claude/skills/$n" ] && { kept="$kept [$n ${h%"${h#???????}"}]"; rm -rf "$H/.claude/skills/$n"; }
    done
  done
  [ "$versions" -gt 0 ] && [ -z "$notin" ] && ok "Q20 all $versions committed versions of the dropped skills are in install.sh's table" || bad Q20 "versions=$versions not in the table:$notin"
  [ "$versions" -gt 0 ] && [ -z "$kept" ] && ok "Q20 each of those versions is removed when installed" || bad Q20 "versions=$versions kept:$kept"
  if [ -n "$new" ]; then
    H=$(newhome q20f); inst "$H" >/dev/null; plant "$H" smith "$new"; out=$(inst "$H")
    [ ! -e "$H/.claude/skills/smith" ] && printf '%s\n' "$out" | grep -q '^removed .*skills/smith' && ok "Q20 the newest shipped versions are recognised too" || bad Q20 "newest: $(printf '%s' "$out" | grep -m1 'smith')"
  else
    echo "skip Q20 newest shipped versions (commit 7e339b4 isn't in the history)"
  fi
fi

echo "== OpenCode target"
# ohome <name>: an empty HOME (no .claude)
ohome() { local h="$T/$1"; rm -rf "$h"; mkdir -p "$h"; printf '%s' "$h"; }
OC=".config/opencode"
# run from an empty folder, so the package's own CLAUDE.md in the cwd isn't picked up
OCWD="$T/oc-cwd"; rm -rf "$OCWD"; mkdir -p "$OCWD"; cd "$OCWD" || exit 1
H=$(ohome oc0); a=$(treesum "$H"); out=$(inst "$H" "" --target bogus); rc=$?
[ $rc = 1 ] && [ "$a" = "$(treesum "$H")" ] && printf '%s' "$out" | grep -q 'Unknown target: bogus (use claude or opencode)' && ok "OC1 --target bogus exits 1, says so and writes nothing" || bad OC1 "rc=$rc output: $out"
H=$(ohome oc1); out=$(inst "$H" "" --target opencode); rc=$?
[ $rc = 0 ] && [ "$(ls "$H/$OC/agents" | tr '\n' ' ')" = "critic.md scout.md smith.md " ] && [ "$(ls "$H/$OC/skills" | wc -l | tr -d ' ')" = 6 ] && [ ! -e "$H/.claude" ] && ok "OC2 --target opencode installs 3 agents and 6 skills under ~/.config/opencode, and nothing in ~/.claude" || bad OC2 "rc=$rc: $(find "$H" -maxdepth 3 | head -20 | tr '\n' ' ')"
same "OC2 the rules section is AGENTS.md" "$H/$OC/AGENTS.md" "$SEC"
printf '%s\n' "$out" | grep -qi 'warning' && bad OC2 "unexpected warning: $(printf '%s' "$out" | grep -i -m1 warning)" || ok "OC2 no warning on a clean install"
P="$T/oc-proj"; rm -rf "$P"; mkdir -p "$P"; H=$(ohome oc2); out=$(cd "$P" && inst "$H" "" --target opencode --project); rc=$?
[ $rc = 0 ] && [ "$(ls "$P/.opencode/agents" | wc -l | tr -d ' ')" = 3 ] && [ "$(ls "$P/.opencode/skills" | wc -l | tr -d ' ')" = 6 ] && [ ! -e "$P/.claude" ] && [ ! -e "$H/.config" ] && ok "OC2 --project installs under ./.opencode, and nothing in HOME or ./.claude" || bad OC2 "rc=$rc: $(find "$P" -maxdepth 2 | head -12 | tr '\n' ' ')"
same "OC2 --project puts the section in ./AGENTS.md" "$P/AGENTS.md" "$SEC"
# the converted agents
H=$(ohome oc3); inst "$H" "" --target opencode >/dev/null; A="$H/$OC/agents"
for n in scout critic smith; do
  f="$A/$n.md"; miss=""
  grep -qx 'mode: subagent' "$f" || miss="$miss [mode]"
  grep -q '^description: "' "$f" || miss="$miss [description]"
  if grep -qE '^(effort|skills|tools|name):' "$f"; then miss="$miss [source-only key left]"; fi
  grep -qE '^color: "#[0-9a-f]{6}"$' "$f" || miss="$miss [color]"
  [ "$(grep -c '^  - action: ' "$f")" = 2 ] || miss="$miss [rule count]"
  [ -z "$miss" ] && ok "OC3 converted $n has mode, description, hex color and two permission rules, and no Claude-only keys" || bad "OC3 $n" "$miss"
done
grep -qx 'model: anthropic/claude-haiku-5-5' "$A/scout.md" && grep -qx 'model: anthropic/claude-sonnet-5-5' "$A/critic.md" && grep -qx 'model: anthropic/claude-sonnet-5-5' "$A/smith.md" && ok "OC3 models map to anthropic/claude-*-5-5" || bad OC3 "models: $(grep -h '^model:' "$A"/*.md | tr '\n' ' ')"
# perm <file> <action>: the effect of that action's rule
perm() { awk -v a="$2" '$0 == "  - action: " a { getline; getline; print $2 }' "$1"; }
[ "$(perm "$A/scout.md" write)$(perm "$A/scout.md" edit)$(perm "$A/critic.md" write)$(perm "$A/critic.md" edit)" = denydenydenydeny ] && ok "OC3 scout and critic deny write and edit" || bad OC3 "scout/critic permissions"
[ "$(perm "$A/smith.md" write)$(perm "$A/smith.md" edit)" = allowallow ] && ok "OC3 smith allows write and edit" || bad OC3 "smith permissions"
[ "$(grep -l 'load the `tdd` skill' "$A"/*.md | xargs -n1 basename)" = smith.md ] && tail -1 "$A/smith.md" | grep -qx 'Before writing code, load the `tdd` skill and follow it.' && ok "OC3 only smith's body tells it to load tdd, as its last line" || bad OC3 "tdd line"
# scout and critic have no skills, so their body after the frontmatter is the source's
miss=""
for n in scout critic; do
  [ "$(sed '1,/^---$/d' "$PKG/agents/$n.md")" = "$(sed '1,/^---$/d' "$A/$n.md")" ] || miss="$miss $n"
done
[ -z "$miss" ] && ok "OC3 scout and critic bodies are unchanged" || bad OC3 "body differs:$miss"
H=$(ohome oc3b); CONF_MODEL_HAIKU=acme/fast HOME="$H" TMPDIR="$T/tmp" bash "$PKG/install.sh" --target opencode >/dev/null 2>&1
grep -qx 'model: acme/fast' "$H/$OC/agents/scout.md" && grep -qx 'model: anthropic/claude-sonnet-5-5' "$H/$OC/agents/critic.md" && ok "OC3 CONF_MODEL_HAIKU changes only the haiku agent's model" || bad OC3 "override: $(grep -h '^model:' "$H/$OC/agents"/*.md | tr '\n' ' ')"
# skills, rules and re-runs
H=$(ohome oc4); inst "$H" "" --target opencode >/dev/null; miss=""
for d in "$PKG"/skills/*/; do diff -rq "$d" "$H/$OC/skills/$(basename "$d")" >/dev/null || miss="$miss $(basename "$d")"; done
[ -z "$miss" ] && ok "OC4 every installed skill folder matches the source" || bad OC4 "differ:$miss"
# the installed tree has no Claude-only tool name outside the "when it's available" wording
h=$(grep -rh 'AskUserQuestion' "$H/$OC" | grep -v "AskUserQuestion when it's available" | head -1)
[ -z "$h" ] && ok "OC4 AskUserQuestion appears in the opencode install only as 'when it's available'" || bad OC4 "$h"
out=$(inst "$H" "" --target opencode); [ "$(printf '%s\n' "$out" | grep -c '^unchanged')" = 10 ] && [ "$(printf '%s\n' "$out" | grep -cE '^(installed|replaced|updated|appended|created|removed|warning)')" = 0 ] && ok "OC6 a second run reports 10 unchanged and nothing else" || bad OC6 "rerun: $(printf '%s' "$out" | grep -vE '^(unchanged|Target|Agents|AGENTS|$|Done)' | head -3)"
H=$(ohome oc5); a=$(treesum "$H"); out=$(inst "$H" "" --target opencode --dry-run)
[ "$a" = "$(treesum "$H")" ] && printf '%s\n' "$out" | grep -q '^would install  *agents/scout.md$' && printf '%s\n' "$out" | grep -q '^would create ' && ok "OC5 --dry-run writes nothing and says what it would install" || bad OC5 "dry run: $(printf '%s' "$out" | head -8 | tr '\n' '|')"
H=$(ohome oc5b); mkdir -p "$H/$OC"; printf '# Mine\n' > "$H/$OC/AGENTS.md"; out=$(inst "$H" "" --target opencode --dry-run)
printf '%s\n' "$out" | grep -q '^would append ' && printf '%s\n' "$out" | grep -q '^    +## Claude Code subagents$' && ok "OC5 --dry-run shows an AGENTS.md diff" || bad OC5 "no diff: $(printf '%s' "$out" | grep -m2 'append\|+##')"
H=$(ohome oc7); mkdir -p "$H/$OC"; printf 'before\n\n%s\n\nafter\n' "$OLD" > "$H/$OC/AGENTS.md"; inst "$H" "" --target opencode >/dev/null
same "OC7 an AGENTS.md section is replaced and the user's lines before and after it are kept" "$H/$OC/AGENTS.md" "$(printf 'before\n\n%s\n\nafter' "$SEC")"
H=$(ohome oc7b); mkdir -p "$H/.claude"; printf '%s\n' "$SEC" > "$H/.claude/CLAUDE.md"; printf '{"enabledPlugins":{"superpowers@x":true}}\n' > "$H/.claude/settings.json"
out=$(inst "$H" "" --target opencode); if printf '%s\n' "$out" | grep -qi 'warning'; then bad OC7 "a Claude-only warning: $(printf '%s' "$out" | grep -i -m1 warning)"; else ok "OC7 no Claude CLAUDE.md or superpowers warnings for opencode"; fi
if [ -n "$old" ]; then
  H=$(ohome oc8); inst "$H" "" --target opencode >/dev/null; mkdir -p "$H/$OC/skills/scout"; git -C "$PKG" show "$old:skills/scout/SKILL.md" > "$H/$OC/skills/scout/SKILL.md"
  out=$(inst "$H" "" --target opencode); [ ! -e "$H/$OC/skills/scout" ] && printf '%s\n' "$out" | grep -q '^removed .*skills/scout' && ok "OC8 an unedited dropped skill is removed from the opencode skills folder" || bad OC8 "scout kept: $(printf '%s' "$out" | grep -m1 scout)"
else
  echo "skip OC8 dropped skill in the opencode folder (needs git and the package's history)"
fi
# an agent that can't be converted stops the install before anything is written
rm -rf "$T/pkg-badkey"; cp -R "$PKG" "$T/pkg-badkey"
awk '{ print } /^color: / { print "bogus: 1" }' "$PKG/agents/critic.md" > "$T/pkg-badkey/agents/critic.md"
H=$(ohome oc9); a=$(treesum "$H"); out=$(inst "$H" "$T/pkg-badkey" --target opencode); rc=$?
[ $rc = 1 ] && [ "$a" = "$(treesum "$H")" ] && printf '%s' "$out" | grep -q 'unknown frontmatter key "bogus"' && printf '%s' "$out" | grep -q 'Nothing was changed' && ok "OC9 an unknown agent frontmatter key is refused, nothing written" || bad OC9 "rc=$rc: $out"
# CLAUDE.md fallback: OpenCode reads CLAUDE.md in a scope only when that scope has no AGENTS.md
P="$T/oc-fb"; rm -rf "$P"; mkdir -p "$P"; printf '%s\n' "$SEC" > "$P/CLAUDE.md"; H=$(ohome oc10)
out=$(cd "$P" && inst "$H" "" --target opencode)
printf '%s\n' "$out" | grep -q "^warning .*/oc-fb/CLAUDE.md also has the .*OpenCode loads both" && ok "OC13 a global install warns about ./CLAUDE.md with the section and no ./AGENTS.md" || bad OC13 "no warning: $(printf '%s' "$out" | grep -i warning)"
printf '# Mine\n' > "$P/AGENTS.md"; H=$(ohome oc10b); out=$(cd "$P" && inst "$H" "" --target opencode)
printf '%s\n' "$out" | grep -qi 'warning' && bad OC13 "warned though ./AGENTS.md exists: $(printf '%s' "$out" | grep -i warning)" || ok "OC13 no warning when ./AGENTS.md exists in the same scope"
P="$T/oc-fb2"; rm -rf "$P"; mkdir -p "$P"; H=$(ohome oc10c); mkdir -p "$H/.claude"; printf '%s\n' "$SEC" > "$H/.claude/CLAUDE.md"
out=$(cd "$P" && inst "$H" "" --target opencode --project)
printf '%s\n' "$out" | grep -q "^warning .*/oc10c/.claude/CLAUDE.md also has the .*OpenCode loads both" && ok "OC13 --project warns about ~/.claude/CLAUDE.md with the section and no global AGENTS.md" || bad OC13 "no warning: $(printf '%s' "$out" | grep -i warning)"
H=$(ohome oc10d); mkdir -p "$H/.claude" "$H/$OC"; printf '%s\n' "$SEC" > "$H/.claude/CLAUDE.md"; printf '# Mine\n' > "$H/$OC/AGENTS.md"
out=$(cd "$P" && inst "$H" "" --target opencode --project)
printf '%s\n' "$out" | grep -qi 'warning' && bad OC13 "warned though the global AGENTS.md exists: $(printf '%s' "$out" | grep -i warning)" || ok "OC13 --project: no warning when the global AGENTS.md exists"
# the warning doesn't suggest a command that wouldn't update the file, and ./.claude/CLAUDE.md isn't a fallback
P="$T/oc-fb3"; rm -rf "$P"; mkdir -p "$P/.claude"; printf '%s\n' "$SEC" > "$P/.claude/CLAUDE.md"; H=$(ohome oc10e)
out=$(cd "$P" && inst "$H" "" --target opencode)
printf '%s\n' "$out" | grep -qi 'warning' && bad OC13 "warned about ./.claude/CLAUDE.md, which OpenCode doesn't read: $(printf '%s' "$out" | grep -i warning)" || ok "OC13 ./.claude/CLAUDE.md is not treated as an OpenCode fallback"
out=$(cd "$T/oc-fb" 2>/dev/null && rm -f AGENTS.md && inst "$(ohome oc10f)" "" --target opencode)
printf '%s\n' "$out" | grep -q 'OpenCode loads both' && ! printf '%s\n' "$out" | grep -q 'to update it' && ok "OC13 the opencode warning doesn't say 'run ... to update it'" || bad OC13 "wording: $(printf '%s' "$out" | grep -i warning)"
# agent description forms
badpkg() { rm -rf "$T/pkg-$1"; cp -R "$PKG" "$T/pkg-$1"; }
badpkg sq; awk '/^description:/ { print "description: '"'"'It'"''"'s a test: ok'"'"'"; next } { print }' "$PKG/agents/critic.md" > "$T/pkg-sq/agents/critic.md"
H=$(ohome oc11); out=$(inst "$H" "$T/pkg-sq" --target opencode); rc=$?
[ $rc = 0 ] && grep -qxF 'description: "It'"'"'s a test: ok"' "$H/$OC/agents/critic.md" && ok "OC14 a single-quoted description is unquoted and '' becomes '" || bad OC14 "rc=$rc: $(grep -m1 '^description' "$H/$OC/agents/critic.md")"
for form in '>' '|' '"x"' '[a]'; do
  badpkg df; awk -v f="$form" '/^description:/ { print "description: " f; next } { print }' "$PKG/agents/critic.md" > "$T/pkg-df/agents/critic.md"
  H=$(ohome oc12); a=$(treesum "$H"); out=$(inst "$H" "$T/pkg-df" --target opencode); rc=$?
  [ $rc = 1 ] && [ "$a" = "$(treesum "$H")" ] && printf '%s' "$out" | grep -q 'unsupported description form' && printf '%s' "$out" | grep -q 'Nothing was changed' && ok "OC14 description starting with $form is refused, nothing written" || bad "OC14 $form" "rc=$rc: $out"
done
for key in model color; do
  badpkg mk; awk -v k="$key" '$0 ~ "^" k ":" { next } { print }' "$PKG/agents/critic.md" > "$T/pkg-mk/agents/critic.md"
  H=$(ohome oc13); out=$(inst "$H" "$T/pkg-mk" --target opencode); rc=$?
  [ $rc = 1 ] && printf '%s' "$out" | grep -q "missing $key" && ok "OC14 an agent with no $key says 'missing $key'" || bad "OC14 $key" "rc=$rc: $out"
done
grep -q -- '--target opencode' "$PKG/README.md" && grep -q '^### OpenCode$' "$PKG/README.md" && ok "OC12 the README documents the OpenCode target" || bad OC12 "README has no OpenCode section"
[ ! -e "$PKG/opencode" ] && ok "OC11 the package keeps one copy of each agent (no opencode/ folder)" || bad OC11 "opencode/ exists"

cd "$PKG" || exit 1
echo
echo "passed $PASS, failed $FAIL"
if [ "$FAIL" = 0 ] && [ -z "${KEEP:-}" ]; then rm -rf "$T"; else echo "Test files kept in $T"; fi
[ "$FAIL" = 0 ]
