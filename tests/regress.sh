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
T="$(mktemp -d "${TMPDIR:-/tmp}/claude-conf-test.XXXXXX")"
mkdir -p "$T/tmp"
cp -R "$PKG_SRC" "$T/pkg"
PKG="$T/pkg"
SEC="$(cat "$PKG/CLAUDE.md")"
MARK='<!-- claude-conf: end of section -->'
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
# refused <case> <home> <expected words> [args]: the run exits 1, says nothing changed, and leaves HOME as it was
refused() {
  local a out rc; a=$(treesum "$2"); out=$(inst "$2" "" ${4:-}); rc=$?
  if [ $rc = 1 ] && [ "$a" = "$(treesum "$2")" ] && printf '%s' "$out" | grep -q "$3" && printf '%s' "$out" | grep -q 'Nothing was changed'; then ok "$1"
  else bad "$1" "rc=$rc, changed=$([ "$a" = "$(treesum "$2")" ] && echo no || echo yes), output: $(printf '%s' "$out" | grep -m1 -i 'error\|warning')"; fi
}

echo "== Installing and re-running"
H=$(newhome b1); rmdir "$H/.claude"; inst "$H" >/dev/null
[ "$(ls "$H/.claude/agents" | wc -l | tr -d ' ')" = 5 ] && [ "$(ls "$H/.claude/skills" | wc -l | tr -d ' ')" = 4 ] && ok "B1 fresh install copies 5 agents, 4 skills" || bad B1 "missing files"
same "B1 fresh CLAUDE.md is the section" "$H/.claude/CLAUDE.md" "$SEC"
out=$(inst "$H"); [ "$(printf '%s\n' "$out" | grep -c '^unchanged')" = 10 ] && ok "B1 rerun reports 10 unchanged" || bad B1 "rerun: $(printf '%s' "$out" | head -3)"

H=$(newhome b2); printf '# Mine\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; mkdir -p "$H/.claude/agents"; printf -- '---\nname: Plan\n---\n' > "$H/.claude/agents/plan.md"
a=$(treesum "$H"); inst "$H" "" --dry-run >/dev/null; [ "$a" = "$(treesum "$H")" ] && ok "B2 --dry-run changes nothing" || bad B2 "tree changed"

H=$(newhome b3); printf '# Mine\n\nstuff\n\n## Claude Code subagents\n\n- old\n\n## Other\n\nkeep\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "B3 mid-file section replaced, rest kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\nstuff\n\n%s\n\n## Other\n\nkeep' "$SEC")"; idem B3 "$H"

H=$(newhome b4); printf '# Mine\n\n```md\n## Claude Code subagents\n- example\n```\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "B4 fenced example heading left alone, section appended" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```md\n## Claude Code subagents\n- example\n```\n\n%s' "$SEC")"; idem B4 "$H"

H=$(newhome b5); printf '# Mine\r\n\r\n## Claude Code subagents\r\n\r\n- old\r\n\r\n## Other\r\nkeep\r\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
f="$H/.claude/CLAUDE.md"; lines=$(wc -l < "$f" | tr -d ' '); crs=$(grep -c $'\r$' "$f"); dbl=$(grep -c $'\r\r' "$f")
[ "$lines" = "$crs" ] && [ "$dbl" = 0 ] && [ "$(heads "$f")" = 1 ] && ! grep -q '^- old' "$f" && ok "B5 CRLF target stays CRLF, section replaced" || bad B5 "lines=$lines cr=$crs dbl=$dbl heads=$(heads "$f")"; idem B5 "$H"

H=$(newhome b6); out=$(cd "$H" && inst "$H" "" --project); rc=$?; [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "home folder" && ok "B6 --project refused in HOME (exit $rc)" || bad B6 "not refused in HOME (exit $rc)"
out=$(cd "$PKG" && inst "$H" "" --project); rc=$?; [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "claude-conf package itself" && ok "B6 --project refused in package (exit $rc)" || bad B6 "not refused in package (exit $rc)"

H=$(newhome b7); printf 'abc' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "B7 append after a file with no final newline" "$H/.claude/CLAUDE.md" "$(printf 'abc\n\n%s' "$SEC")"; idem B7 "$H"

H=$(newhome b8); mkdir -p "$H/.claude/agents" "$H/.claude/skills/brainstorming"; printf -- '---\nname: Plan\ndescription: x\n---\nbody\n' > "$H/.claude/agents/plan.md"; printf -- '---\nname: brainstorming\n---\n' > "$H/.claude/skills/brainstorming/SKILL.md"
inst "$H" >/dev/null; [ ! -e "$H/.claude/agents/plan.md" ] && [ ! -e "$H/.claude/skills/brainstorming" ] && ls "$H"/.claude/claude-conf-backup-*/agents/plan.md >/dev/null 2>&1 && ok "B8 old claude-conf agent and skill retired to backup" || bad B8 "not retired"

H=$(newhome b9); printf '# Mine\n\n## Claude Code subagents\n\n- old\n\n---\n\nafter rule\n\n# Top\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "B9 section ends at a --- line" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s\n\n---\n\nafter rule\n\n# Top' "$SEC")"

echo "== Code blocks around the section"
H=$(newhome f1); printf '# Mine\n\n```bash\nx\n~~~ y\n```\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "F1 ~~~ inside a \`\`\` block doesn't hide the real section" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```bash\nx\n~~~ y\n```\n\n%s' "$SEC")"; idem F1 "$H"

H=$(newhome f2); printf '# Mine\n\n```npm test``` runs the tests.\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null; inst "$H" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(heads "$f")" = 1 ] && ok "F2 a line starting with inline code isn't a fence" || bad F2 "headings after 2 runs: $(heads "$f")"; idem F2 "$H"
H=$(newhome f2b); printf '# Mine\n\n```npm test``` runs the tests.\n\n## Claude Code subagents\n\n- old\n\n## Build\n\n```bash\nmake\n```\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "F2b inline-code line, real section and a later block: replaced in place" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```npm test``` runs the tests.\n\n%s\n\n## Build\n\n```bash\nmake\n```' "$SEC")"; idem F2b "$H"

H=$(newhome f3); printf '# Mine\n\n````md\n```\n## Claude Code subagents\n```\n````\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "F3 \`\`\` inside a \`\`\`\` block doesn't close it" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n````md\n```\n## Claude Code subagents\n```\n````\n\n%s' "$SEC")"; idem F3 "$H"

H=$(newhome f4); printf '## Claude Code subagents\n\n- old\n```\n~~~\n## not a heading (in code)\n```\n\n## Other\nkeep\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "F4 a code block after the old section is kept whole" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n```\n~~~\n## not a heading (in code)\n```\n\n## Other\nkeep' "$SEC")"; idem F4 "$H"

H=$(newhome f5); printf '# Mine\n\n```text\nheading example\n~~~~\n```\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(heads "$f")" = 1 ] && ! grep -q '^- old' "$f" && ok "F5 longer ~~~~ inside a \`\`\` block doesn't close it" || bad F5 "heads=$(heads "$f")"

H=$(newhome f6); printf '# Mine\n\n~~~ `md`\n## Claude Code subagents\n- example\n~~~\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "F6 ~~~ with backticks in its info string still opens a block" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n~~~ `md`\n## Claude Code subagents\n- example\n~~~\n\n%s' "$SEC")"
H=$(newhome f7); printf '# Mine\n\n```md\n## Claude Code subagents\n- example\n```  \n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "F7 closing fence with trailing spaces closes the block" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```md\n## Claude Code subagents\n- example\n```  \n\n%s' "$SEC")"

echo "== Nested and mistyped fences, code after the section"
NEST='# Notes\nExample doc:\n```md\nRun this:\n```bash\nnpm test\n```\n```\n\n'
H=$(newhome n1); printf "$NEST"'## Claude Code subagents\n- old\n## Commands\n```bash\nnpm run build\n```\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "N1 naively nested example before the section: replaced in place" "$H/.claude/CLAUDE.md" "$(printf "$NEST"'%s\n\n## Commands\n```bash\nnpm run build\n```' "$SEC")"; idem N1 "$H"
H=$(newhome n2); printf '# Mine\n```bash\nnpm test\n```bash\n\n## Claude Code subagents\n- old\n## Commands\n```sh\nx\n```\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(heads "$f")" = 1 ] && ! grep -q '^- old' "$f" && grep -q '^## Commands' "$f" && ok "N2 closer typed with an info string: replaced in place" || bad N2 "heads=$(heads "$f")"; idem N2 "$H"
H=$(newhome n3); printf '# T\n## Claude Code subagents\n- old\n\nExample:\n```md\n```bash\nx\n```\n```\n\n## Notes\nmy notes\n\n## Build\n```js\ny\n```\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "N3 naive nesting after the section: nothing after it is deleted" "$H/.claude/CLAUDE.md" "$(printf '# T\n%s\n\n```md\n```bash\nx\n```\n```\n\n## Notes\nmy notes\n\n## Build\n```js\ny\n```' "$SEC")"; idem N3 "$H"
H=$(newhome n4); printf '# Notes\n## Claude Code subagents\n- old\n## Notes2\n```md\n## Claude Code subagents\n- example\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "N4 unclosed example at the end after the real section is kept" "$H/.claude/CLAUDE.md" "$(printf '# Notes\n%s\n\n## Notes2\n```md\n## Claude Code subagents\n- example' "$SEC")"
H=$(newhome n5); printf '# Mine\n## Claude Code subagents\n- old\n```bash\n# build it\nmake\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "N5 unclosed block inside the old section is kept intact" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n%s\n\n```bash\n# build it\nmake' "$SEC")"; idem N5 "$H"
H=$(newhome n6); printf '# Mine\n````md\n## Claude Code subagents\n- example\n```\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"
refused "N6 heading only after an unclosed block: refused, names line 2, nothing installed" "$H" "starts on line 2 is never closed"
H=$(newhome n7); printf '# Mine\n\n```bash\nx\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"
refused "N7 stray fence before the section: refused" "$H" "never closed"; refused "N7 (again)" "$H" "never closed"
H=$(newhome n8); printf '# Mine\n\n```bash\nx\n' > "$H/.claude/CLAUDE.md"
refused "N8 stray fence, no section: refused in a dry run too" "$H" "never closed" --dry-run; refused "N8 (real run)" "$H" "never closed"
H=$(newhome n9); printf '# Mine\n\n```md\n## Claude Code subagents\n- example\n```\n\n## Claude Code subagents\n\n- old\n\n```\nstray\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "N9 closed example kept, real section replaced, stray block after it kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```md\n## Claude Code subagents\n- example\n```\n\n%s\n\n```\nstray' "$SEC")"; idem N9 "$H"

echo "== Fence lines that can be read two ways"
H=$(newhome a1); printf '## Claude Code subagents\n\n- old rule\n\n## Team setup\n\n```md\nPaste this into CLAUDE.md:\n```markdown\n## Claude Code subagents\n- my team rule\n```\n```\n' > "$H/.claude/CLAUDE.md"
refused "A1 real section, plus the heading inside a naively nested example: refused, names line 10" "$H" "around line 10 can be read two ways"
H=$(newhome a2); printf '# Team\n\n```md\nPaste this:\n```markdown\n## Claude Code subagents\n- team example rule\n```\n```\n\n## Claude Code subagents\n\n- old rule\n' > "$H/.claude/CLAUDE.md"
refused "A2 heading inside a nested example before the real one: refused" "$H" "can be read two ways"
H=$(newhome a3); printf '# Mine\n```bash\nnpm test\n```bash\n\n## Claude Code subagents\n- old\n## Commands\n```sh\nx\n```\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "A3 closer typo, only one reading closes every block: that one is used" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n```bash\nnpm test\n```bash\n\n%s\n\n## Commands\n```sh\nx\n```' "$SEC")"; idem A3 "$H"
H=$(newhome a4); printf '# Mine\n```bash\nnpm test\n```bash\n\n## Claude Code subagents\n- old\n## Commands\n```\nx\n```\n' > "$H/.claude/CLAUDE.md"
refused "A4 closer typo where both readings close every block: refused" "$H" "can be read two ways"
H=$(newhome a5); printf '# Mine\n\n```md\n```npm test``` runs the tests\n## Claude Code subagents\n- example\n```\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "A5 inline code inside a block doesn't close it" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n```md\n```npm test``` runs the tests\n## Claude Code subagents\n- example\n```\n\n%s' "$SEC")"
H=$(newhome a6); printf '## Claude Code subagents\n- old\n\n## Notes\n```md\n```npm test``` runs the tests\n## Claude Code subagents\n- example\n```\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "A6 an example after the real section isn't cut short" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n## Notes\n```md\n```npm test``` runs the tests\n## Claude Code subagents\n- example\n```' "$SEC")"
H=$(newhome a7); printf '1. Run:\n   ```bash\n   make\n   ```\n- Or:\n    ```bash\n    x\n    ```\n\n## Claude Code subagents\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "A7 fences indented in lists (3 and 4 spaces)" "$H/.claude/CLAUDE.md" "$(printf '1. Run:\n   ```bash\n   make\n   ```\n- Or:\n    ```bash\n    x\n    ```\n\n%s' "$SEC")"

echo "== The end-of-section comment"
[ "$(tail -1 "$PKG/CLAUDE.md")" = "$MARK" ] && ok "M0 the package section ends with the end-of-section comment" || bad M0 "no end marker"
H=$(newhome m1); printf '# Mine\n\n## Claude Code subagents\n\n- old\n%s\n- Use pnpm, never npm.\n@docs/conventions.md\n' "$MARK" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "M1 bullets and @imports right after the end comment are kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s\n- Use pnpm, never npm.\n@docs/conventions.md' "$SEC")"; idem M1 "$H"
H=$(newhome m2); rmdir "$H/.claude"; inst "$H" >/dev/null; printf -- '- Added later by Claude.\n' >> "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "M2 a line appended after a fresh install survives the next run" "$H/.claude/CLAUDE.md" "$(printf '%s\n- Added later by Claude.' "$SEC")"
H=$(newhome m3); printf '# Mine\n\n## Claude Code subagents\n\n- old\n\n### My extra routing\n- Use the db agent for SQL.\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "M3 no end comment yet: a ### subsection after the section is kept" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s\n\n### My extra routing\n- Use the db agent for SQL.' "$SEC")"; idem M3 "$H"
H=$(newhome m4); printf '## Claude Code subagents\n- old\n```md\n%s\n```\nmine\n' "$MARK" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "M4 an end comment inside a code block doesn't count" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n```md\n%s\n```\nmine' "$SEC" "$MARK")"
H=$(newhome m5); printf '## Claude Code subagents\n- old\n%s\nkeep 1\n\n## Claude Code subagents\n- old 2\n%s\nkeep 2\n' "$MARK" "$MARK" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "M5 two marked copies: merged into one, text after each kept" "$H/.claude/CLAUDE.md" "$(printf '%s\nkeep 1\n\nkeep 2' "$SEC")"; idem M5 "$H"
H=$(newhome m6); printf '## Claude Code subagents\n- old\n\n## Next\n- mine\n%s\n' "$MARK" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "M6 an end comment after another heading isn't this section's" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n## Next\n- mine\n%s' "$SEC" "$MARK")"
H=$(newhome m6b); printf '## Claude Code subagents\n- old\n### Mine\n- keep\n%s\n' "$MARK" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "M6b a heading of yours inside a marked section is kept" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n### Mine\n- keep\n%s' "$SEC" "$MARK")"; idem M6b "$H"
H=$(newhome m7); printf '\357\273\277## Claude Code subagents\r\n- old\r\n%s\r\nkeep\r\n' "$MARK" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" = efbbbf ] && [ "$(grep -c "$MARK" "$f")" = 1 ] && grep -q $'^keep\r$' "$f" && [ "$(grep -c $'\r\r' "$f")" = 0 ] && ok "M7 BOM + CRLF with an end comment" || bad M7 "marks=$(grep -c "$MARK" "$f")"; idem M7 "$H"
for t in '# x' '#\tx' '### x' '***' '___' '--- ' '##'; do
  H=$(newhome "mt$(printf '%s' "$t" | cksum | cut -d' ' -f1)"); printf "## Claude Code subagents\n- old\n$t\nmine\n" > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
  same "M8 no end comment: '$t' ends the section and what follows is kept" "$H/.claude/CLAUDE.md" "$(printf "%s\n\n$t\nmine" "$SEC")"
done

echo "== Refusals stop the whole install"
H=$(newhome x1); printf '# Mine\n\n```bash\nx\n' > "$H/.claude/CLAUDE.md"; mkdir -p "$H/.claude/agents"; printf -- '---\nname: Plan\n---\n' > "$H/.claude/agents/plan.md"
refused "X1 nothing is installed or retired when CLAUDE.md is refused" "$H" "never closed"
H=$(newhome x2); out=$(inst "$H"); rc=$?; [ $rc = 0 ] && printf '%s' "$out" | grep -q '^Done' && ok "X2 a normal install still exits 0 and says Done" || bad X2 "rc=$rc"

echo "== Heading variants"
H=$(newhome h1); printf '# Mine\n\n## Claude Code subagents  \n\n- old\n\n## Other\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "H1 heading with trailing spaces is replaced" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s\n\n## Other' "$SEC")"; idem H1 "$H"
H=$(newhome h2); printf '## Claude Code subagents ##\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "H2 heading with closing ## is replaced" "$H/.claude/CLAUDE.md" "$SEC"; idem H2 "$H"
H=$(newhome h3); printf '\357\273\277## Claude Code subagents\n\n- old\n\n## Other\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" = efbbbf ] && [ "$(grep -c 'Claude Code subagents' "$f")" = 1 ] && ! grep -q '^- old' "$f" && ok "H3 BOM before the heading: replaced, BOM kept" || bad H3 "count=$(grep -c 'Claude Code subagents' "$f")"; idem H3 "$H"
H=$(newhome h4); printf '#  Not it\n\n### Claude Code subagents\n\n- keep me\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
f="$H/.claude/CLAUDE.md"; grep -q '^- keep me' "$f" && grep -q '^### Claude Code subagents' "$f" && ok "H4 a ### heading with the same text isn't the section" || bad H4 "### section touched"
H=$(newhome h5); printf '## Claude Code subagents and more\n\n- keep me\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
grep -q '^- keep me' "$H/.claude/CLAUDE.md" && ok "H5 a longer heading isn't the section" || bad H5 "longer heading touched"
H=$(newhome h6); printf '## Claude  Code\tsubagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "H6 extra spaces and a tab inside the heading" "$H/.claude/CLAUDE.md" "$SEC"
H=$(newhome h7); printf '# Mine\n  ## Claude Code subagents\n  - old\n  ## Other\n  keep\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
f="$H/.claude/CLAUDE.md"; grep -q '^  ## Other' "$f" && grep -q '^  keep' "$f" && grep -q '^  - old' "$f" && ok "H7 an indented heading isn't matched, so nothing indented is deleted" || bad H7 "indented content changed"
H=$(newhome h8); printf '## Claude Code subagents\n- old\n##\tMine\nmine\n#\tTop\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null
same "H8 headings with a tab after # end the section" "$H/.claude/CLAUDE.md" "$(printf '%s\n\n##\tMine\nmine\n#\tTop' "$SEC")"

echo "== Windows line endings and byte order marks in the package"
CR="$T/pkgcr"; cp -R "$PKG" "$CR"; awk '{ printf "%s\r\n", $0 }' "$PKG/CLAUDE.md" > "$CR/CLAUDE.md"
H=$(newhome c1); printf '# Mine\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" "$CR" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(grep -c $'\r' "$f")" = 0 ] && ok "C1 CRLF section into an LF file: no CRs" || bad C1 "$(grep -c $'\r' "$f") lines with CR"
a=$(sum "$f"); inst "$H" "$CR" >/dev/null; [ "$a" = "$(sum "$f")" ] && [ "$(heads "$f")" = 1 ] && ok "C1 (idempotent)" || bad "C1 (idempotent)" "heads=$(heads "$f")"
H=$(newhome c2); printf '# Mine\r\n\r\n## Claude Code subagents\r\n\r\n- old\r\n' > "$H/.claude/CLAUDE.md"; inst "$H" "$CR" >/dev/null
f="$H/.claude/CLAUDE.md"; [ "$(grep -c $'\r\r' "$f")" = 0 ] && [ "$(wc -l < "$f" | tr -d ' ')" = "$(grep -c $'\r$' "$f")" ] && ok "C2 CRLF section into a CRLF file: single CRs" || bad C2 "double CRs: $(grep -c $'\r\r' "$f")"
a=$(sum "$f"); inst "$H" "$CR" >/dev/null; [ "$a" = "$(sum "$f")" ] && [ "$(heads "$f")" = 1 ] && ok "C2 (idempotent)" || bad "C2 (idempotent)" "heads=$(heads "$f")"
H=$(newhome c3); rmdir "$H/.claude"; inst "$H" "$CR" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(grep -c $'\r' "$f")" = 0 ] && ok "C3 CRLF section, new CLAUDE.md: no CRs" || bad C3 "$(grep -c $'\r' "$f") lines with CR"
H=$(newhome c4); printf '# Mine\r\n' > "$H/.claude/CLAUDE.md"; inst "$H" "$CR" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(grep -c $'\r\r' "$f")" = 0 ] && [ "$(wc -l < "$f" | tr -d ' ')" = "$(grep -c $'\r$' "$f")" ] && ok "C4 CRLF section appended to a CRLF file: single CRs" || bad C4 "double CRs: $(grep -c $'\r\r' "$f")"
[ -f "$PKG/.gitattributes" ] && grep -q 'eol=lf' "$PKG/.gitattributes" && ok "C5 .gitattributes forces LF" || bad C5 "no .gitattributes with eol=lf"
H=$(newhome c6); printf '# Mine\r\n\r\n## Claude Code subagents\r\r\n- old\r\r\n\r\n## Claude Code subagents\r\r\n- old\r\r\n\r\n## Other\r\n' > "$H/.claude/CLAUDE.md"; inst "$H" >/dev/null; f="$H/.claude/CLAUDE.md"
[ "$(heads "$f")" = 1 ] && [ "$(grep -c $'\r\r' "$f")" = 0 ] && grep -q '^## Other' "$f" && ok "C6 sections with \\r\\r line endings from older versions are repaired and merged" || bad C6 "heads=$(heads "$f") dbl=$(grep -c $'\r\r' "$f")"; idem C6 "$H"
BM="$T/pkgbom"; cp -R "$PKG" "$BM"; { printf '\357\273\277'; cat "$PKG/CLAUDE.md"; } > "$BM/CLAUDE.md"
H=$(newhome c7); printf '# Mine\n\n## Claude Code subagents\n\n- old\n' > "$H/.claude/CLAUDE.md"; inst "$H" "$BM" >/dev/null; inst "$H" "$BM" >/dev/null
same "C7 BOM in the package's CLAUDE.md isn't copied mid-file" "$H/.claude/CLAUDE.md" "$(printf '# Mine\n\n%s' "$SEC")"
H=$(newhome c8); rmdir "$H/.claude"; inst "$H" "$BM" >/dev/null; inst "$H" "$BM" >/dev/null
same "C8 BOM in the package: new CLAUDE.md has none, rerun unchanged" "$H/.claude/CLAUDE.md" "$SEC"

echo "== Retiring old agents and skills"
H=$(newhome r1); mkdir -p "$H/.claude/agents"; printf -- '---\r\nname: Plan\r\ndescription: old\r\n---\r\nbody\r\n' > "$H/.claude/agents/plan.md"; inst "$H" >/dev/null
[ ! -e "$H/.claude/agents/plan.md" ] && ok "R1 CRLF old agent is retired" || bad R1 "left in place"
H=$(newhome r2); mkdir -p "$H/.claude/agents"; printf -- '---\nname: "Explore"\n---\n' > "$H/.claude/agents/explore.md"; inst "$H" >/dev/null
[ ! -e "$H/.claude/agents/explore.md" ] && ok "R2 double-quoted name is retired" || bad R2 "left in place"
H=$(newhome r2b); mkdir -p "$H/.claude/agents"; printf -- "---\nname: 'Explore'\n---\n" > "$H/.claude/agents/explore.md"; inst "$H" >/dev/null
[ ! -e "$H/.claude/agents/explore.md" ] && ok "R2b single-quoted name is retired" || bad R2b "left in place"
H=$(newhome r2c); mkdir -p "$H/.claude/agents"; printf -- '---\nname: review   \n---\n' > "$H/.claude/agents/review.md"; inst "$H" >/dev/null
[ ! -e "$H/.claude/agents/review.md" ] && ok "R2c name with trailing spaces is retired" || bad R2c "left in place"
H=$(newhome r3); mkdir -p "$H/.claude/skills/brainstorming"; printf -- '---\nname: my-ideas\n---\nname: brainstorming\n' > "$H/.claude/skills/brainstorming/SKILL.md"; inst "$H" >/dev/null
[ -e "$H/.claude/skills/brainstorming" ] && ok "R3 name line in the body doesn't count" || bad R3 "retired by a body line"
H=$(newhome r3b); mkdir -p "$H/.claude/agents"; printf -- '---\ndescription: mine\n---\nname: Explore\n' > "$H/.claude/agents/explore.md"; inst "$H" >/dev/null
[ -e "$H/.claude/agents/explore.md" ] && ok "R3b frontmatter without a name, name in the body: left" || bad R3b "retired by a body line"
H=$(newhome r4); mkdir -p "$H/.claude/agents"; printf -- '---\nname: review\n---\nmine\n' > "$H/.claude/agents/review.md"; out=$(inst "$H")
printf '%s' "$out" | grep -q 'next run retires it again' && ok "R4 real run says to rename, since moving back doesn't last" || bad R4 "no rename hint"
H=$(newhome r4b); mkdir -p "$H/.claude/agents"; printf -- '---\nname: review\n---\nmine\n' > "$H/.claude/agents/review.md"; dout=$(inst "$H" "" --dry-run)
printf '%s' "$dout" | grep -q 'rename the file' && ! printf '%s' "$dout" | grep -q 'move it back' && ok "R4b dry run says to rename first, not to move back" || bad R4b "dry-run hint wrong"
H=$(newhome r5); mkdir -p "$H/.claude/agents"; printf -- '---\nname: plan\n---\n' > "$H/.claude/agents/plan.md"; out=$(inst "$H")
[ -e "$H/.claude/agents/plan.md" ] && printf '%s' "$out" | grep -q "its name isn't Plan" && ok "R5 a different name is left alone, and the output says why" || bad R5 "retired or wrong message"
H=$(newhome r6); mkdir -p "$H/.claude/agents"; printf -- '\357\273\277---\nname: Plan\n---\n' > "$H/.claude/agents/plan.md"; inst "$H" >/dev/null
[ ! -e "$H/.claude/agents/plan.md" ] && ok "R6 BOM before the frontmatter: retired" || bad R6 "left in place"
H=$(newhome r7); mkdir -p "$H/.claude/agents"; printf -- '--- \nname: Plan\n---  \n' > "$H/.claude/agents/plan.md"; inst "$H" >/dev/null
[ ! -e "$H/.claude/agents/plan.md" ] && ok "R7 trailing spaces on the --- lines: retired" || bad R7 "left in place"
H=$(newhome r8); out=$(inst "$H"); printf '%s' "$out" | grep -q 'matched by their name' && bad R8 "hint printed with nothing retired" || ok "R8 no retire hint when nothing was retired"

echo "== Finding the section in --project mode"
P=$T/proj1; rm -rf "$P"; mkdir -p "$P/.claude"; H=$(newhome hs1)
printf '# Proj\n\n```md\n## Claude Code subagents\n```\n' > "$P/CLAUDE.md"; printf '## Claude Code subagents\n\n- old\n' > "$P/.claude/CLAUDE.md"; a=$(sum "$P/CLAUDE.md")
(cd "$P" && inst "$H" "" --project >/dev/null)
[ "$a" = "$(sum "$P/CLAUDE.md")" ] && ! grep -q '^- old' "$P/.claude/CLAUDE.md" && ok "S1 --project picks the file with the real section" || bad S1 "wrong file updated"
P=$T/proj2; rm -rf "$P"; mkdir -p "$P"; H=$(newhome hs2); printf '# Proj\n\n```md\n## Claude Code subagents\n```\n' > "$P/CLAUDE.md"
out=$(cd "$P" && inst "$H"); printf '%s' "$out" | grep -q 'also has' && bad S2 "false duplicate warning" || ok "S2 no duplicate warning for a fenced example"
P=$T/proj3; rm -rf "$P"; mkdir -p "$P"; H=$(newhome hs3); printf '# Proj\n\n## Claude Code subagents\n\n- old\n' > "$P/CLAUDE.md"
out=$(cd "$P" && inst "$H"); printf '%s' "$out" | grep -q 'proj3/CLAUDE.md also has' && ok "S3 duplicate warning for a real section elsewhere" || bad S3 "no warning"

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

echo
echo "passed $PASS, failed $FAIL"
if [ "$FAIL" = 0 ] && [ -z "${KEEP:-}" ]; then rm -rf "$T"; else echo "Test files kept in $T"; fi
[ "$FAIL" = 0 ]
