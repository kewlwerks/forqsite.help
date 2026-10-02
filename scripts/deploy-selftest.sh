#!/usr/bin/env bash
#
# deploy-selftest.sh — exercises scripts/deploy.sh's refusals and happy path against a
# throwaway fixture git repository and a throwaway fixture "remote" directory, using a
# stub `ssh` placed first on PATH. The stub runs the remote command under `dash` (a
# real POSIX sh, not bash) so that any bash-only quoting the remote command relies on
# is exposed rather than silently passing (CER-025). Contacts no real host.
#
# Cases (see docs/stories/INFRA/INFRA-006.md § Tests, INFRA-011 for 6-7, INFRA-012 for 8-12,
# INFRA-013 for 13, INFRA-014 for 14, INFRA-017 for 13f, 15 and 16, INFRA-018 for 17-22):
#   1. missing config   — exit 2, message names both variable names, stub-ssh not invoked
#   2. dirty tree       — exit 3, message names the dirty bundle, target files untouched
#   3. happy path       — exit 0, target files match committed bytes, two .bak-<stamp>
#                          files sharing one stamp, success block printed
#   4. hash mismatch    — stub ssh corrupts the file after the copy step, exit 4, message
#                          names the failing bundle
#   5. dry run          — exit 0, stub-ssh marker file absent (no ssh invoked at all)
#   6. hostile alias    — exit 2, no ssh invoked, no local command execution, value not
#                          printed; repeated with --dry-run and with an alias containing
#                          a space (CER-019)
#   7. POSIX quoting    — remote directory name containing a space, a single quote and a
#                          tab; exit 0, bytes match, under the dash-backed stub ssh (CER-025)
#   8. staging symlinks — symlinks to a sentinel at every old-scheme stage name for the
#                          run's window: exit 0, bytes match, sentinel unchanged, no stage
#                          left; symlinks at index.html.bak-<S>: exit 5, sentinel unchanged
#                          (INFRA-012, CER-023)
#   9. first-write mode — under umask 077, files that did not exist are created 0644; an
#                          existing file keeps its inode and its 0640 mode (INFRA-012)
#  10. retention        — six past and BACKUP_KEEP future-dated verified sets, one
#                          unverified set, one malformed marker: exit 0, current set kept,
#                          exactly BACKUP_KEEP pattern markers, pruned sets gone,
#                          unverified set and malformed marker untouched (CER-027)
#  11. partial prune    — the second of two prune removals fails: exit 5, report names the
#                          first stamp as pruned and the second as failed (INFRA-012)
#  12. no prune on fail — hash-mismatch run over seeded sets: exit 4, nothing deleted, no
#                          marker written (INFRA-012)
#  13. config file read as data (CER-024), with HOST and DIR unset in the environment
#      unless stated:
#      a. accepted forms  — the example's form (comment, blank line, double-quoted HOST
#                          and DIR, a SITE_URL line); then `export` + single-quoted DIR;
#                          then bare values with CRLF line endings: each exit 0, bytes landed
#      b. payloads        — DIR, and separately SITE_URL, set to "$(touch M)" and to a
#                          backtick `touch M` in double quotes: every marker absent
#      c. command line    — line 3 is `touch M3`: exit 2, names line 3, does not print the
#                          line, M3 absent, ssh never invoked
#      d. unknown key     — line 2 is UNKNOWN_KEY=<value>: exit 2, names line 2, value not
#                          printed, ssh never invoked
#      e. env complete    — env HOST and DIR set, malformed file present: exit 0 (the file
#                          is never read)
#      f. precedence, the environment wins (INFRA-017/CER-035):
#         f1. env DIR a fresh target, env HOST unset, file sets both: exit 0, bytes landed
#             in the environment's DIR and not in the file's
#         f2. env HOST valid, env DIR unset, file HOST `-oProxyCommand=false`, file DIR a
#             fresh target: exit 0 into the file's DIR (a file HOST that won would be
#             refused by the alias rule, exit 2)
#  14. transport errors (CER-028, INFRA-014) — the stub emits realistic ssh/remote-shell
#      text naming the alias or directory in force and exits without running the real
#      command; each case asserts exit 5, that the configured alias and directory are
#      absent from the captured output, and that the expected reason label is present:
#      a. resolve   — "Could not resolve hostname", exit 255 — "the host would not resolve"
#      b. refused   — "Connection refused", exit 255 — "the connection was refused"
#      c. auth      — "Permission denied (publickey)", exit 255 — "authentication was refused"
#      d. hostkey   — "Host key verification failed", exit 255 — "host key verification failed"
#      e. remote-text — a remote cp refusal, exit 1 — generic fallback label naming exit 1
#      f. dir missing — a target directory that is never created, no mode file (the real
#                        dash cd fails): exit 5 — "the remote directory is missing or
#                        cannot be entered"
#      Precondition: the stub is invoked directly in resolve mode and in remote-text
#      mode; its raw stderr is asserted to contain the alias and the directory,
#      respectively, so the leak-detection assertions above are not vacuous.
#  15. usage error (INFRA-017/CER-015) — `--bogus`, and separately a bare `--ref`: each
#      exit 64, ssh never invoked
#  16. --ref class (INFRA-017/CER-033) — a real fixture branch named q"b: `--ref 'q"b'`
#      exits 64, ssh never invoked, the value absent from the output; a branch
#      rel/a-1.b_2: `--dry-run --ref rel/a-1.b_2` exits 0
#  17. truthful backups line (INFRA-018/CER-037) — a deploy into an empty directory: exit 0,
#      no *.bak-* file, the backups line names no .bak-; a deploy over both bundles and no
#      sidecar: exit 0, the backups line names the two bundle backups and no sidecar backup
#  18. rollback (INFRA-018/CER-031), from a set seeded at a fixed past stamp:
#      a. complete set over live files — exit 0; each live file equals its backup, keeps
#         its inode, and has its old bytes in <name>.bak-<fresh stamp>; the backups line
#         names all three; no marker for the fresh stamp; no stage file left
#      b. no set, c. no sidecar backup, d. gap-handoff backup a symlink to the sentinel —
#         each exit 6; the target's snapshot (name, inode, sha256 of every entry) is
#         unchanged and the sentinel intact; c and d name the backup; none names the
#         directory
#      e. CORRUPT_FLAG set — exit 4, names index.html
#      f. --rollback with no value, a bad stamp, with --ref, with --dry-run — each exit
#         64, no ssh, never "unrecognized argument"
#  19. per-file prune report (INFRA-018/CER-030) — BACKUP_KEEP verified sets, the oldest
#      with a non-empty directory at its gap-handoff backup: exit 5, never "no backups were
#      pruned"; removed: names its index backup and not its gap-handoff backup; remains:
#      names its gap-handoff backup; its index backup gone, its marker still present
#  20. atomic backup (INFRA-018/ATOMIC) — the live index.html made unreadable (mode 000):
#      exit 5, and no entry containing "index.html.ba" is left (no backup name, no
#      temporary file); reported FAIL with a precondition message if the file is still
#      readable (e.g. as root), so it cannot pass vacuously
#  21. empty backup (INFRA-018/EMPTY) — a complete set whose index.html backup is emptied:
#      the 18(b)-(d) refusal contract (exit 6, unchanged snapshot, names the backup, not the
#      directory)
#  22. repeated option (INFRA-018/REPEAT) — `--ref HEAD --ref HEAD`, `--dry-run --dry-run`
#      and `--rollback <S> --rollback <S>`, each in a fresh target: exit 64, no ssh, the
#      output says "more than once"
#  23. resolve once (INFRA-022), on annotated fixture tags rel-fixture (at HEAD),
#      tree-fixture (a tag of HEAD's tree) and rel-move (at HEAD), each run in a fresh,
#      empty target:
#      a. CER-063: `--dry-run --ref rel-fixture` prints
#         `would deploy ref rel-fixture (resolved <commit>)`; no tag object sha
#      b. CER-063: `--ref rel-fixture` prints exactly `deployed  <commit>   (rel-fixture)`;
#         the sidecar has that repo_commit and repo_ref; no tag object sha
#         (vacuity guard for a and b: the tag object sha differs from the commit's)
#      c. CER-063: `--ref tree-fixture` exits 3, no ssh, "does not name a commit"
#      d. MOVE: a git wrapper, first on PATH for this run only, re-points rel-move at a
#         side commit (built with hash-object, mktree, commit-tree; a different
#         index.html) straight after the first git call naming it: exit 0,
#         `deployed  <HEAD>   (rel-move)`, the target's index.html is HEAD's bytes, the
#         sidecar has HEAD's repo_commit and index.html hash and repo_ref rel-move
#         (vacuity guard: the seam fired and rel-move^{commit} is now the side commit)
#
# Determinism: deploy.sh refuses a deploy whose one-second backup stamp already exists in
# its target (INFRA-012). So every deploy run that can reach the backup step starts from a
# target that was reset (fresh_target, reset_target_state, or a directory never used
# before), unless the case is asserting that refusal itself.
#
# Exits non-zero if any case fails.

set -euo pipefail

if ! command -v dash >/dev/null 2>&1; then
  echo "deploy-selftest: dash is required (used as the stub remote shell) but not found on PATH" >&2
  exit 1
fi

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
DEPLOY_SH="$REPO_ROOT/scripts/deploy.sh"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

FIXTURE_REPO="$WORK_DIR/fixture-repo"
FIXTURE_TARGET="$WORK_DIR/fixture-target"
STUB_BIN="$WORK_DIR/stub-bin"
SSH_MARKER="$WORK_DIR/ssh-marker"
CORRUPT_FLAG="$WORK_DIR/corrupt-flag"
# INFRA-014: when present, the stub emits one mode's canned ssh/remote-shell text and
# exit status without running the remote command at all. STUB_DIR_HINT_FILE supplies
# the "directory in force" text for the remote-text mode, whose canned line names a
# directory (the real cd never runs in that mode, so the stub cannot read it from the
# command it never executes).
STUB_MODE_FILE="$WORK_DIR/stub-mode"
STUB_DIR_HINT_FILE="$WORK_DIR/stub-dir-hint"

FAILURES=0
PASS_COUNT=0

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

# --- Build fixture repo -------------------------------------------------------------
mkdir -p "$FIXTURE_REPO"
git -C "$FIXTURE_REPO" init -q
git -C "$FIXTURE_REPO" config user.email "selftest@example.invalid"
git -C "$FIXTURE_REPO" config user.name "deploy-selftest"
echo "fixture index bundle" > "$FIXTURE_REPO/index.html"
echo "fixture gap-handoff bundle" > "$FIXTURE_REPO/gap-handoff.html"
git -C "$FIXTURE_REPO" add index.html gap-handoff.html
git -C "$FIXTURE_REPO" commit -q -m "fixture: initial bundles"

# --- Build fixture "remote" target directory ----------------------------------------
mkdir -p "$FIXTURE_TARGET"

# --- Build stub ssh, first on PATH ---------------------------------------------------
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/ssh" <<STUB
#!/usr/bin/env bash
# Stub ssh for deploy-selftest.sh (INFRA-006, extended INFRA-014). Records the host
# alias (\$1) before shift, then either:
#   - with $STUB_MODE_FILE present: emits one mode's realistic ssh or remote-shell
#     text to stderr and exits with that mode's status, without running the remote
#     command at all;
#   - otherwise: runs the remainder of its arguments with dash -c (a real POSIX sh,
#     not bash) against the fixture target directory, recording that it was invoked.
# Running the remote command under dash rather than bash is deliberate (CER-025):
# bash's \$'...' quoting only works under bash, and running the stub under bash would
# let that bash-only quoting pass even though the far account's login shell may be
# POSIX sh. Every call, mode or not, also writes a realistic "Permanently added"
# known-hosts notice to stderr, naming the alias, so the happy-path hygiene check
# (deploy-selftest.sh case 3) is asserting over real alias-bearing noise, not silence.
alias="\$1"
echo "invoked" >> "$SSH_MARKER"
echo "Warning: Permanently added '\$alias' (ED25519) to the list of known hosts." >&2
shift
cmd="\$1"
if [ -f "$STUB_MODE_FILE" ]; then
  mode="\$(cat "$STUB_MODE_FILE")"
  case "\$mode" in
    resolve)
      echo "ssh: Could not resolve hostname \$alias: Name or service not known" >&2
      exit 255
      ;;
    refused)
      echo "ssh: connect to host \$alias port 22: Connection refused" >&2
      exit 255
      ;;
    auth)
      echo "someuser@\$alias: Permission denied (publickey)." >&2
      exit 255
      ;;
    hostkey)
      echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" >&2
      echo "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED for \$alias!    @" >&2
      echo "Host key verification failed." >&2
      exit 255
      ;;
    remote-text)
      dir_hint="\$(cat "$STUB_DIR_HINT_FILE" 2>/dev/null || true)"
      echo "cp: cannot create regular file '\$dir_hint/index.html': Permission denied" >&2
      exit 1
      ;;
  esac
fi
out="\$(dash -c "\$cmd")"
status=\$?
case "\$cmd" in
  *"cat >"*)
    if [ -f "$CORRUPT_FLAG" ] && [ -f "$FIXTURE_TARGET/index.html" ]; then
      echo "corrupted" > "$FIXTURE_TARGET/index.html"
    fi
    ;;
esac
printf '%s\n' "\$out"
exit "\$status"
STUB
chmod +x "$STUB_BIN/ssh"

export PATH="$STUB_BIN:$PATH"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"

run_deploy() {
  ( cd "$FIXTURE_REPO" && "$DEPLOY_SH" "$@" )
}

# Clears every backup and verified marker from a target, so the next deploy into it can
# never collide with an earlier run's one-second stamp (INFRA-012 refuses that, exit 5).
reset_target_state() {
  rm -f "$1"/*.bak-* "$1"/.deploy-verified-* 2>/dev/null || true
}

# =====================================================================================
# Case 1: missing config
# =====================================================================================
rm -f "$SSH_MARKER"
unset FORQSITE_HELP_DEPLOY_HOST || true
unset FORQSITE_HELP_DEPLOY_DIR || true
rm -f "$FIXTURE_REPO/scripts/deploy.env" 2>/dev/null || true

set +e
out_case1="$(run_deploy 2>&1)"
status_case1=$?
set -e

ok=0
detail=""
if [ "$status_case1" -ne 2 ]; then
  ok=1; detail="expected exit 2, got $status_case1"
elif ! printf '%s' "$out_case1" | grep -q "FORQSITE_HELP_DEPLOY_HOST"; then
  ok=1; detail="message did not name FORQSITE_HELP_DEPLOY_HOST"
elif ! printf '%s' "$out_case1" | grep -q "FORQSITE_HELP_DEPLOY_DIR"; then
  ok=1; detail="message did not name FORQSITE_HELP_DEPLOY_DIR"
elif [ -f "$SSH_MARKER" ]; then
  ok=1; detail="stub-ssh marker file present — ssh was invoked"
fi
report "missing config (exit 2, names both variables, no ssh)" "$ok" "$detail"

# Restore config for the remaining cases.
export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"

# =====================================================================================
# Case 6: hostile alias (CER-019) — a value beginning with "-" must never reach ssh.
# HOSTILE_MARKER stands in for the local command execution ssh's own option parser
# would perform (e.g. -oProxyCommand=touch <marker>) if the raw value were ever
# passed to a real ssh unvalidated; deploy.sh must refuse before invoking ssh (stub
# or real) at all, so HOSTILE_MARKER must never be created here either.
# =====================================================================================
HOSTILE_MARKER="$WORK_DIR/hostile-marker"

check_hostile_alias() {
  local name="$1" status="$2" out="$3" value="$4"
  local ok=0 detail=""
  if [ "$status" -ne 2 ]; then
    ok=1; detail="expected exit 2, got $status"
  elif [ -f "$SSH_MARKER" ]; then
    ok=1; detail="stub-ssh marker present — ssh was invoked"
  elif [ -f "$HOSTILE_MARKER" ]; then
    ok=1; detail="hostile marker file created — value was executed"
  elif printf '%s' "$out" | grep -F -- "$value" >/dev/null; then
    ok=1; detail="output contains the value"
  fi
  report "$name" "$ok" "$detail"
}

rm -f "$SSH_MARKER" "$HOSTILE_MARKER"
export FORQSITE_HELP_DEPLOY_HOST="-oProxyCommand=touch $HOSTILE_MARKER"
set +e
out_hostile="$(run_deploy 2>&1)"
status_hostile=$?
set -e
check_hostile_alias "hostile alias (exit 2, no ssh, no marker, value not printed)" "$status_hostile" "$out_hostile" "$FORQSITE_HELP_DEPLOY_HOST"

rm -f "$SSH_MARKER" "$HOSTILE_MARKER"
set +e
out_hostile_dry="$(run_deploy --dry-run 2>&1)"
status_hostile_dry=$?
set -e
check_hostile_alias "hostile alias with --dry-run (exit 2, no ssh, no marker, value not printed)" "$status_hostile_dry" "$out_hostile_dry" "$FORQSITE_HELP_DEPLOY_HOST"

rm -f "$SSH_MARKER" "$HOSTILE_MARKER"
export FORQSITE_HELP_DEPLOY_HOST="fixture alias with space"
set +e
out_hostile_space="$(run_deploy 2>&1)"
status_hostile_space=$?
set -e
check_hostile_alias "alias containing a space (exit 2, no ssh, no marker, value not printed)" "$status_hostile_space" "$out_hostile_space" "$FORQSITE_HELP_DEPLOY_HOST"

# Restore a valid alias for the remaining cases.
export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"
rm -f "$SSH_MARKER" "$HOSTILE_MARKER"

# =====================================================================================
# Case 2: dirty tree
# =====================================================================================
rm -f "$SSH_MARKER"
echo "x" >> "$FIXTURE_REPO/index.html"

before_index_sha="$(sha256sum "$FIXTURE_TARGET/index.html" 2>/dev/null || true)"
before_gap_sha="$(sha256sum "$FIXTURE_TARGET/gap-handoff.html" 2>/dev/null || true)"

set +e
out_case2="$(run_deploy 2>&1)"
status_case2=$?
set -e

after_index_sha="$(sha256sum "$FIXTURE_TARGET/index.html" 2>/dev/null || true)"
after_gap_sha="$(sha256sum "$FIXTURE_TARGET/gap-handoff.html" 2>/dev/null || true)"

ok=0
detail=""
if [ "$status_case2" -ne 3 ]; then
  ok=1; detail="expected exit 3, got $status_case2"
elif ! printf '%s' "$out_case2" | grep -q "index.html"; then
  ok=1; detail="message did not name index.html as dirty"
elif [ -f "$SSH_MARKER" ]; then
  ok=1; detail="stub-ssh marker file present — ssh was invoked before the dirty refusal"
elif [ "$before_index_sha" != "$after_index_sha" ] || [ "$before_gap_sha" != "$after_gap_sha" ]; then
  ok=1; detail="fixture target files changed despite the refusal"
fi
report "dirty tree (exit 3, names bundle, target untouched)" "$ok" "$detail"

# Revert the dirtying edit.
git -C "$FIXTURE_REPO" checkout -q -- index.html

# =====================================================================================
# Case 3: happy path
# =====================================================================================
rm -f "$SSH_MARKER"
reset_target_state "$FIXTURE_TARGET"
# Pre-populate the fixture target with stand-in "live" bundles so the deploy has an
# existing file to back up (matching a real target, which is never empty).
echo "pre-existing live index bundle" > "$FIXTURE_TARGET/index.html"
echo "pre-existing live gap-handoff bundle" > "$FIXTURE_TARGET/gap-handoff.html"

set +e
out_case3="$(run_deploy 2>&1)"
status_case3=$?
set -e

committed_index_sha="$(git -C "$FIXTURE_REPO" show HEAD:index.html | sha256sum | cut -d' ' -f1)"
committed_gap_sha="$(git -C "$FIXTURE_REPO" show HEAD:gap-handoff.html | sha256sum | cut -d' ' -f1)"
target_index_sha="$(sha256sum "$FIXTURE_TARGET/index.html" | cut -d' ' -f1)"
target_gap_sha="$(sha256sum "$FIXTURE_TARGET/gap-handoff.html" | cut -d' ' -f1)"

bak_index=$(ls "$FIXTURE_TARGET"/index.html.bak-* 2>/dev/null || true)
bak_gap=$(ls "$FIXTURE_TARGET"/gap-handoff.html.bak-* 2>/dev/null || true)

ok=0
detail=""
if [ "$status_case3" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_case3: $out_case3"
elif [ "$committed_index_sha" != "$target_index_sha" ]; then
  ok=1; detail="target index.html does not match committed bytes"
elif [ "$committed_gap_sha" != "$target_gap_sha" ]; then
  ok=1; detail="target gap-handoff.html does not match committed bytes"
elif [ -z "$bak_index" ] || [ -z "$bak_gap" ]; then
  ok=1; detail="expected .bak-<stamp> files not found"
else
  stamp_index="${bak_index##*.bak-}"
  stamp_gap="${bak_gap##*.bak-}"
  if [ "$stamp_index" != "$stamp_gap" ]; then
    ok=1; detail="backup stamps differ: $stamp_index vs $stamp_gap"
  elif ! printf '%s' "$out_case3" | grep -q "^deployed"; then
    ok=1; detail="success block not printed"
  fi
fi
report "happy path (exit 0, bytes match, shared stamp, success block)" "$ok" "$detail"

# Forbidden-proxy check: neither the fixture host alias nor the fixture target
# directory path may appear anywhere in the captured happy-path output.
ok=0
detail=""
if printf '%s' "$out_case3" | grep -F "$FORQSITE_HELP_DEPLOY_HOST" >/dev/null; then
  ok=1; detail="fixture host alias leaked into success output"
elif printf '%s' "$out_case3" | grep -F "$FIXTURE_TARGET" >/dev/null; then
  ok=1; detail="fixture target directory path leaked into success output"
fi
report "happy path output names no configuration value" "$ok" "$detail"

# =====================================================================================
# Case 7: POSIX quoting — remote directory name with a space, a single quote and a
# tab. Every value spliced into a remote command string must round-trip exactly
# under a real POSIX sh (dash), not just under bash's own $'...' quoting (CER-025).
# =====================================================================================
ODD_DIR_NAME="odd target $(printf '\047')quote$(printf '\t')tab"
FIXTURE_ODD_TARGET="$WORK_DIR/$ODD_DIR_NAME"
mkdir -p "$FIXTURE_ODD_TARGET"
echo "pre-existing live index bundle" > "$FIXTURE_ODD_TARGET/index.html"
echo "pre-existing live gap-handoff bundle" > "$FIXTURE_ODD_TARGET/gap-handoff.html"

rm -f "$SSH_MARKER"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_ODD_TARGET"

set +e
out_odd="$(run_deploy 2>&1)"
status_odd=$?
set -e

target_odd_index_sha="$(sha256sum "$FIXTURE_ODD_TARGET/index.html" 2>/dev/null | cut -d' ' -f1 || true)"
target_odd_gap_sha="$(sha256sum "$FIXTURE_ODD_TARGET/gap-handoff.html" 2>/dev/null | cut -d' ' -f1 || true)"

ok=0
detail=""
if [ "$status_odd" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_odd: $out_odd"
elif [ "$committed_index_sha" != "$target_odd_index_sha" ]; then
  ok=1; detail="target index.html (odd dir) does not match committed bytes"
elif [ "$committed_gap_sha" != "$target_odd_gap_sha" ]; then
  ok=1; detail="target gap-handoff.html (odd dir) does not match committed bytes"
fi
report "POSIX quoting (dir name with space, quote and tab; exit 0, bytes match)" "$ok" "$detail"

# Restore the plain fixture target for the remaining cases.
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"
rm -f "$SSH_MARKER"

# =====================================================================================
# Case 4: hash mismatch
# =====================================================================================
rm -f "$SSH_MARKER"
# Case 3 deployed into this same target moments ago: clear its backups and marker.
reset_target_state "$FIXTURE_TARGET"
: > "$CORRUPT_FLAG"

set +e
out_case4="$(run_deploy 2>&1)"
status_case4=$?
set -e

rm -f "$CORRUPT_FLAG"

ok=0
detail=""
if [ "$status_case4" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_case4: $out_case4"
elif ! printf '%s' "$out_case4" | grep -q "index.html"; then
  ok=1; detail="message did not name index.html as the failing bundle"
fi
report "hash mismatch (exit 4, names failing bundle)" "$ok" "$detail"

# Restore the fixture target to a clean, matching state for the next case.
git -C "$FIXTURE_REPO" show HEAD:index.html > "$FIXTURE_TARGET/index.html"
git -C "$FIXTURE_REPO" show HEAD:gap-handoff.html > "$FIXTURE_TARGET/gap-handoff.html"
reset_target_state "$FIXTURE_TARGET"

# =====================================================================================
# Case 5: dry run
# =====================================================================================
rm -f "$SSH_MARKER"

set +e
out_case5="$(run_deploy --dry-run 2>&1)"
status_case5=$?
set -e

ok=0
detail=""
if [ "$status_case5" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_case5: $out_case5"
elif [ -f "$SSH_MARKER" ]; then
  ok=1; detail="stub-ssh marker file present — ssh was invoked during a dry run"
fi
report "dry run (exit 0, no ssh invoked)" "$ok" "$detail"

# =====================================================================================
# Shared helpers for the staging, backup and retention cases (INFRA-012).
# =====================================================================================
BACKUP_KEEP="$(sed -n 's/^BACKUP_KEEP=\([0-9][0-9]*\)$/\1/p' "$DEPLOY_SH" | head -n 1)"
if [ -z "$BACKUP_KEEP" ]; then
  echo "deploy-selftest: could not read BACKUP_KEEP from deploy.sh" >&2
  exit 1
fi
STAMP_RE='^[0-9]{8}T[0-9]{6}Z$'
SET_FILES=(index.html gap-handoff.html site-provenance.json)
SENTINEL="$WORK_DIR/sentinel"
SENTINEL_BYTES="sentinel — must never be written through"

stamp_at() { date -u -d "@$1" +%Y%m%dT%H%M%SZ; }

reset_sentinel() { printf '%s\n' "$SENTINEL_BYTES" > "$SENTINEL"; }
sentinel_intact() { [ "$(cat "$SENTINEL")" = "$SENTINEL_BYTES" ]; }

# A fresh target directory holding stand-in live bundles and a live sidecar.
fresh_target() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  echo "pre-existing live index bundle" > "$dir/index.html"
  echo "pre-existing live gap-handoff bundle" > "$dir/gap-handoff.html"
  echo '{"pre-existing": "live sidecar"}' > "$dir/site-provenance.json"
}

stamp_from_output() { printf '%s\n' "$1" | sed -n 's/^stamp[[:space:]]*//p' | head -n 1; }

# Seeds one backup set (three .bak-<stamp> files), with a marker when $3 is "verified".
seed_set() {
  local dir="$1" s="$2" kind="$3" n
  for n in "${SET_FILES[@]}"; do
    echo "seeded backup of $n at $s" > "$dir/$n.bak-$s"
  done
  if [ "$kind" = "verified" ]; then
    : > "$dir/.deploy-verified-$s"
  fi
}

# Verified marker names in a directory whose stamp matches the stamp pattern.
pattern_markers() {
  local dir="$1" f
  for f in "$dir"/.deploy-verified-*; do
    [ -e "$f" ] || continue
    f="${f##*/.deploy-verified-}"
    if [[ "$f" =~ $STAMP_RE ]]; then echo "$f"; fi
  done
}

PAST_STAMPS=()
for i in 1 2 3 4 5 6; do PAST_STAMPS+=("20200101T00000${i}Z"); done
FUTURE_STAMPS=()
for i in $(seq 1 "$BACKUP_KEEP"); do FUTURE_STAMPS+=("$(printf '20990101T%06dZ' "$i")"); done
UNVERIFIED_STAMP="20000101T000000Z"
MALFORMED_MARKER=".deploy-verified-19990101T000000Z-x"

# Clears backups and markers, then seeds six past verified sets, BACKUP_KEEP verified
# sets dated 2099, one unverified set older than all of them, and one marker whose
# name fails the stamp pattern.
seed_retention() {
  local dir="$1" s
  rm -f "$dir"/*.bak-* "$dir"/.deploy-verified-*
  for s in "${PAST_STAMPS[@]}" "${FUTURE_STAMPS[@]}"; do seed_set "$dir" "$s" verified; done
  seed_set "$dir" "$UNVERIFIED_STAMP" unverified
  : > "$dir/$MALFORMED_MARKER"
}

# =====================================================================================
# Case 8: staging symlinks (CER-023) — a symlink planted at every old-scheme stage name
# (.<name>.deploy-<S>.tmp) for the run's time window is never written through.
# =====================================================================================
SYM_TARGET="$WORK_DIR/symlink-target"
fresh_target "$SYM_TARGET"
reset_sentinel
now="$(date -u +%s)"
for off in $(seq 0 10); do
  S="$(stamp_at $((now + off)))"
  for n in "${SET_FILES[@]}"; do
    ln -s "$SENTINEL" "$SYM_TARGET/.${n}.deploy-${S}.tmp"
  done
done

export FORQSITE_HELP_DEPLOY_DIR="$SYM_TARGET"
set +e
out_sym="$(run_deploy 2>&1)"
status_sym=$?
set -e

left_stage=""
for f in "$SYM_TARGET"/.*.deploy-*; do
  [ -e "$f" ] || [ -L "$f" ] || continue
  [ -L "$f" ] && continue   # the planted symlinks themselves
  left_stage="$f"
done

ok=0
detail=""
if [ "$status_sym" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_sym: $out_sym"
elif ! sentinel_intact; then
  ok=1; detail="sentinel outside the target was written through a planted stage symlink"
elif [ "$(sha256sum "$SYM_TARGET/index.html" | cut -d' ' -f1)" != "$committed_index_sha" ]; then
  ok=1; detail="target index.html does not match committed bytes"
elif [ "$(sha256sum "$SYM_TARGET/gap-handoff.html" | cut -d' ' -f1)" != "$committed_gap_sha" ]; then
  ok=1; detail="target gap-handoff.html does not match committed bytes"
elif [ -n "$left_stage" ]; then
  ok=1; detail="a stage file was left in the target: ${left_stage##*/}"
fi
report "staging symlinks (exit 0, bytes match, sentinel unchanged, no stage left)" "$ok" "$detail"

# Backup-name symlinks: a symlink at index.html.bak-<S> for the run's window must make
# the deploy refuse (exit 5), never write through it.
BAKSYM_TARGET="$WORK_DIR/backup-symlink-target"
fresh_target "$BAKSYM_TARGET"
reset_sentinel
now="$(date -u +%s)"
for off in $(seq 0 10); do
  ln -s "$SENTINEL" "$BAKSYM_TARGET/index.html.bak-$(stamp_at $((now + off)))"
done

export FORQSITE_HELP_DEPLOY_DIR="$BAKSYM_TARGET"
set +e
out_baksym="$(run_deploy 2>&1)"
status_baksym=$?
set -e

ok=0
detail=""
if [ "$status_baksym" -ne 5 ]; then
  ok=1; detail="expected exit 5, got $status_baksym: $out_baksym"
elif ! sentinel_intact; then
  ok=1; detail="sentinel outside the target was written through a planted backup symlink"
elif ! printf '%s' "$out_baksym" | grep -q "index.html"; then
  ok=1; detail="refusal did not name index.html"
elif printf '%s' "$out_baksym" | grep -F "$BAKSYM_TARGET" >/dev/null; then
  ok=1; detail="refusal named the target directory"
fi
report "backup symlinks (exit 5, sentinel unchanged, names the file not the directory)" "$ok" "$detail"

# =====================================================================================
# Case 9: first-write mode — a destination that did not exist is created 0644 (never
# the mktemp stage's 0600), even under a restrictive umask; an existing destination
# keeps its inode and its operator-set mode.
# =====================================================================================
MODE_TARGET="$WORK_DIR/first-write-target"
rm -rf "$MODE_TARGET"
mkdir -p "$MODE_TARGET"
echo "pre-existing live index bundle" > "$MODE_TARGET/index.html"
chmod 0640 "$MODE_TARGET/index.html"
before_mode_inode="$(stat -c '%i' "$MODE_TARGET/index.html")"

export FORQSITE_HELP_DEPLOY_DIR="$MODE_TARGET"
set +e
out_mode="$( umask 077; run_deploy 2>&1 )"
status_mode=$?
set -e

mode_of() { stat -c '%a' "$1" 2>/dev/null || echo missing; }
ok=0
detail=""
if [ "$status_mode" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_mode: $out_mode"
elif [ "$(mode_of "$MODE_TARGET/gap-handoff.html")" != "644" ]; then
  ok=1; detail="newly created gap-handoff.html has mode $(mode_of "$MODE_TARGET/gap-handoff.html"), expected 644"
elif [ "$(mode_of "$MODE_TARGET/site-provenance.json")" != "644" ]; then
  ok=1; detail="newly created site-provenance.json has mode $(mode_of "$MODE_TARGET/site-provenance.json"), expected 644"
elif [ "$(mode_of "$MODE_TARGET/index.html")" != "640" ]; then
  ok=1; detail="existing index.html mode changed to $(mode_of "$MODE_TARGET/index.html"), expected 640"
elif [ "$(stat -c '%i' "$MODE_TARGET/index.html")" != "$before_mode_inode" ]; then
  ok=1; detail="existing index.html was replaced (inode changed)"
elif [ "$(sha256sum "$MODE_TARGET/index.html" | cut -d' ' -f1)" != "$committed_index_sha" ]; then
  ok=1; detail="target index.html does not match committed bytes"
fi
report "first-write mode (new files 0644 under umask 077; existing file keeps inode and mode)" "$ok" "$detail"

# =====================================================================================
# Case 10: retention (CER-027) — future-dated verified sets never displace the current
# set; unverified sets and malformed marker names are never touched.
# =====================================================================================
RET_TARGET="$WORK_DIR/retention-target"
fresh_target "$RET_TARGET"
seed_retention "$RET_TARGET"

export FORQSITE_HELP_DEPLOY_DIR="$RET_TARGET"
set +e
out_ret="$(run_deploy 2>&1)"
status_ret=$?
set -e
ret_stamp="$(stamp_from_output "$out_ret")"

# Expected pruned: every past stamp, plus the oldest future stamps beyond KEEP - 1.
expected_pruned=("${PAST_STAMPS[@]}" "${FUTURE_STAMPS[@]:0:$(( ${#FUTURE_STAMPS[@]} - (BACKUP_KEEP - 1) ))}")

ok=0
detail=""
if [ "$status_ret" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_ret: $out_ret"
elif ! [[ "$ret_stamp" =~ $STAMP_RE ]]; then
  ok=1; detail="could not read the run's stamp from the success block"
elif [ ! -e "$RET_TARGET/.deploy-verified-$ret_stamp" ]; then
  ok=1; detail="current set's marker missing"
else
  for n in "${SET_FILES[@]}"; do
    if [ ! -f "$RET_TARGET/$n.bak-$ret_stamp" ]; then ok=1; detail="current set's $n backup missing"; fi
  done
fi
if [ "$ok" -eq 0 ]; then
  marker_count="$(pattern_markers "$RET_TARGET" | wc -l)"
  if [ "$marker_count" -ne "$BACKUP_KEEP" ]; then
    ok=1; detail="expected $BACKUP_KEEP pattern markers, found $marker_count"
  fi
fi
if [ "$ok" -eq 0 ]; then
  for s in "${expected_pruned[@]}"; do
    for f in "${SET_FILES[@]/%/.bak-$s}" ".deploy-verified-$s"; do
      if [ -e "$RET_TARGET/$f" ]; then ok=1; detail="pruned stamp's file still present: $f"; fi
    done
  done
fi
if [ "$ok" -eq 0 ]; then
  for f in "${SET_FILES[@]/%/.bak-$UNVERIFIED_STAMP}" "$MALFORMED_MARKER"; do
    if [ ! -e "$RET_TARGET/$f" ]; then ok=1; detail="unverified or malformed entry was removed: $f"; fi
  done
  if [ "$(cat "$RET_TARGET/index.html.bak-$UNVERIFIED_STAMP")" != "seeded backup of index.html at $UNVERIFIED_STAMP" ]; then
    ok=1; detail="unverified set's content changed"
  fi
fi
if [ "$ok" -eq 0 ] && ! printf '%s\n' "$out_ret" | grep -q "^pruned .*${PAST_STAMPS[0]}"; then
  ok=1; detail="success block has no pruned line naming the pruned stamps"
fi
report "retention (current set kept, $BACKUP_KEEP verified markers, pruned sets gone, unverified + malformed untouched)" "$ok" "$detail"

# =====================================================================================
# Case 11: partial prune failure — the second of two prune removals fails; the report
# names the first stamp as pruned and the second as the one that failed, and never
# claims that no backups were pruned.
# =====================================================================================
PART_TARGET="$WORK_DIR/partial-prune-target"
fresh_target "$PART_TARGET"
# BACKUP_KEEP - 1 kept plus exactly two to prune.
part_stamps=()
for i in $(seq 1 $((BACKUP_KEEP + 1))); do part_stamps+=("$(printf '20200101T%06dZ' "$i")"); done
for s in "${part_stamps[@]}"; do seed_set "$PART_TARGET" "$s" verified; done
first_pruned="${part_stamps[0]}"
failing="${part_stamps[1]}"
# A non-empty directory where a backup file is expected: rm -f cannot remove it.
rm -f "$PART_TARGET/index.html.bak-$failing"
mkdir -p "$PART_TARGET/index.html.bak-$failing/blocker"

export FORQSITE_HELP_DEPLOY_DIR="$PART_TARGET"
set +e
out_part="$(run_deploy 2>&1)"
status_part=$?
set -e

ok=0
detail=""
if [ "$status_part" -ne 5 ]; then
  ok=1; detail="expected exit 5, got $status_part: $out_part"
elif ! printf '%s\n' "$out_part" | grep -i "pruned" | grep -q "$first_pruned"; then
  ok=1; detail="report does not name $first_pruned as pruned: $out_part"
elif ! printf '%s\n' "$out_part" | grep -i "fail" | grep -q "$failing"; then
  ok=1; detail="report does not name $failing as the failed stamp: $out_part"
elif printf '%s\n' "$out_part" | grep -qi "no backups were pruned\|no backups pruned"; then
  ok=1; detail="report claims no backups were pruned after one removal succeeded: $out_part"
elif [ -e "$PART_TARGET/.deploy-verified-$first_pruned" ] || [ -e "$PART_TARGET/gap-handoff.html.bak-$first_pruned" ]; then
  ok=1; detail="first stamp's files were not actually removed"
elif ! printf '%s\n' "$out_part" | grep -qi "verified"; then
  ok=1; detail="report does not say the files verified"
fi
report "partial prune failure (exit 5, names the pruned stamp and the failed one)" "$ok" "$detail"
rm -rf "$PART_TARGET"

# =====================================================================================
# Case 12: no prune on failure — a hash-mismatch run deletes nothing and writes no
# marker.
# =====================================================================================
fresh_target "$FIXTURE_TARGET"
seed_retention "$FIXTURE_TARGET"
seeded_names=()
for s in "${PAST_STAMPS[@]}" "${FUTURE_STAMPS[@]}"; do
  seeded_names+=("${SET_FILES[@]/%/.bak-$s}" ".deploy-verified-$s")
done
seeded_names+=("${SET_FILES[@]/%/.bak-$UNVERIFIED_STAMP}" "$MALFORMED_MARKER")
markers_before="$(cd "$FIXTURE_TARGET" && ls -A | grep '^\.deploy-verified-' | sort)"

export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"
: > "$CORRUPT_FLAG"
set +e
out_noprune="$(run_deploy 2>&1)"
status_noprune=$?
set -e
rm -f "$CORRUPT_FLAG"
markers_after="$(cd "$FIXTURE_TARGET" && ls -A | grep '^\.deploy-verified-' | sort)"

ok=0
detail=""
if [ "$status_noprune" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_noprune: $out_noprune"
elif [ "$markers_before" != "$markers_after" ]; then
  ok=1; detail="marker set changed on a failed run"
else
  for f in "${seeded_names[@]}"; do
    if [ ! -e "$FIXTURE_TARGET/$f" ]; then ok=1; detail="seeded file removed on a failed run: $f"; fi
  done
fi
report "no prune on failure (exit 4, every seeded file present, no marker written)" "$ok" "$detail"

# =====================================================================================
# Case 13: scripts/deploy.env is read as KEY=value data, never executed (CER-024).
# The fixture repo has no scripts/ directory of its own, so it is created here. Every
# run that can reach the backup step deploys into ENV_TARGET, and fresh_target resets
# ENV_TARGET immediately before each such run, so no two runs share a backup stamp.
# =====================================================================================
ENV_TARGET="$WORK_DIR/env-target"
ENV_FILE="$FIXTURE_REPO/scripts/deploy.env"
mkdir -p "$FIXTURE_REPO/scripts"

# Runs deploy.sh with HOST and DIR unset in the environment (a subshell, so the
# enclosing environment is unchanged).
run_deploy_file_only() {
  ( unset FORQSITE_HELP_DEPLOY_HOST FORQSITE_HELP_DEPLOY_DIR; run_deploy "$@" )
}

landed_in() {
  local dir="$1"
  [ "$(sha256sum "$dir/index.html" 2>/dev/null | cut -d' ' -f1)" = "$committed_index_sha" ] &&
    [ "$(sha256sum "$dir/gap-handoff.html" 2>/dev/null | cut -d' ' -f1)" = "$committed_gap_sha" ]
}

# --- 13a: accepted forms -------------------------------------------------------------
check_accepted() {
  local name="$1" status="$2" out="$3"
  local ok=0 detail=""
  if [ "$status" -ne 0 ]; then
    ok=1; detail="expected exit 0, got $status: $out"
  elif ! landed_in "$ENV_TARGET"; then
    ok=1; detail="committed bytes did not land in the file's DIR"
  fi
  report "$name" "$ok" "$detail"
}

# The example's form: a comment, a blank line, double-quoted HOST and DIR, SITE_URL.
cat > "$ENV_FILE" <<ENVEOF
# deploy.env in the example's form
FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"

FORQSITE_HELP_DEPLOY_DIR="$ENV_TARGET"
FORQSITE_HELP_SITE_URL="https://site.example.invalid"
ENVEOF
fresh_target "$ENV_TARGET"
set +e
out_env_a1="$(run_deploy_file_only 2>&1)"
status_env_a1=$?
set -e
check_accepted "config file, example form (double quotes, comment, blank, SITE_URL; exit 0, bytes landed)" "$status_env_a1" "$out_env_a1"

# export prefix and a single-quoted value.
cat > "$ENV_FILE" <<ENVEOF
  # an indented comment
export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"
export FORQSITE_HELP_DEPLOY_DIR='$ENV_TARGET'
ENVEOF
fresh_target "$ENV_TARGET"
set +e
out_env_a2="$(run_deploy_file_only 2>&1)"
status_env_a2=$?
set -e
check_accepted "config file, export + single-quoted value (exit 0, bytes landed)" "$status_env_a2" "$out_env_a2"

# Bare values, CRLF line endings.
printf 'FORQSITE_HELP_DEPLOY_HOST=fixture-host-alias\r\nFORQSITE_HELP_DEPLOY_DIR=%s\r\n' "$ENV_TARGET" > "$ENV_FILE"
fresh_target "$ENV_TARGET"
set +e
out_env_a3="$(run_deploy_file_only 2>&1)"
status_env_a3=$?
set -e
check_accepted "config file, bare values with CRLF endings (exit 0, bytes landed)" "$status_env_a3" "$out_env_a3"
rm -f "$ENV_FILE"

# --- 13b: payloads stay literal ------------------------------------------------------
# Each payload would create its marker if the file were ever executed. The evidence is
# the marker's absence, whatever the exit code.
PAYLOAD_M1="$WORK_DIR/payload-m1"
PAYLOAD_M2="$WORK_DIR/payload-m2"
check_payload() {
  local name="$1" marker="$2" out="$3"
  local ok=0 detail=""
  if [ -e "$marker" ]; then
    ok=1; detail="payload marker created — the config file was executed: $out"
  fi
  report "$name" "$ok" "$detail"
}

for key in FORQSITE_HELP_DEPLOY_DIR FORQSITE_HELP_SITE_URL; do
  for form in dollar backtick; do
    if [ "$form" = "dollar" ]; then
      marker="$PAYLOAD_M1"; payload="\$(touch $marker)"
    else
      marker="$PAYLOAD_M2"; payload="\`touch $marker\`"
    fi
    rm -f "$PAYLOAD_M1" "$PAYLOAD_M2"
    {
      echo 'FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"'
      if [ "$key" = "FORQSITE_HELP_DEPLOY_DIR" ]; then
        printf '%s="%s"\n' "$key" "$payload"
      else
        printf 'FORQSITE_HELP_DEPLOY_DIR="%s"\n' "$ENV_TARGET"
        printf '%s="%s"\n' "$key" "$payload"
      fi
    } > "$ENV_FILE"
    fresh_target "$ENV_TARGET"
    set +e
    out_payload="$(run_deploy_file_only 2>&1)"
    set -e
    check_payload "config file, $form payload in $key stays literal (marker absent)" "$marker" "$out_payload"
  done
done
rm -f "$ENV_FILE" "$PAYLOAD_M1" "$PAYLOAD_M2"

# --- 13c: a command line is refused by line number -----------------------------------
PAYLOAD_M3="$WORK_DIR/payload-m3"
rm -f "$PAYLOAD_M3" "$SSH_MARKER"
{
  echo '# line 1'
  echo 'FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"'
  echo "touch $PAYLOAD_M3"
  printf 'FORQSITE_HELP_DEPLOY_DIR="%s"\n' "$ENV_TARGET"
} > "$ENV_FILE"
set +e
out_env_c="$(run_deploy_file_only 2>&1)"
status_env_c=$?
set -e
ok=0
detail=""
if [ "$status_env_c" -ne 2 ]; then
  ok=1; detail="expected exit 2, got $status_env_c: $out_env_c"
elif ! printf '%s' "$out_env_c" | grep -q "line 3"; then
  ok=1; detail="refusal does not name line 3: $out_env_c"
elif printf '%s' "$out_env_c" | grep -q "touch"; then
  ok=1; detail="refusal printed the refused line's content"
elif [ -e "$PAYLOAD_M3" ]; then
  ok=1; detail="payload marker created — the config file was executed"
elif [ -f "$SSH_MARKER" ]; then
  ok=1; detail="stub-ssh marker present — ssh was invoked before the refusal"
fi
report "config file, command line (exit 2, names line 3, content not printed, marker absent, no ssh)" "$ok" "$detail"
rm -f "$ENV_FILE" "$PAYLOAD_M3"

# --- 13d: an unknown key is refused by line number, its value never printed ----------
UNKNOWN_VALUE="distinct-unknown-value-7f3a9c"
rm -f "$SSH_MARKER"
{
  echo 'FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"'
  echo "UNKNOWN_KEY=$UNKNOWN_VALUE"
  printf 'FORQSITE_HELP_DEPLOY_DIR="%s"\n' "$ENV_TARGET"
} > "$ENV_FILE"
set +e
out_env_d="$(run_deploy_file_only 2>&1)"
status_env_d=$?
set -e
ok=0
detail=""
if [ "$status_env_d" -ne 2 ]; then
  ok=1; detail="expected exit 2, got $status_env_d: $out_env_d"
elif ! printf '%s' "$out_env_d" | grep -q "line 2"; then
  ok=1; detail="refusal does not name line 2: $out_env_d"
elif printf '%s' "$out_env_d" | grep -qF "$UNKNOWN_VALUE"; then
  ok=1; detail="refusal printed the unknown key's value"
elif [ -f "$SSH_MARKER" ]; then
  ok=1; detail="stub-ssh marker present — ssh was invoked before the refusal"
fi
report "config file, unknown key (exit 2, names line 2, value not printed, no ssh)" "$ok" "$detail"
rm -f "$ENV_FILE"

# --- 13e: a complete environment never reads the file --------------------------------
PAYLOAD_M4="$WORK_DIR/payload-m4"
rm -f "$PAYLOAD_M4"
printf 'this line is not KEY=value\ntouch %s\n' "$PAYLOAD_M4" > "$ENV_FILE"
fresh_target "$ENV_TARGET"
set +e
out_env_e="$( export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias" FORQSITE_HELP_DEPLOY_DIR="$ENV_TARGET"; run_deploy 2>&1 )"
status_env_e=$?
set -e
ok=0
detail=""
if [ "$status_env_e" -ne 0 ]; then
  ok=1; detail="expected exit 0 with a complete environment, got $status_env_e: $out_env_e"
elif ! landed_in "$ENV_TARGET"; then
  ok=1; detail="committed bytes did not land in the environment's DIR"
elif [ -e "$PAYLOAD_M4" ]; then
  ok=1; detail="payload marker created — the config file was executed"
fi
report "config file, malformed but env complete (exit 0, file never read)" "$ok" "$detail"
rm -f "$ENV_FILE" "$PAYLOAD_M4"

# --- 13f: precedence — the environment wins; the file fills only unset keys ----------
# (INFRA-017/CER-035, replacing INFRA-013's file-overrides-environment case.)
PREC_ENV_TARGET="$WORK_DIR/precedence-env-target"
PREC_FILE_TARGET="$WORK_DIR/precedence-file-target"

# f1: env DIR set, env HOST unset, the file sets both. The environment's DIR is used;
# the file supplies only HOST.
{
  echo 'FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"'
  printf 'FORQSITE_HELP_DEPLOY_DIR="%s"\n' "$PREC_FILE_TARGET"
} > "$ENV_FILE"
fresh_target "$PREC_ENV_TARGET"
fresh_target "$PREC_FILE_TARGET"
set +e
out_env_f1="$( unset FORQSITE_HELP_DEPLOY_HOST; export FORQSITE_HELP_DEPLOY_DIR="$PREC_ENV_TARGET"; run_deploy 2>&1 )"
status_env_f1=$?
set -e
ok=0
detail=""
if [ "$status_env_f1" -ne 0 ]; then
  ok=1; detail="expected exit 0 into the environment's DIR, got $status_env_f1: $out_env_f1"
elif ! landed_in "$PREC_ENV_TARGET"; then
  ok=1; detail="committed bytes did not land in the environment's DIR"
elif landed_in "$PREC_FILE_TARGET"; then
  ok=1; detail="the file's DIR overrode the environment's"
fi
report "config file, precedence f1 (env DIR set, env HOST unset, file sets both; exit 0 into the environment's DIR, not the file's) INFRA-017/CER-035" "$ok" "$detail"

# f2: env HOST valid, env DIR unset. The file's HOST is one the alias rule refuses, so a
# file HOST that overrode the environment's would end the run with exit 2.
{
  echo 'FORQSITE_HELP_DEPLOY_HOST="-oProxyCommand=false"'
  printf 'FORQSITE_HELP_DEPLOY_DIR="%s"\n' "$PREC_FILE_TARGET"
} > "$ENV_FILE"
fresh_target "$PREC_FILE_TARGET"
set +e
out_env_f2="$( unset FORQSITE_HELP_DEPLOY_DIR; export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"; run_deploy 2>&1 )"
status_env_f2=$?
set -e
ok=0
detail=""
if [ "$status_env_f2" -ne 0 ]; then
  ok=1; detail="expected exit 0 into the file's DIR with the environment's HOST, got $status_env_f2: $out_env_f2"
elif ! landed_in "$PREC_FILE_TARGET"; then
  ok=1; detail="committed bytes did not land in the file's DIR"
fi
report "config file, precedence f2 (env HOST set, env DIR unset, file HOST refused by the alias rule; exit 0 into the file's DIR) INFRA-017/CER-035" "$ok" "$detail"
rm -f "$ENV_FILE"
rm -rf "$PREC_ENV_TARGET" "$PREC_FILE_TARGET"

export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"

# =====================================================================================
# Case 14: transport errors (CER-028, INFRA-014) — deploy.sh never prints the
# configured alias or directory on any ssh/remote-shell failure, and still prints a
# fixed reason label. An alias distinct from fixture-host-alias is used throughout, so
# the leak grep below is unambiguous (it could otherwise match deploy.sh's own
# unrelated argument-parsing text that happens to reuse "fixture-host-alias").
# =====================================================================================
TRANSPORT_HOST="fixture-host-alias-transport"
TRANSPORT_TARGET="$WORK_DIR/transport-target"

assert_no_leak_with_reason() {
  local name="$1" status="$2" out="$3" reason_substr="$4"
  local ok=0 detail=""
  if [ "$status" -ne 5 ]; then
    ok=1; detail="expected exit 5, got $status: $out"
  elif printf '%s' "$out" | grep -F -- "$TRANSPORT_HOST" >/dev/null; then
    ok=1; detail="output contains the configured alias"
  elif printf '%s' "$out" | grep -F -- "$TRANSPORT_TARGET" >/dev/null; then
    ok=1; detail="output contains the configured directory"
  elif ! printf '%s' "$out" | grep -F -- "$reason_substr" >/dev/null; then
    ok=1; detail="output does not contain the expected reason label ($reason_substr): $out"
  fi
  report "$name" "$ok" "$detail"
}

run_transport_case() {
  local mode="$1" reason_substr="$2" name="$3"
  fresh_target "$TRANSPORT_TARGET"
  rm -f "$SSH_MARKER"
  export FORQSITE_HELP_DEPLOY_HOST="$TRANSPORT_HOST"
  export FORQSITE_HELP_DEPLOY_DIR="$TRANSPORT_TARGET"
  echo "$mode" > "$STUB_MODE_FILE"
  set +e
  out="$(run_deploy 2>&1)"
  status=$?
  set -e
  rm -f "$STUB_MODE_FILE"
  assert_no_leak_with_reason "$name" "$status" "$out" "$reason_substr"
}

run_transport_case resolve "the host would not resolve" \
  "transport: host would not resolve (exit 5, no alias/dir leak, reason label)"
run_transport_case refused "the connection was refused" \
  "transport: connection refused (exit 5, no alias/dir leak, reason label)"
run_transport_case auth "authentication was refused" \
  "transport: authentication refused (exit 5, no alias/dir leak, reason label)"
run_transport_case hostkey "host key verification failed" \
  "transport: host key verification failed (exit 5, no alias/dir leak, reason label)"

# remote-text: the remote command itself fails (exit 1, not ssh). Its label is the
# generic fallback naming the exit code, since the canned cp refusal matches none of
# deploy.sh's own fixed remote-refusal texts.
fresh_target "$TRANSPORT_TARGET"
rm -f "$SSH_MARKER"
export FORQSITE_HELP_DEPLOY_HOST="$TRANSPORT_HOST"
export FORQSITE_HELP_DEPLOY_DIR="$TRANSPORT_TARGET"
echo "$TRANSPORT_TARGET" > "$STUB_DIR_HINT_FILE"
echo "remote-text" > "$STUB_MODE_FILE"
set +e
out_remotetext="$(run_deploy 2>&1)"
status_remotetext=$?
set -e
rm -f "$STUB_MODE_FILE" "$STUB_DIR_HINT_FILE"
assert_no_leak_with_reason \
  "transport: remote command failure (exit 5, no alias/dir leak, reason names exit 1)" \
  "$status_remotetext" "$out_remotetext" "exit 1"

# Remote directory missing — the real dash cd fails (no mode file), decided by exit
# code alone (REMOTE_DIR_MISSING_EXIT), never by parsing the shell's own wording.
MISSING_TARGET_DIR="$WORK_DIR/never-created-transport-target"
rm -rf "$MISSING_TARGET_DIR"
rm -f "$SSH_MARKER"
export FORQSITE_HELP_DEPLOY_HOST="$TRANSPORT_HOST"
export FORQSITE_HELP_DEPLOY_DIR="$MISSING_TARGET_DIR"
set +e
out_dirmissing="$(run_deploy 2>&1)"
status_dirmissing=$?
set -e
ok=0
detail=""
if [ "$status_dirmissing" -ne 5 ]; then
  ok=1; detail="expected exit 5, got $status_dirmissing: $out_dirmissing"
elif printf '%s' "$out_dirmissing" | grep -F -- "$TRANSPORT_HOST" >/dev/null; then
  ok=1; detail="output contains the configured alias"
elif printf '%s' "$out_dirmissing" | grep -F -- "$MISSING_TARGET_DIR" >/dev/null; then
  ok=1; detail="output contains the configured directory"
elif ! printf '%s' "$out_dirmissing" | grep -q "remote directory is missing or cannot be entered"; then
  ok=1; detail="output does not contain the expected reason label: $out_dirmissing"
fi
report "transport: remote directory missing (exit 5, no alias/dir leak, reason label)" "$ok" "$detail"

# Precondition (INFRA-014): the stub's own raw text really does carry the configured
# value, so the leak-detection assertions above are not vacuous.
PRECOND_ALIAS="precondition-alias-distinct-value"
rm -f "$SSH_MARKER"
echo "resolve" > "$STUB_MODE_FILE"
set +e
precond_resolve_out="$("$STUB_BIN/ssh" "$PRECOND_ALIAS" "true" 2>&1 >/dev/null)"
set -e
rm -f "$STUB_MODE_FILE"
ok=0
detail=""
if ! printf '%s' "$precond_resolve_out" | grep -F -- "$PRECOND_ALIAS" >/dev/null; then
  ok=1; detail="stub's raw resolve-mode stderr does not contain the alias — the leak assertions above would be vacuous: $precond_resolve_out"
fi
report "precondition: stub resolve-mode stderr carries the alias" "$ok" "$detail"

PRECOND_DIR="$WORK_DIR/precondition-directory-distinct-value"
rm -f "$SSH_MARKER"
echo "$PRECOND_DIR" > "$STUB_DIR_HINT_FILE"
echo "remote-text" > "$STUB_MODE_FILE"
set +e
precond_remotetext_out="$("$STUB_BIN/ssh" "fixture-host-alias" "true" 2>&1 >/dev/null)"
set -e
rm -f "$STUB_MODE_FILE" "$STUB_DIR_HINT_FILE"
ok=0
detail=""
if ! printf '%s' "$precond_remotetext_out" | grep -F -- "$PRECOND_DIR" >/dev/null; then
  ok=1; detail="stub's raw remote-text-mode stderr does not contain the directory — the leak assertions above would be vacuous: $precond_remotetext_out"
fi
report "precondition: stub remote-text-mode stderr carries the directory" "$ok" "$detail"

export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"

# =====================================================================================
# Case 15: usage error (INFRA-017/CER-015) — bad usage exits 64, never 2 (configuration
# missing) or 1, and never reaches ssh.
# =====================================================================================
check_usage_error() {
  local name="$1" status="$2" out="$3"
  local ok=0 detail=""
  if [ "$status" -ne 64 ]; then
    ok=1; detail="expected exit 64, got $status: $out"
  elif [ -f "$SSH_MARKER" ]; then
    ok=1; detail="stub-ssh marker present — ssh was invoked"
  fi
  report "$name" "$ok" "$detail"
}

USAGE_TARGET="$WORK_DIR/usage-target"
fresh_target "$USAGE_TARGET"
export FORQSITE_HELP_DEPLOY_DIR="$USAGE_TARGET"

rm -f "$SSH_MARKER"
set +e
out_usage_bogus="$(run_deploy --bogus 2>&1)"
status_usage_bogus=$?
set -e
check_usage_error "usage error, unrecognised argument --bogus (exit 64, no ssh) INFRA-017/CER-015" "$status_usage_bogus" "$out_usage_bogus"

rm -f "$SSH_MARKER"
set +e
out_usage_ref="$(run_deploy --ref 2>&1)"
status_usage_ref=$?
set -e
check_usage_error "usage error, --ref with no value (exit 64, no ssh) INFRA-017/CER-015" "$status_usage_ref" "$out_usage_ref"

# =====================================================================================
# Case 16: --ref class (INFRA-017/CER-033) — a ref outside REF_RE is refused (64) before
# any git or ssh work, and the refusal never prints the value. The branch is real, so
# without the check the ref would pass the dirty check and reach ssh.
# =====================================================================================
BAD_REF='q"b'
GOOD_REF='rel/a-1.b_2'
git -C "$FIXTURE_REPO" branch "$BAD_REF"
git -C "$FIXTURE_REPO" branch "$GOOD_REF"

fresh_target "$USAGE_TARGET"
rm -f "$SSH_MARKER"
set +e
out_badref="$(run_deploy --ref "$BAD_REF" 2>&1)"
status_badref=$?
set -e
ok=0
detail=""
if [ "$status_badref" -ne 64 ]; then
  ok=1; detail="expected exit 64, got $status_badref"
elif [ -f "$SSH_MARKER" ]; then
  ok=1; detail="stub-ssh marker present — ssh was invoked"
elif printf '%s' "$out_badref" | grep -qF -- "$BAD_REF"; then
  ok=1; detail="the refusal printed the ref's value"
fi
report "--ref class, a branch named q\"b (exit 64, no ssh, value not printed) INFRA-017/CER-033" "$ok" "$detail"

rm -f "$SSH_MARKER"
set +e
out_goodref="$(run_deploy --dry-run --ref "$GOOD_REF" 2>&1)"
status_goodref=$?
set -e
ok=0
detail=""
if [ "$status_goodref" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_goodref: $out_goodref"
elif [ -f "$SSH_MARKER" ]; then
  ok=1; detail="stub-ssh marker present — ssh was invoked during a dry run"
fi
report "--ref class, --dry-run --ref rel/a-1.b_2 (exit 0) INFRA-017/CER-033" "$ok" "$detail"

rm -rf "$USAGE_TARGET"
rm -f "$SSH_MARKER"
export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"

# =====================================================================================
# Shared helpers for cases 17-19 (INFRA-018).
# =====================================================================================
# The success block's backups line, or nothing.
backups_line_of() { printf '%s\n' "$1" | grep '^backups ' | head -n 1 || true; }

# Every entry of a directory: name, inode and sha256 (of what a regular file, or a
# symlink's target, holds; "-" for anything else). Two equal snapshots mean nothing in
# the directory was created, removed, replaced or rewritten.
snapshot_dir() {
  local dir="$1" f h
  ( cd "$dir" && ls -A | LC_ALL=C sort | while IFS= read -r f; do
      if [ -f "$f" ]; then h="$(sha256sum < "$f" | cut -d' ' -f1)"; else h="-"; fi
      printf '%s %s %s\n' "$f" "$(stat -c '%i' -- "$f")" "$h"
    done )
}

sha_of() { sha256sum < "$1" 2>/dev/null | cut -d' ' -f1 || true; }

# =====================================================================================
# Case 17 (INFRA-018/CER-037): the backups line lists only the backups the far side
# confirmed it wrote.
# =====================================================================================
# (a) A deploy into an empty directory: nothing to back up, nothing listed.
EMPTY17="$WORK_DIR/case17a-empty-target"
rm -rf "$EMPTY17"; mkdir -p "$EMPTY17"
export FORQSITE_HELP_DEPLOY_DIR="$EMPTY17"
set +e
out_17a="$(run_deploy 2>&1)"
status_17a=$?
set -e
bl_17a="$(backups_line_of "$out_17a")"
baks_17a="$(cd "$EMPTY17" && ls -A | grep '\.bak-' || true)"
ok=0
detail=""
if [ "$status_17a" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_17a: $out_17a"
elif [ -n "$baks_17a" ]; then
  ok=1; detail="a backup file exists after a deploy into an empty directory: $baks_17a"
elif [ -z "$bl_17a" ]; then
  ok=1; detail="the success block has no backups line"
elif printf '%s' "$bl_17a" | grep -qF '.bak-'; then
  ok=1; detail="the backups line names a backup that was never written: $bl_17a"
fi
report "first deploy into an empty directory (exit 0, no backup written, backups line names none) INFRA-018/CER-037" "$ok" "$detail"

# (b) Both bundles live, no sidecar: the two bundle backups are listed, no sidecar backup.
NOSIDE17="$WORK_DIR/case17b-no-sidecar-target"
rm -rf "$NOSIDE17"; mkdir -p "$NOSIDE17"
echo "pre-existing live index bundle" > "$NOSIDE17/index.html"
echo "pre-existing live gap-handoff bundle" > "$NOSIDE17/gap-handoff.html"
export FORQSITE_HELP_DEPLOY_DIR="$NOSIDE17"
set +e
out_17b="$(run_deploy 2>&1)"
status_17b=$?
set -e
bl_17b="$(backups_line_of "$out_17b")"
stamp_17b="$(stamp_from_output "$out_17b")"
ok=0
detail=""
if [ "$status_17b" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_17b: $out_17b"
elif ! [[ "$stamp_17b" =~ $STAMP_RE ]]; then
  ok=1; detail="could not read the run's stamp from the success block"
elif ! printf '%s' "$bl_17b" | grep -qF "index.html.bak-$stamp_17b"; then
  ok=1; detail="the backups line does not name index.html.bak-$stamp_17b: $bl_17b"
elif ! printf '%s' "$bl_17b" | grep -qF "gap-handoff.html.bak-$stamp_17b"; then
  ok=1; detail="the backups line does not name gap-handoff.html.bak-$stamp_17b: $bl_17b"
elif printf '%s' "$bl_17b" | grep -qF 'site-provenance.json.bak-'; then
  ok=1; detail="the backups line names a sidecar backup although no sidecar existed: $bl_17b"
elif [ -e "$NOSIDE17/site-provenance.json.bak-$stamp_17b" ]; then
  ok=1; detail="a sidecar backup was written although no sidecar existed"
fi
report "deploy over two bundles and no sidecar (exit 0, backups line names the two bundle backups only) INFRA-018/CER-037" "$ok" "$detail"
rm -rf "$EMPTY17" "$NOSIDE17"

# =====================================================================================
# Case 18 (INFRA-018/CER-031): --rollback <stamp> restores a complete set in place,
# sha256-verified, and refuses a missing or incomplete set with exit 6, writing nothing.
# =====================================================================================
RB_STAMP="20200202T020202Z"
# The success block's first line is the first non-blank one: the stub ssh echoes an
# empty line for every call whose stdout deploy.sh does not capture.

# A fresh target per run: live files, plus (unless told otherwise) a seeded backup set at
# RB_STAMP whose bytes end in a newline. Unmarked: a rollback does not need a marker.
rb_fresh_target() {
  fresh_target "$1"
  seed_set "$1" "$RB_STAMP" unverified
}

# (a) A rollback over live files.
RB18A="$WORK_DIR/case18a-rollback-target"
rb_fresh_target "$RB18A"
declare -A rb_old_sha rb_inode rb_bak_sha
for n in "${SET_FILES[@]}"; do
  rb_old_sha["$n"]="$(sha_of "$RB18A/$n")"
  rb_inode["$n"]="$(stat -c '%i' "$RB18A/$n")"
  rb_bak_sha["$n"]="$(sha_of "$RB18A/$n.bak-$RB_STAMP")"
done
export FORQSITE_HELP_DEPLOY_DIR="$RB18A"
rm -f "$SSH_MARKER"
set +e
out_18a="$(run_deploy --rollback "$RB_STAMP" 2>&1)"
status_18a=$?
set -e
fresh_18a="$(stamp_from_output "$out_18a")"
bl_18a="$(backups_line_of "$out_18a")"
left_stage_18a=""
for f in "$RB18A"/.*.deploy-*; do
  [ -e "$f" ] || [ -L "$f" ] || continue
  left_stage_18a="$f"
done
ok=0
detail=""
if [ "$status_18a" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_18a: $out_18a"
elif ! printf '%s\n' "$out_18a" | grep -v '^[[:space:]]*$' | head -n 1 | grep -q "^rolled back.*$RB_STAMP"; then
  ok=1; detail="the success block's first line does not start 'rolled back' and name $RB_STAMP: $out_18a"
elif ! [[ "$fresh_18a" =~ $STAMP_RE ]] || [ "$fresh_18a" = "$RB_STAMP" ]; then
  ok=1; detail="the success block's stamp is not a fresh stamp: '$fresh_18a'"
else
  for n in "${SET_FILES[@]}"; do
    [ "$ok" -eq 0 ] || break
    if [ "$(sha_of "$RB18A/$n")" != "${rb_bak_sha[$n]}" ]; then
      ok=1; detail="live $n does not equal $n.bak-$RB_STAMP"
    elif [ "$(stat -c '%i' "$RB18A/$n")" != "${rb_inode[$n]}" ]; then
      ok=1; detail="live $n was replaced (inode changed) rather than overwritten in place"
    elif [ "$(sha_of "$RB18A/$n.bak-$fresh_18a")" != "${rb_old_sha[$n]}" ]; then
      ok=1; detail="$n.bak-$fresh_18a does not hold $n's pre-rollback bytes"
    elif ! printf '%s' "$bl_18a" | grep -qF "$n.bak-$fresh_18a"; then
      ok=1; detail="the backups line does not name $n.bak-$fresh_18a: $bl_18a"
    elif ! printf '%s\n' "$out_18a" | grep -q "^$n .*${rb_bak_sha[$n]}  verified"; then
      ok=1; detail="the success block has no verified line for $n with its sha256"
    fi
  done
fi
if [ "$ok" -eq 0 ]; then
  if [ -e "$RB18A/.deploy-verified-$fresh_18a" ]; then
    ok=1; detail="a verified marker was written for the rollback's stamp"
  elif [ -n "$left_stage_18a" ]; then
    ok=1; detail="a stage file was left in the target: ${left_stage_18a##*/}"
  elif ! printf '%s\n' "$out_18a" | grep -q '^pruned    none$'; then
    ok=1; detail="the success block does not say pruned none"
  elif ! printf '%s\n' "$out_18a" | grep '^next' | grep -q 'drift check'; then
    ok=1; detail="the next line does not say to run the drift check"
  elif printf '%s' "$out_18a" | grep -F -- "$RB18A" >/dev/null; then
    ok=1; detail="the output names the target directory"
  elif printf '%s' "$out_18a" | grep -F -- "$FORQSITE_HELP_DEPLOY_HOST" >/dev/null; then
    ok=1; detail="the output names the ssh alias"
  fi
fi
report "rollback over live files (exit 0, each file restored in place and verified, old bytes in a fresh backup set, no marker, no stage left) INFRA-018/CER-031" "$ok" "$detail"
rm -rf "$RB18A"

# (b)-(d): refusals. Each writes nothing: the target's snapshot (every name, inode and
# sha256) is the same before and after, and the sentinel is intact.
check_rb_refusal() {
  local name="$1" dir="$2" names_backup="$3"
  local before after out status ok=0 detail=""
  reset_sentinel
  before="$(snapshot_dir "$dir")"
  export FORQSITE_HELP_DEPLOY_DIR="$dir"
  set +e
  out="$(run_deploy --rollback "$RB_STAMP" 2>&1)"
  status=$?
  set -e
  after="$(snapshot_dir "$dir")"
  if [ "$status" -ne 6 ]; then
    ok=1; detail="expected exit 6, got $status: $out"
  elif [ "$before" != "$after" ]; then
    ok=1; detail="the target changed although the rollback was refused"
  elif ! sentinel_intact; then
    ok=1; detail="the sentinel was written through"
  elif [ -n "$names_backup" ] && ! printf '%s' "$out" | grep -qF -- "$names_backup"; then
    ok=1; detail="the refusal does not name $names_backup: $out"
  elif printf '%s' "$out" | grep -F -- "$dir" >/dev/null; then
    ok=1; detail="the refusal names the target directory"
  fi
  report "$name" "$ok" "$detail"
}

RB18B="$WORK_DIR/case18b-no-set-target"
fresh_target "$RB18B"
check_rb_refusal "rollback to a stamp with no backup set (exit 6, nothing written, directory not named) INFRA-018/CER-031" "$RB18B" ""
rm -rf "$RB18B"

RB18C="$WORK_DIR/case18c-no-sidecar-backup-target"
rb_fresh_target "$RB18C"
rm -f "$RB18C/site-provenance.json.bak-$RB_STAMP"
check_rb_refusal "rollback to a set with no sidecar backup (exit 6, nothing written, names the sidecar backup) INFRA-018/CER-031" "$RB18C" "site-provenance.json.bak-$RB_STAMP"
rm -rf "$RB18C"

RB18D="$WORK_DIR/case18d-symlinked-backup-target"
rb_fresh_target "$RB18D"
rm -f "$RB18D/gap-handoff.html.bak-$RB_STAMP"
ln -s "$SENTINEL" "$RB18D/gap-handoff.html.bak-$RB_STAMP"
check_rb_refusal "rollback to a set whose gap-handoff.html backup is a symlink (exit 6, nothing written, sentinel intact, names that backup) INFRA-018/CER-031" "$RB18D" "gap-handoff.html.bak-$RB_STAMP"
rm -rf "$RB18D"

# (e) The stub corrupts the live index.html after each copy step: exit 4, names it.
rb_fresh_target "$FIXTURE_TARGET"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"
: > "$CORRUPT_FLAG"
set +e
out_18e="$(run_deploy --rollback "$RB_STAMP" 2>&1)"
status_18e=$?
set -e
rm -f "$CORRUPT_FLAG"
ok=0
detail=""
if [ "$status_18e" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_18e: $out_18e"
elif ! printf '%s' "$out_18e" | grep -q "index.html"; then
  ok=1; detail="the failure does not name index.html: $out_18e"
elif printf '%s' "$out_18e" | grep -F -- "$FIXTURE_TARGET" >/dev/null; then
  ok=1; detail="the failure names the target directory"
fi
report "rollback whose restored index.html fails the far-side hash (exit 4, names index.html) INFRA-018/CER-031" "$ok" "$detail"
fresh_target "$FIXTURE_TARGET"

# (f) Usage: each form exits 64 before any ssh, and is not reported as an unknown flag.
RB18F="$WORK_DIR/case18f-usage-target"
rb_fresh_target "$RB18F"
export FORQSITE_HELP_DEPLOY_DIR="$RB18F"
check_rb_usage() {
  local name="$1"; shift
  local out status ok=0 detail=""
  rm -f "$SSH_MARKER"
  set +e
  out="$(run_deploy "$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 64 ]; then
    ok=1; detail="expected exit 64, got $status: $out"
  elif [ -f "$SSH_MARKER" ]; then
    ok=1; detail="stub-ssh marker present — ssh was invoked"
  elif printf '%s' "$out" | grep -qi 'unrecognized argument'; then
    ok=1; detail="the refusal reports an unrecognized argument: $out"
  fi
  report "$name" "$ok" "$detail"
}
check_rb_usage "rollback usage, --rollback with no value (exit 64, no ssh, not an unknown flag) INFRA-018/CER-031" --rollback
check_rb_usage "rollback usage, a stamp outside the class (exit 64, no ssh, not an unknown flag) INFRA-018/CER-031" --rollback 2020-02-02
check_rb_usage "rollback usage, --rollback with --ref (exit 64, no ssh, not an unknown flag) INFRA-018/CER-031" --rollback "$RB_STAMP" --ref HEAD
check_rb_usage "rollback usage, --rollback with --dry-run (exit 64, no ssh, not an unknown flag) INFRA-018/CER-031" --rollback "$RB_STAMP" --dry-run
rm -rf "$RB18F"

# =====================================================================================
# Case 19 (INFRA-018/CER-030): a prune failure is reported file by file.
# =====================================================================================
PRUNE19="$WORK_DIR/case19-prune-report-target"
fresh_target "$PRUNE19"
# BACKUP_KEEP verified sets: with this deploy's own set, exactly the oldest is pruned.
p19_stamps=()
for i in $(seq 1 "$BACKUP_KEEP"); do p19_stamps+=("$(printf '20200303T%06dZ' "$i")"); done
for s in "${p19_stamps[@]}"; do seed_set "$PRUNE19" "$s" verified; done
p19_old="${p19_stamps[0]}"
# A non-empty directory where the oldest set's gap-handoff backup is: rm -f cannot remove it.
rm -f "$PRUNE19/gap-handoff.html.bak-$p19_old"
mkdir -p "$PRUNE19/gap-handoff.html.bak-$p19_old/blocker"
export FORQSITE_HELP_DEPLOY_DIR="$PRUNE19"
set +e
out_19="$(run_deploy 2>&1)"
status_19=$?
set -e
removed_19="$(printf '%s\n' "$out_19" | grep "in backup set $p19_old, removed:" || true)"
remains_19="$(printf '%s\n' "$out_19" | grep "in backup set $p19_old, remains:" || true)"
ok=0
detail=""
if [ "$status_19" -ne 5 ]; then
  ok=1; detail="expected exit 5, got $status_19: $out_19"
elif printf '%s\n' "$out_19" | grep -qi "no backups were pruned"; then
  ok=1; detail="the report says no backups were pruned although index.html.bak-$p19_old was removed: $out_19"
elif ! printf '%s' "$removed_19" | grep -qF "index.html.bak-$p19_old"; then
  ok=1; detail="the removed: line does not name index.html.bak-$p19_old: $out_19"
elif printf '%s' "$removed_19" | grep -qF "gap-handoff.html.bak-$p19_old"; then
  ok=1; detail="the removed: line names gap-handoff.html.bak-$p19_old, which remains: $out_19"
elif ! printf '%s' "$remains_19" | grep -qF "gap-handoff.html.bak-$p19_old"; then
  ok=1; detail="the remains: line does not name gap-handoff.html.bak-$p19_old: $out_19"
elif [ -e "$PRUNE19/index.html.bak-$p19_old" ]; then
  ok=1; detail="index.html.bak-$p19_old was not removed"
elif [ ! -e "$PRUNE19/.deploy-verified-$p19_old" ]; then
  ok=1; detail="the failed set's marker was removed, so no later deploy would retry it"
fi
report "prune failure reported per file (exit 5, removed: and remains: lines name the failed set's files) INFRA-018/CER-030" "$ok" "$detail"
rm -rf "$PRUNE19"

export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"

# =====================================================================================
# Case 20 (INFRA-018/ATOMIC): a backup write that fails leaves no backup name and no
# temporary file. The live index.html is made unreadable, so the far side's read fails
# after the write target has been opened.
# =====================================================================================
ATOM20="$WORK_DIR/case20-atomic-backup-target"
fresh_target "$ATOM20"
chmod 000 "$ATOM20/index.html"
if cat "$ATOM20/index.html" >/dev/null 2>&1; then
  chmod 644 "$ATOM20/index.html"
  report "a failed backup write leaves no backup name and no temporary file (exit 5) INFRA-018/ATOMIC" 1 \
    "precondition failed: a mode-000 file is still readable here (running as root?), so the case would pass vacuously"
else
  export FORQSITE_HELP_DEPLOY_DIR="$ATOM20"
  set +e
  out_20="$(run_deploy 2>&1)"
  status_20=$?
  set -e
  chmod 644 "$ATOM20/index.html"
  left_20="$(cd "$ATOM20" && ls -A | grep -F 'index.html.ba' || true)"
  ok=0
  detail=""
  if [ "$status_20" -ne 5 ]; then
    ok=1; detail="expected exit 5, got $status_20: $out_20"
  elif [ -n "$left_20" ]; then
    ok=1; detail="a failed backup write left an entry behind: $left_20"
  elif printf '%s' "$out_20" | grep -F -- "$ATOM20" >/dev/null; then
    ok=1; detail="the failure names the target directory"
  fi
  report "a failed backup write leaves no backup name and no temporary file (exit 5) INFRA-018/ATOMIC" "$ok" "$detail"
fi
rm -rf "$ATOM20"

# =====================================================================================
# Case 21 (INFRA-018/EMPTY): an empty backup counts as missing, so its set is refused
# under the 18(b)-(d) refusal contract.
# =====================================================================================
EMPTY21="$WORK_DIR/case21-empty-backup-target"
rb_fresh_target "$EMPTY21"
: > "$EMPTY21/index.html.bak-$RB_STAMP"
check_rb_refusal "rollback to a set with an empty index.html backup (exit 6, nothing written, names that backup) INFRA-018/EMPTY" "$EMPTY21" "index.html.bak-$RB_STAMP"
rm -rf "$EMPTY21"

# =====================================================================================
# Case 22 (INFRA-018/REPEAT): an option given more than once is a usage error (exit 64,
# no ssh); the last value never wins. Each run gets a fresh target.
# =====================================================================================
REP22="$WORK_DIR/case22-repeat-target"
check_repeat() {
  local name="$1"; shift
  local out status ok=0 detail=""
  rb_fresh_target "$REP22"
  export FORQSITE_HELP_DEPLOY_DIR="$REP22"
  rm -f "$SSH_MARKER"
  set +e
  out="$(run_deploy "$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 64 ]; then
    ok=1; detail="expected exit 64, got $status: $out"
  elif [ -f "$SSH_MARKER" ]; then
    ok=1; detail="stub-ssh marker present — ssh was invoked"
  elif ! printf '%s' "$out" | grep -q 'more than once'; then
    ok=1; detail="the refusal does not say the option was given more than once: $out"
  fi
  report "$name" "$ok" "$detail"
  rm -rf "$REP22"
}
check_repeat "repeated --ref (exit 64, no ssh, says more than once) INFRA-018/REPEAT" --ref HEAD --ref HEAD
check_repeat "repeated --dry-run (exit 64, no ssh, says more than once) INFRA-018/REPEAT" --dry-run --dry-run
check_repeat "repeated --rollback (exit 64, no ssh, says more than once) INFRA-018/REPEAT" --rollback "$RB_STAMP" --rollback "$RB_STAMP"

export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"

# =====================================================================================
# Case 23 (INFRA-022/CER-063, INFRA-022/MOVE): the ref is resolved to a commit once.
# Fixture tags: rel-fixture (annotated, at HEAD), tree-fixture (annotated, of HEAD's
# tree), rel-move (annotated, at HEAD, re-pointed mid-run by the git wrapper below).
# Every run uses a fresh, empty target.
# =====================================================================================
D23_HEAD="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
git -C "$FIXTURE_REPO" tag -a -m "fixture: release tag" rel-fixture "$D23_HEAD"
git -C "$FIXTURE_REPO" tag -a -m "fixture: tag of a tree" tree-fixture "${D23_HEAD}^{tree}"
git -C "$FIXTURE_REPO" tag -a -m "fixture: moving tag" rel-move "$D23_HEAD"
D23_TAG_OBJ="$(git -C "$FIXTURE_REPO" rev-parse rel-fixture)"
D23_TAG_OBJ_SHORT="$(git -C "$FIXTURE_REPO" rev-parse --short rel-fixture)"
D23_HEAD_INDEX_SHA="$(git -C "$FIXTURE_REPO" show "${D23_HEAD}:index.html" | sha256sum | cut -d' ' -f1)"
D23_TARGET="$WORK_DIR/case23-resolve-once-target"
d23_fresh_target() { rm -rf "$D23_TARGET"; mkdir -p "$D23_TARGET"; export FORQSITE_HELP_DEPLOY_DIR="$D23_TARGET"; rm -f "$SSH_MARKER"; }
d23_sidecar_field() {  # $1 field; prints the target sidecar's field, or nothing
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["bundles"][sys.argv[2][8:]] if sys.argv[2].startswith("bundles.") else d[sys.argv[2]])' \
    "$D23_TARGET/site-provenance.json" "$1" 2>/dev/null || true
}

# 23a: dry run of an annotated tag names the commit it points to.
d23_fresh_target
set +e
out_23a="$(run_deploy --dry-run --ref rel-fixture 2>&1)"
status_23a=$?
set -e
ok=0
detail=""
if [ "$D23_TAG_OBJ" = "$D23_HEAD" ]; then
  ok=1; detail="precondition: rel-fixture's tag object sha equals its commit, so the case is vacuous"
elif [ "$status_23a" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_23a: $out_23a"
elif ! printf '%s\n' "$out_23a" | grep -qF "would deploy ref rel-fixture (resolved ${D23_HEAD})"; then
  ok=1; detail="the dry run does not say 'would deploy ref rel-fixture (resolved ${D23_HEAD})': $out_23a"
elif printf '%s' "$out_23a" | grep -qF "$D23_TAG_OBJ_SHORT"; then
  ok=1; detail="the dry run prints the tag object's sha ($D23_TAG_OBJ_SHORT): $out_23a"
fi
report "dry run of an annotated tag (exit 0, resolved names its commit, no tag object sha) INFRA-022/CER-063" "$ok" "$detail"

# 23b: a deploy of an annotated tag records and prints the commit it points to.
d23_fresh_target
set +e
out_23b="$(run_deploy --ref rel-fixture 2>&1)"
status_23b=$?
set -e
ok=0
detail=""
if [ "$D23_TAG_OBJ" = "$D23_HEAD" ]; then
  ok=1; detail="precondition: rel-fixture's tag object sha equals its commit, so the case is vacuous"
elif [ "$status_23b" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_23b: $out_23b"
elif ! printf '%s\n' "$out_23b" | grep -qxF "deployed  ${D23_HEAD}   (rel-fixture)"; then
  ok=1; detail="no line is exactly 'deployed  ${D23_HEAD}   (rel-fixture)': $out_23b"
elif [ "$(d23_sidecar_field repo_commit)" != "$D23_HEAD" ]; then
  ok=1; detail="the sidecar's repo_commit is not the commit ($D23_HEAD): $(cat "$D23_TARGET/site-provenance.json" 2>/dev/null)"
elif [ "$(d23_sidecar_field repo_ref)" != "rel-fixture" ]; then
  ok=1; detail="the sidecar's repo_ref is not rel-fixture"
elif printf '%s' "$out_23b" | grep -qF "$D23_TAG_OBJ_SHORT"; then
  ok=1; detail="the deploy prints the tag object's sha ($D23_TAG_OBJ_SHORT): $out_23b"
fi
report "deploy of an annotated tag (exit 0, deployed line and sidecar name its commit, repo_ref the tag) INFRA-022/CER-063" "$ok" "$detail"

# 23c: a ref that names no commit is refused before any ssh call.
d23_fresh_target
set +e
out_23c="$(run_deploy --ref tree-fixture 2>&1)"
status_23c=$?
set -e
ok=0
detail=""
if [ "$(git -C "$FIXTURE_REPO" cat-file -t 'tree-fixture^{}' 2>/dev/null)" != "tree" ]; then
  ok=1; detail="precondition: tree-fixture does not peel to a tree, so the case is vacuous"
elif [ "$status_23c" -ne 3 ]; then
  ok=1; detail="expected exit 3, got $status_23c: $out_23c"
elif [ -f "$SSH_MARKER" ]; then
  ok=1; detail="stub-ssh marker present — ssh was invoked"
elif ! printf '%s' "$out_23c" | grep -qF 'does not name a commit'; then
  ok=1; detail="the refusal does not say the ref names no commit: $out_23c"
fi
report "deploy of a tag of a tree (exit 3, no ssh, does not name a commit) INFRA-022/CER-063" "$ok" "$detail"

# 23d (MOVE): rel-move is re-pointed at a side commit with a different index.html
# straight after the first git call that names it. The side commit is built with
# hash-object, mktree and commit-tree, so HEAD and the working tree stay put.
D23_SIDE_BLOB="$(printf 'side commit index bundle\n' | git -C "$FIXTURE_REPO" hash-object -w --stdin)"
D23_GAP_BLOB="$(git -C "$FIXTURE_REPO" rev-parse "${D23_HEAD}:gap-handoff.html")"
D23_SIDE_TREE="$(printf '100644 blob %s\tgap-handoff.html\n100644 blob %s\tindex.html\n' "$D23_GAP_BLOB" "$D23_SIDE_BLOB" | git -C "$FIXTURE_REPO" mktree)"
D23_SIDE="$(git -C "$FIXTURE_REPO" commit-tree -p "$D23_HEAD" -m "fixture: side commit" "$D23_SIDE_TREE")"

# The git wrapper runs the real git (captured before the wrapper exists). On the first
# call naming rel-move while the trigger exists, it deletes the trigger, runs that
# call, then re-points rel-move at $MOVE_TO with `tag -f -a`, and returns the call's
# own status. It is first on PATH for this one run only, inside a subshell.
D23_REAL_GIT="$(command -v git)"
D23_WRAP_DIR="$WORK_DIR/git-wrap"
D23_TRIGGER="$WORK_DIR/move-trigger"
mkdir -p "$D23_WRAP_DIR"
cat > "$D23_WRAP_DIR/git" <<WRAP
#!/usr/bin/env bash
names_move=0
for a in "\$@"; do
  case "\$a" in *rel-move*) names_move=1 ;; esac
done
if [ "\$names_move" -eq 1 ] && [ -f "$D23_TRIGGER" ]; then
  rm -f "$D23_TRIGGER"
  status=0
  "$D23_REAL_GIT" "\$@" || status=\$?
  "$D23_REAL_GIT" tag -f -a -m "fixture: moved mid-run" rel-move "\$MOVE_TO" >/dev/null 2>&1
  exit "\$status"
fi
exec "$D23_REAL_GIT" "\$@"
WRAP
chmod +x "$D23_WRAP_DIR/git"

d23_fresh_target
: > "$D23_TRIGGER"
set +e
out_23d="$( export PATH="$D23_WRAP_DIR:$PATH"; export MOVE_TO="$D23_SIDE"; run_deploy --ref rel-move 2>&1 )"
status_23d=$?
set -e
d23_moved_to="$(git -C "$FIXTURE_REPO" rev-parse -q --verify 'rel-move^{commit}' 2>/dev/null || true)"
d23_target_index_sha="$(sha256sum "$D23_TARGET/index.html" 2>/dev/null | cut -d' ' -f1 || true)"
ok=0
detail=""
if [ -f "$D23_TRIGGER" ]; then
  ok=1; detail="precondition: the seam never fired (no git call named rel-move)"
elif [ "$d23_moved_to" != "$D23_SIDE" ]; then
  ok=1; detail="precondition: rel-move^{commit} is $d23_moved_to after the run, not the side commit $D23_SIDE"
elif [ "$(git -C "$FIXTURE_REPO" rev-parse "${D23_SIDE}:index.html")" = "$(git -C "$FIXTURE_REPO" rev-parse "${D23_HEAD}:index.html")" ]; then
  ok=1; detail="precondition: the side commit's index.html equals HEAD's, so the case is vacuous"
elif [ "$status_23d" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_23d: $out_23d"
elif ! printf '%s\n' "$out_23d" | grep -qxF "deployed  ${D23_HEAD}   (rel-move)"; then
  ok=1; detail="no line is exactly 'deployed  ${D23_HEAD}   (rel-move)': $out_23d"
elif [ "$d23_target_index_sha" != "$D23_HEAD_INDEX_SHA" ]; then
  ok=1; detail="the target's index.html is not HEAD's bytes"
elif [ "$(d23_sidecar_field repo_commit)" != "$D23_HEAD" ]; then
  ok=1; detail="the sidecar's repo_commit is not HEAD ($D23_HEAD)"
elif [ "$(d23_sidecar_field repo_ref)" != "rel-move" ]; then
  ok=1; detail="the sidecar's repo_ref is not rel-move"
elif [ "$(d23_sidecar_field bundles.index.html)" != "$D23_HEAD_INDEX_SHA" ]; then
  ok=1; detail="the sidecar's index.html hash is not HEAD's"
fi
rm -f "$D23_TRIGGER"
report "deploy of a ref moved to a side commit straight after its first read (exit 0, deployed line, bytes and sidecar are the resolved commit's) INFRA-022/MOVE" "$ok" "$detail"
rm -rf "$D23_TARGET"

export FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"
export FORQSITE_HELP_DEPLOY_DIR="$FIXTURE_TARGET"

# =====================================================================================
echo ""
echo "deploy-selftest: $PASS_COUNT passed, $FAILURES failed"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
exit 0
