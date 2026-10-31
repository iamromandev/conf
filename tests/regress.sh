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
[ "$(ls "$H/.claude/agents" | wc -l | tr -d ' ')" = 3 ] && [ "$(ls "$H/.claude/skills" | wc -l | tr -d ' ')" = 10 ] && ok "B1 fresh install copies 3 agents, 10 skills" || bad B1 "missing files"
same "B1 fresh CLAUDE.md is the section" "$H/.claude/CLAUDE.md" "$SEC"
out=$(inst "$H"); [ "$(printf '%s\n' "$out" | grep -c '^unchanged')" = 14 ] && ok "B1 rerun reports 14 unchanged" || bad B1 "rerun: $(printf '%s' "$out" | head -3)"
H=$(newhome b2); put "$H" '# Mine\n\n%s\n' "$OLD"
mkdir -p "$H/.claude/agents"; printf 'my edit\n' > "$H/.claude/agents/critic.md"
a=$(treesum "$H"); out=$(inst "$H" "" --dry-run); [ "$a" = "$(treesum "$H")" ] && ok "B2 --dry-run changes nothing" || bad B2 "tree changed"
printf '%s\n' "$out" | grep -q '^would replace  *agents/critic.md$' && ok "B2 --dry-run says it would replace a changed agent" || bad B2 "no 'would replace' line: $(printf '%s' "$out" | grep -m1 critic)"
H=$(newhome b6); out=$(cd "$H" && inst "$H" "" --project); rc=$?; [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "home folder" && ok "B6 --project refused in HOME (exit $rc)" || bad B6 "not refused in HOME (exit $rc)"
out=$(cd "$PKG" && inst "$H" "" --project); rc=$?; [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "that's the conf package itself" && ok "B6 --project refused in package (exit $rc)" || bad B6 "not refused in package (exit $rc)"
H=$(newhome b7); put "$H" 'abc'; inst "$H" >/dev/null
same "B7 append after a file with no final newline" "$H/.claude/CLAUDE.md" "$(printf 'abc\n\n%s' "$SEC")"; idem B7 "$H"
H=$(newhome b8); mkdir -p "$H/.claude/agents" "$H/.claude/skills/check"; printf 'my edit\n' > "$H/.claude/agents/critic.md"; printf 'my skill edit\n' > "$H/.claude/skills/check/SKILL.md"; printf 'mine\n' > "$H/.claude/skills/check/extra.md"
chmod a-w "$H/.claude/agents/critic.md"; out=$(inst "$H")
cmp -s "$PKG/agents/critic.md" "$H/.claude/agents/critic.md" && printf '%s' "$out" | grep -q '^replaced       agents/critic.md$' && ok "B8 a changed agent is replaced in place, even if it's read-only" || bad B8 "not replaced: $(printf '%s' "$out" | grep -m1 critic)"
diff -rq "$PKG/skills/check" "$H/.claude/skills/check" >/dev/null && printf '%s' "$out" | grep -q '^replaced       skills/check$' && ok "B8 a changed skill folder is replaced whole, extra files included" || bad B8 "skill not replaced: $(printf '%s' "$out" | grep -m1 skills/check)"
if ls -d "$H"/.claude/conf-backup-* >/dev/null 2>&1 || printf '%s' "$out" | grep -qi 'backup'; then bad B8 "a backup was made: $(ls "$H/.claude")"; else ok "B8 nothing is backed up"; fi
if [ "$(id -u)" != 0 ]; then
  H=$(newhome b10); mkdir -p "$H/.claude/skills/check"; printf 'my skill edit\n' > "$H/.claude/skills/check/SKILL.md"; chmod -R a-w "$H/.claude/skills/check"; out=$(inst "$H"); rc=$?; chmod -R u+w "$H/.claude/skills"
  [ $rc = 0 ] && diff -rq "$PKG/skills/check" "$H/.claude/skills/check" >/dev/null && ok "B10 a read-only skill folder is replaced too" || bad B10 "rc=$rc $(printf '%s' "$out" | grep -m1 -i 'rm:\|error')"
else
  echo "skip B10 read-only skill folder (running as root)"
fi
H=$(newhome b11); mkdir -p "$T/b11-mine" "$H/.claude/skills"; printf 'keep\n' > "$T/b11-mine/KEEP"; ln -s "$T/b11-mine" "$H/.claude/skills/check"; inst "$H" >/dev/null
[ ! -L "$H/.claude/skills/check" ] && diff -rq "$PKG/skills/check" "$H/.claude/skills/check" >/dev/null && [ "$(ls "$T/b11-mine")" = KEEP ] && ok "B11 a symlinked skill folder is replaced by a copy, the folder it pointed to untouched" || bad B11 "link=$([ -L "$H/.claude/skills/check" ] && echo yes || echo no) target=$(ls "$T/b11-mine" | tr '\n' ' ')"
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
for s in 'Run the `check` skill' '^## Branch' '<short-kebab-name>' '^## Commit' 'Conventional Commits' '^## PR' 'Closes #<issue>' '^## Merge' 'squash if more' '^## After merging' 'remote and local branch' 'link to the merged PR'; do grep -q -- "$s" "$g" 2>/dev/null || missing="$missing [ship: $s]"; done
[ -z "$missing" ] && ok "Q8 the git rules (branch, commit, PR, merge, cleanup, issue update) are in the ship skill, and CLAUDE.md only says to use it when asked" || bad Q8 "missing:$missing"
grep '^- Non-trivial change' "$PKG/CLAUDE.md" | grep -q '`tdd`' && grep '^- Something broken' "$PKG/CLAUDE.md" | grep -q '`tdd`' && ok "Q9 the non-trivial and bug-fix routes in CLAUDE.md name tdd" || bad Q9 "tdd missing from a route"
a="$PKG/agents"; grep -qx 'model: sonnet' "$a/critic.md" && grep -qx 'effort: high' "$a/critic.md" && grep -qx 'model: haiku' "$a/scout.md" && grep -qx 'effort: low' "$a/scout.md" \
  && grep -qx 'model: sonnet' "$a/smith.md" && grep -qx 'effort: medium' "$a/smith.md" \
  && grep -q '^| `critic` | sonnet | high |' "$PKG/README.md" && grep -q '^| `scout` | haiku | low |' "$PKG/README.md" && grep -q '^| `smith` | sonnet | medium |' "$PKG/README.md" \
  && ok "Q10 critic is sonnet/high, scout haiku/low and smith sonnet/medium, in the agents and README" || bad Q10 "model or effort differs"
# (bracketed so this line doesn't match itself)
legacy='old-[s]ections|spec-[w]riter|[s]pecifier|[p]lanner|[b]uilder|[r]etire|claude-[c]onf|[r]eviewer|[e]xplorer|`[b]uild`'
hits=$(cd "$PKG" && grep -nE "$legacy|[b]uild (report|skill)" README.md install.sh tests/regress.sh CLAUDE.md skills/*/SKILL.md)
# The agents only get the build checks: critic's prompt names its role (code review) with a word on the list above
hits="$hits$(cd "$PKG" && grep -nE '`[b]uild`|[b]uild (report|skill)' agents/*.md)"
[ -z "$hits" ] && ok "Q11 no earlier names or upgrade paths are left" || bad Q11 "$(printf '%s' "$hits" | head -3 | cut -c1-80)"
for n in critic scout smith; do
  s="$PKG/skills/$n/SKILL.md"; fm=$(sed -n '2,/^---$/p' "$s" 2>/dev/null); missing=""
  [ -f "$PKG/agents/$n.md" ] || missing="$missing [no agents/$n.md]"
  [ "$(sed -n 1p "$s" 2>/dev/null)" = '---' ] && [ "$(printf '%s\n' "$fm" | tail -n 1)" = '---' ] || missing="$missing [frontmatter between --- lines]"
  for l in 'context: fork' "agent: $n" 'background: false' 'disable-model-invocation: true'; do printf '%s\n' "$fm" | grep -qx "$l" || missing="$missing [$l]"; done
  printf '%s\n' "$fm" | grep -qE '^(model|effort):' && missing="$missing [sets model or effort]"
  sed '1,/^---$/d' "$s" 2>/dev/null | grep -q '\$ARGUMENTS' || missing="$missing [\$ARGUMENTS in the body]"
  [ -z "$missing" ] && ok "Q12 /$n starts the $n agent: forked, waited for, run only by you, at the agent's model and effort" || bad Q12 "skills/$n/SKILL.md:$missing"
done
grep '^- Mechanical changes' "$PKG/CLAUDE.md" | grep '`blueprint`' | grep '`critic`' | grep 'logic, security, auth or data' | grep -q 'keeps the meaning' && ok "Q13 mechanical changes skip blueprint and critic, unless they touch logic, security, auth or data" || bad Q13 "no mechanical-changes route with its limits"
s="$PKG/agents/smith.md"; fm=$(sed -n '2,/^---$/p' "$s" 2>/dev/null); missing=""
for t in Edit Write Bash; do printf '%s\n' "$fm" | grep '^tools:' | grep -q "$t" || missing="$missing [tools: $t]"; done
printf '%s\n' "$fm" | grep -A3 -x 'skills:' | grep -qx '  - tdd' || missing="$missing [skills: - tdd]"
for p in "can't ask the user" 'report Blocked' 'leave the code building' 'files you touched'; do sed '1,/^---$/d' "$s" 2>/dev/null | grep -q "$p" || missing="$missing [$p]"; done
grep '^- Run `spec`' "$PKG/CLAUDE.md" | grep 'continue that same `smith`' | grep -q 'start a new one with the plan, its Blocked report and my answer' || missing="$missing [CLAUDE.md: continue smith, or start a new one]"
[ -z "$missing" ] && ok "Q15 smith can edit and run commands, preloads tdd, and reports Blocked instead of asking, leaving work a new run can pick up" || bad Q15 "agents/smith.md:$missing"

echo
echo "passed $PASS, failed $FAIL"
if [ "$FAIL" = 0 ] && [ -z "${KEEP:-}" ]; then rm -rf "$T"; else echo "Test files kept in $T"; fi
[ "$FAIL" = 0 ]
