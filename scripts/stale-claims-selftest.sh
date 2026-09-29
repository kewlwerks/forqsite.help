#!/usr/bin/env bash
#
# stale-claims-selftest.sh — exercises scripts/stale-claims.py against a throwaway fixture
# git repository and fixture manifests. Needs no forqsite clone and contacts no host.
#
# Fixture repo: commit P, the release commit R, then eight commits ending at T:
#   1. edit holds.txt; reflow wrap.md, splitting "two three four" across a line break
#   2. "old api()" -> "new api()" in stale.txt
#   3. append "no such" + newline + "thing" to absent.txt; create nope.txt
#   4. add dir/3.sql (R has dir/1.sql, dir/2.sql and dir/sub/x.sql)
#   5. git mv src/moved.txt src/renamed.txt
#   6. change revert.txt
#   7. revert that change
#   8. remove guard() from fix2.txt
#
# Cases (see docs/stories/INFRA/INFRA-016.md § Instructions 6):
#   (a) main manifest at T   — exit 3; every verdict line; per-record commits; summary
#   (b) clean subset at T    — exit 0; C-009 still printed as unverified
#   (c) target R             — exit 0; every claim untouched or unverified
#   (d) untouched but failing — exit 3; the claim is stale
#   (e) error codes          — 2 (config), 4 (resolution), 64 (usage)
#   (f) hygiene              — no fixture path in any output; fixture repo and manifests
#                              unchanged; every git subcommand the checker ran is
#                              read-only
#
# Exits non-zero if any case fails.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
CHECKER="$REPO_ROOT/scripts/stale-claims.py"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

FIXTURE_REPO="$WORK_DIR/fixture-repo"
PLAIN_DIR="$WORK_DIR/plain-dir"
STUB_BIN="$WORK_DIR/stub-bin"
GIT_LOG="$WORK_DIR/git-subcommands"
M_MAIN="$WORK_DIR/manifest-main.json"
M_CLEAN="$WORK_DIR/manifest-clean.json"
M_AT_R="$WORK_DIR/manifest-at-r.json"
M_NEVER="$WORK_DIR/manifest-never.json"
M_NOREL="$WORK_DIR/manifest-norelease.json"

# Keep the fixture independent of the caller's git configuration.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

FAILURES=0
PASS_COUNT=0
ALL_OUTPUT="$WORK_DIR/all-output"
: > "$ALL_OUTPUT"

report() {
  local name="$1" ok="$2" detail="$3"
  if [ "$ok" -eq 0 ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — $detail"
    FAILURES=$((FAILURES + 1))
  fi
}

# =====================================================================================
# Fixture repo
# =====================================================================================
g() { git -C "$FIXTURE_REPO" "$@"; }
commit() { g add -A && g commit -q -m "$1" && g rev-parse HEAD; }

mkdir -p "$FIXTURE_REPO" "$PLAIN_DIR"
git -c init.defaultBranch=main init -q "$FIXTURE_REPO"
g config user.email "selftest@example.invalid"
g config user.name "stale-claims-selftest"
g config commit.gpgsign false

printf 'fixture\n' > "$FIXTURE_REPO/README"
P="$(commit "fixture: initial")"

cd "$FIXTURE_REPO"
printf 'keep me here\n' > keep.txt
printf 'revert base\n' > revert.txt
printf 'holds evidence line\n' > holds.txt
printf 'one two three four five\n' > wrap.md
printf 'call old api() here\n' > stale.txt
printf 'nothing to see\n' > absent.txt
mkdir -p dir/sub cdir src
: > dir/1.sql; : > dir/2.sql; : > dir/sub/x.sql
: > cdir/a.sql; : > cdir/b.sql
printf 'moved evidence\n' > src/moved.txt
printf 'fixed()\n' > fix.txt
printf 'guard()\n' > fix2.txt
cd - >/dev/null
R="$(commit "fixture: release")"

printf 'holds evidence line\nextra line\n' > "$FIXTURE_REPO/holds.txt"
printf 'one two\nthree four five\n' > "$FIXTURE_REPO/wrap.md"
C1="$(commit "fixture 1: edit holds, reflow wrap")"
printf 'call new api() here\n' > "$FIXTURE_REPO/stale.txt"
C2="$(commit "fixture 2: change the api")"
printf 'no such\nthing\n' >> "$FIXTURE_REPO/absent.txt"
printf 'now here\n' > "$FIXTURE_REPO/nope.txt"
C3="$(commit "fixture 3: absent literal and path appear")"
: > "$FIXTURE_REPO/dir/3.sql"
C4="$(commit "fixture 4: third sql")"
g mv src/moved.txt src/renamed.txt
C5="$(commit "fixture 5: rename moved")"
printf 'revert changed\n' > "$FIXTURE_REPO/revert.txt"
C6="$(commit "fixture 6: change revert")"
g revert --no-edit HEAD >/dev/null
C7="$(g rev-parse HEAD)"
printf 'unguarded\n' > "$FIXTURE_REPO/fix2.txt"
C8="$(commit "fixture 8: remove guard")"
T="$C8"

short() { g log -1 --format=%h "$1"; }

# =====================================================================================
# Fixture manifests
# =====================================================================================
cat > "$M_MAIN" <<EOF
{
  "release": {"repo": "fixture/repo", "commit": "$R", "committed": "2026-01-01", "pinned": "2026-01-01"},
  "stamps": [],
  "claims": [
    {"id": "C-001", "result": "open", "note": "", "evidence": [{"path": "keep.txt", "symbol": "keep me here"}]},
    {"id": "C-002", "result": "open", "note": "",
     "evidence": [{"path": "holds.txt", "symbol": "holds evidence line"}],
     "absent": [{"path": "holds.txt", "symbol": "FORBIDDEN"}],
     "counts": [{"path": "cdir", "suffix": ".sql", "n": 2}]},
    {"id": "C-003", "result": "open", "note": "", "evidence": [{"path": "wrap.md", "symbol": "two three four"}]},
    {"id": "C-004", "result": "open", "note": "", "evidence": [{"path": "stale.txt", "symbol": "old api()"}]},
    {"id": "C-005", "result": "open", "note": "", "evidence": [], "absent": [{"path": "absent.txt", "symbol": "no such thing"}]},
    {"id": "C-006", "result": "open", "note": "", "evidence": [], "absent": [{"path": "nope.txt"}]},
    {"id": "C-007", "result": "open", "note": "", "evidence": [], "counts": [{"path": "dir", "suffix": ".sql", "n": 2}]},
    {"id": "C-008", "result": "open", "note": "", "evidence": [{"path": "src/moved.txt", "symbol": "moved evidence"}]},
    {"id": "C-009", "result": "unverified", "note": "UNVERIFIED: fixture reason",
     "marker": "this fixture claim is not verified",
     "evidence": [{"path": "keep.txt", "symbol": "keep me"}]},
    {"id": "C-010", "result": "open", "note": "", "evidence": [{"path": "revert.txt", "symbol": "revert base"}]},
    {"id": "C-011", "result": "open", "note": "no findable evidence", "evidence": []}
  ],
  "closed": [
    {"id": "C-012", "gap": "GAP-901", "claim": "fixed", "closed_by": {"commit": "$R", "path": "fix.txt"},
     "evidence": [{"path": "fix.txt", "symbol": "fixed()"}]},
    {"id": "C-013", "gap": "GAP-902", "claim": "guarded", "closed_by": {"commit": "$R", "path": "fix2.txt"},
     "evidence": [{"path": "fix2.txt", "symbol": "guard()"}]},
    {"id": "C-014", "gap": "GAP-903", "claim": "no evidence", "closed_by": {"commit": "$R", "path": "fix.txt"},
     "evidence": []}
  ]
}
EOF

derive() {
  # derive <out> <python filter body operating on m>
  python3 - "$M_MAIN" "$1" "$2" <<'PYEOF'
import json, sys
src, dst, body = sys.argv[1], sys.argv[2], sys.argv[3]
m = json.load(open(src))
exec(body)
json.dump(m, open(dst, 'w'), indent=1)
PYEOF
}
derive "$M_CLEAN" "
drop = {'C-004','C-005','C-006','C-007','C-008','C-013','C-014'}
m['claims'] = [c for c in m['claims'] if c['id'] not in drop]
m['closed'] = [c for c in m['closed'] if c['id'] not in drop]"
derive "$M_AT_R" "m['closed'] = [c for c in m['closed'] if c['id'] != 'C-014']"
derive "$M_NEVER" "m['claims'] = [{'id': 'C-001', 'result': 'open', 'note': '', 'evidence': [{'path': 'keep.txt', 'symbol': 'this never existed'}]}]; m.pop('closed')"
derive "$M_NOREL" "m['release']['commit'] = 'deadbeef' * 5"

MANIFESTS=("$M_MAIN" "$M_CLEAN" "$M_AT_R" "$M_NEVER" "$M_NOREL")
manifest_sums() { sha256sum "${MANIFESTS[@]}" | cut -d' ' -f1; }
repo_state() {
  g rev-parse HEAD
  g for-each-ref
  g status --porcelain
}
SUMS_BEFORE="$(manifest_sums)"
STATE_BEFORE="$(repo_state)"

# =====================================================================================
# git wrapper, first on PATH for checker runs only: logs the subcommand, then execs git.
# =====================================================================================
REAL_GIT="$(command -v git)"
mkdir -p "$STUB_BIN"
: > "$GIT_LOG"
cat > "$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
args=("\$@")
i=0
while [ \$i -lt \${#args[@]} ]; do
  case "\${args[\$i]}" in
    -C|-c) i=\$((i + 2)) ;;
    -*) i=\$((i + 1)) ;;
    *) break ;;
  esac
done
printf '%s\n' "\${args[\$i]:-<none>}" >> "$GIT_LOG"
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$STUB_BIN/git"

OUT=""
STATUS=0
# run_checker <label> <env: clone|unset|plain> <args...>
run_checker() {
  local label="$1" mode="$2"
  shift 2
  set +e
  case "$mode" in
    clone) OUT="$(cd "$WORK_DIR" && FORQSITE_CLONE="$FIXTURE_REPO" PATH="$STUB_BIN:$PATH" python3 "$CHECKER" "$@" 2>&1)" ;;
    plain) OUT="$(cd "$WORK_DIR" && FORQSITE_CLONE="$PLAIN_DIR" PATH="$STUB_BIN:$PATH" python3 "$CHECKER" "$@" 2>&1)" ;;
    unset) OUT="$(cd "$WORK_DIR" && env -u FORQSITE_CLONE PATH="$STUB_BIN:$PATH" python3 "$CHECKER" "$@" 2>&1)" ;;
  esac
  STATUS=$?
  set -e
  { echo "--- $label ---"; printf '%s\n' "$OUT"; } >> "$ALL_OUTPUT"
}

# The first line of a record's block (its verdict line), and the whole block.
# Both always exit 0, so a missing record reports FAIL instead of aborting under set -e.
verdict_line() { printf '%s\n' "$OUT" | grep -E "^$1 " | head -1 || true; }
record_block() {
  printf '%s\n' "$OUT" | awk -v id="$1" '
    $1 == id { on = 1; print; next }
    on && /^  / { print; next }
    { on = 0 }' || true
}

# =====================================================================================
# (a) Main manifest at T
# =====================================================================================
run_checker "a main at T" clone --manifest "$M_MAIN" "$T"
ok=0; detail=""
if [ "$STATUS" -ne 3 ]; then ok=1; detail="expected exit 3, got $STATUS"; fi
report "(a) main manifest at T exits 3" "$ok" "$detail"

expect_verdict() {
  local id="$1" verdict="$2" extra="${3:-}"
  local line; line="$(verdict_line "$id")"
  local ok=0 detail=""
  if [ -z "$line" ]; then
    ok=1; detail="no verdict line for $id"
  elif [ "$(printf '%s' "$line" | cut -d' ' -f2)" != "$verdict" ]; then
    ok=1; detail="got: $line"
  elif [ -n "$extra" ] && ! printf '%s' "$line" | grep -qF "$extra"; then
    ok=1; detail="verdict line lacks '$extra': $line"
  fi
  report "(a) $id is $verdict${extra:+ ($extra)}" "$ok" "$detail"
}
expect_verdict C-001 untouched
expect_verdict C-002 holds "touched: holds.txt"
expect_verdict C-003 holds "whitespace-only match: wrap.md"
expect_verdict C-004 stale
expect_verdict C-005 stale
expect_verdict C-006 stale
expect_verdict C-007 stale
expect_verdict C-008 stale
expect_verdict C-009 unverified
expect_verdict C-010 untouched
expect_verdict C-011 unverified
expect_verdict C-012 closed "gap GAP-901"
expect_verdict C-013 reopened "gap GAP-902"
expect_verdict C-014 reopened "gap GAP-903"

block_has() {
  local id="$1" needle="$2" name="$3"
  local ok=0 detail=""
  if ! record_block "$id" | grep -qF -- "$needle"; then
    ok=1; detail="$id block lacks '$needle'"
  fi
  report "(a) $name" "$ok" "$detail"
}
block_lacks() {
  local id="$1" needle="$2" name="$3"
  local ok=0 detail=""
  if record_block "$id" | grep -qF -- "$needle"; then
    ok=1; detail="$id block contains '$needle'"
  fi
  report "(a) $name" "$ok" "$detail"
}
block_has C-004 'fail: evidence stale.txt: "old api()" not found' "C-004 names its failing check"
block_has C-004 "commit: $(short "$C2") " "C-004 names commit 2"
block_lacks C-004 "commit: $(short "$C1") " "C-004 does not name commit 1"
block_has C-005 'fail: absent absent.txt: "no such thing" now present' "C-005 names its failing check"
block_has C-006 'fail: absent nope.txt: path now exists' "C-006 names its failing check"
block_has C-007 'fail: counts dir/*.sql: expected 2, found 3' "C-007 counts one level"
block_has C-008 'renamed to src/renamed.txt' "C-008 failure line names the rename"
block_has C-008 "commit: $(short "$C5") " "C-008 names commit 5"
block_has C-009 'reason: result is unverified' "C-009 gives its reason"
block_has C-009 'note: UNVERIFIED: fixture reason' "C-009 prints its note"
block_has C-009 'marker: this fixture claim is not verified' "C-009 prints its marker"
block_has C-011 'reason: no checks recorded' "C-011 reports no checks recorded"
block_has C-013 'fail: evidence fix2.txt: "guard()" not found' "C-013 names its failing check"
block_has C-013 "commit: $(short "$C8") " "C-013 names commit 8"
block_has C-014 'reason: no checks recorded' "C-014 reports no checks recorded"

ok=0; detail=""
expected_summary="summary: 11 claims: 2 untouched, 2 holds, 5 stale, 2 unverified; 3 closed records: 1 closed, 2 reopened"
actual_summary="$(printf '%s\n' "$OUT" | grep '^summary:' || true)"
if [ "$actual_summary" != "$expected_summary" ]; then ok=1; detail="got: $actual_summary"; fi
report "(a) summary line matches exactly" "$ok" "$detail"

ok=0; detail=""
first="$(printf '%s\n' "$OUT" | head -1)"
if [ "$first" != "stale-claims: fixture/repo ${R:0:8} -> $T (${T:0:8}), 8 commits" ]; then
  ok=1; detail="got: $first"
fi
report "(a) header line names release, target and 8 commits" "$ok" "$detail"

# =====================================================================================
# (b) Clean subset at T
# =====================================================================================
run_checker "b clean at T" clone --manifest "$M_CLEAN" "$T"
ok=0; detail=""
if [ "$STATUS" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $STATUS"
elif [ "$(verdict_line C-009 | cut -d' ' -f2)" != "unverified" ]; then
  ok=1; detail="C-009 not printed as unverified"
fi
report "(b) clean subset at T exits 0 and still prints C-009 unverified" "$ok" "$detail"

# =====================================================================================
# (c) Target R
# =====================================================================================
run_checker "c at R" clone --manifest "$M_AT_R" "$R"
ok=0; detail=""
bad="$(printf '%s\n' "$OUT" | grep -E '^C-0(0[1-9]|1[01]) ' | grep -vE '^C-[0-9]+ (untouched|unverified) ' || true)"
if [ "$STATUS" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $STATUS"
elif [ -n "$bad" ]; then
  ok=1; detail="claims not untouched/unverified: $bad"
elif [ "$(printf '%s\n' "$OUT" | grep -cE '^C-0(0[1-9]|1[01]) ')" -ne 11 ]; then
  ok=1; detail="expected 11 claim lines"
fi
report "(c) target R exits 0; every claim untouched or unverified" "$ok" "$detail"

# =====================================================================================
# (d) Untouched but failing
# =====================================================================================
run_checker "d untouched failing" clone --manifest "$M_NEVER" "$T"
ok=0; detail=""
if [ "$STATUS" -ne 3 ]; then
  ok=1; detail="expected exit 3, got $STATUS"
elif [ "$(verdict_line C-001 | cut -d' ' -f2)" != "stale" ]; then
  ok=1; detail="C-001 not stale: $(verdict_line C-001)"
fi
report "(d) untouched but failing claim is stale, exit 3" "$ok" "$detail"

# =====================================================================================
# (e) Error codes
# =====================================================================================
expect_exit() {
  local name="$1" want="$2"
  local ok=0 detail=""
  if [ "$STATUS" -ne "$want" ]; then ok=1; detail="expected exit $want, got $STATUS"; fi
  report "(e) $name exits $want" "$ok" "$detail"
}
run_checker "e unset" unset --manifest "$M_MAIN" "$T";                 expect_exit "FORQSITE_CLONE unset" 2
run_checker "e plain" plain --manifest "$M_MAIN" "$T";                 expect_exit "FORQSITE_CLONE a plain directory" 2
run_checker "e missing manifest" clone --manifest "$WORK_DIR/no-such.json" "$T"; expect_exit "missing manifest" 2
run_checker "e unknown target" clone --manifest "$M_MAIN" no-such-ref; expect_exit "unknown target" 4
run_checker "e target P" clone --manifest "$M_MAIN" "$P";              expect_exit "target P (release not an ancestor)" 4
run_checker "e release absent" clone --manifest "$M_NOREL" "$T";       expect_exit "release sha absent from the repo" 4
run_checker "e no args" clone;                                         expect_exit "no arguments" 64
run_checker "e unknown option" clone --bogus "$T";                     expect_exit "unknown option" 64

# =====================================================================================
# (f) Hygiene
# =====================================================================================
ok=0; detail=""
if grep -qF -- "$FIXTURE_REPO" "$ALL_OUTPUT"; then
  ok=1; detail="the fixture repo's path appears in checker output"
elif grep -qF -- "$WORK_DIR" "$ALL_OUTPUT"; then
  ok=1; detail="the work directory's path appears in checker output"
fi
report "(f) no fixture or work-directory path in any output" "$ok" "$detail"

ok=0; detail=""
if [ "$(repo_state)" != "$STATE_BEFORE" ]; then ok=1; detail="HEAD, refs or status changed"; fi
report "(f) fixture repo HEAD, refs and status unchanged" "$ok" "$detail"

ok=0; detail=""
if [ "$(manifest_sums)" != "$SUMS_BEFORE" ]; then ok=1; detail="a fixture manifest's sha256 changed"; fi
report "(f) fixture manifests unchanged" "$ok" "$detail"

ok=0; detail=""
ALLOWED=" rev-parse cat-file merge-base diff log show ls-tree rev-list "
if [ ! -s "$GIT_LOG" ]; then
  ok=1; detail="the git wrapper logged nothing"
else
  while IFS= read -r sub; do
    case "$ALLOWED" in
      *" $sub "*) ;;
      *) ok=1; detail="checker ran git $sub" ;;
    esac
  done < "$GIT_LOG"
fi
report "(f) every git subcommand the checker ran is read-only" "$ok" "$detail"

# =====================================================================================
echo ""
echo "stale-claims-selftest: $PASS_COUNT passed, $FAILURES failed"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
exit 0
