#!/usr/bin/env bash
#
# release-selftest.sh — exercises scripts/release.sh (INFRA-021) end to end against
# throwaway fixtures: a fixture forqsite clone, a fixture forqsite.help repository with a
# bare origin, a stub `ssh` first on PATH that runs every remote command under `dash`
# against a local target directory (as deploy-selftest.sh does), and a local static
# server bound to 127.0.0.1 that serves that directory, with an override directory (as
# drift-check-selftest.sh does). Contacts no host other than 127.0.0.1, and never a
# real origin: every origin is a bare repository inside the work directory.
#
# Fixture forqsite clone (FORQSITE_CLONE), fixed dates:
#   base; R (a.txt "alpha", b.txt "beta"); T1 edits a.txt, keeping alpha; T2 adds c.txt;
#   S, from T2, removes beta. The subjects of T1 and S carry a marker string. Tags:
#   cp-PM9-main on T1, cp-PM10-main on T2, and a decoy cp-PM999-rc-main on S.
#
# Fixture forqsite.help seed: release.sh and its siblings (restamp.py, stale-claims.py,
# bundle-template.py, deploy.sh, drift-check.sh, make-provenance.sh, read-deploy-env.sh),
# the repository's real .gitignore, and a stub scripts/fixture-selftest.sh (its only
# selftest, so there is no recursion: FIXTURE_SELFTEST_FAIL=pre always fails, =post fails
# once the manifest differs from HEAD). Both bundles are built with bundle-template.py's
# encode() through importlib, and each template contains a "/". The manifest pins
# fixture/forqsite at R: S-01 (ISO, index.html), S-02 (long form, gap-handoff.html),
# C-001 Known-gaps (no result, note naming S-02, evidence equal to C-003's), C-002 open on
# a.txt/alpha, C-003 open on b.txt/beta under S-02. The seed is committed, tagged
# rel-<R8> (annotated, with a past date) and pushed to a bare origin.
#
# Each case copies the bare origin, clones it fresh and empties the deploy target.
# "Nothing touched" means HEAD, the local tags, the origin refs and the tracked status
# are unchanged, and the stub ssh was never invoked.
#
# Cases (tokens): CLEAN, NOOP, LATEST, AHEAD, DRYRUN, STALE, DRIFT, DEPLOY, PUSH, REFUSE
# (every refusal code), HYGIENE (no work-directory path, alias, 127.0.0.1 or port in any
# release.sh output). INFRA-023 adds, under tokens INFRA-023/<TOKEN>: PARTIAL (a real
# partial restamp write through a read-only docs/: exit 11, the restore line, and a clean
# tree after running it; SKIP when docs/ stays writable, as for root), PUSHURL (a pushurl
# that differs from the url refuses with 2 and prints neither URL, also with GIT_CONFIG set;
# pushurls equal to the url are not refused) and REFSPEC (with hijacking remote.origin.push
# refspecs, both the release's own push and the printed exit-17 push line land on main and
# rel-<t8>). INFRA-024 adds, under token INFRA-024/EXACT: the push and every printed push
# line send the release commit and the tag object by sha, and exit 18 stops the job, pushing
# nothing, when the release commit's only parent is not PRE, when rel-<t8> is not the tag
# the job made, or when deploy.sh's deployed line or drift-check.sh's ref line does not name
# the release commit. An optional hook file, run once by the stub ssh inside the deploy,
# moves main or the tag in the deploy window.
#
# Exits non-zero if any case fails.

set -euo pipefail

for tool in dash curl python3; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "release-selftest: $tool is required but not found on PATH" >&2
    exit 1
  fi
done

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
SRC_SCRIPTS="$REPO_ROOT/scripts"

WORK_DIR="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  chmod -R u+w "$WORK_DIR" 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

FQ="$WORK_DIR/fixture-forqsite"
FQ_NOCP="$WORK_DIR/fixture-forqsite-no-cp"
SEED="$WORK_DIR/seed"
SEED_ORIGIN="$WORK_DIR/seed-origin.git"
TARGET="$WORK_DIR/target"
CONTROL_DIR="$WORK_DIR/control"
STUB_BIN="$WORK_DIR/stub-bin"
SSH_MARKER="$WORK_DIR/ssh-marker"
SSH_REFUSE="$WORK_DIR/ssh-refuse"
SSH_HOOK="$WORK_DIR/ssh-hook"
GIT_LOG="$WORK_DIR/git-subcommands"
HELPER="$WORK_DIR/helper.py"
SERVER_SCRIPT="$WORK_DIR/server.py"
ALL_OUTPUT="$WORK_DIR/all-output"
ALIAS="fixture-release-alias"
MARKER="SUBJECTMARKER-forq-7d1e"
SLUG="fixture/forqsite"
FILES3="docs/claims-manifest.json
gap-handoff.html
index.html"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export PYTHONDONTWRITEBYTECODE=1
export HOME="$WORK_DIR/home"
unset XDG_CONFIG_HOME
export GIT_AUTHOR_NAME="release-selftest" GIT_AUTHOR_EMAIL="selftest@example.invalid"
export GIT_COMMITTER_NAME="release-selftest" GIT_COMMITTER_EMAIL="selftest@example.invalid"
mkdir -p "$HOME" "$TARGET" "$CONTROL_DIR" "$STUB_BIN"
: > "$ALL_OUTPUT"

FAILURES=0
PASS_COUNT=0
# report <TOKEN> <name> <ok> <detail>: every name ends " — INFRA-021/<TOKEN>", or " — <TOKEN>"
# when the token already names its story (contains a /, e.g. INFRA-023/PARTIAL).
report() {
  local token="$1"
  case "$token" in */*) ;; *) token="INFRA-021/$token" ;; esac
  local name="$2 — $token" ok="$3" detail="$4"
  if [ "$ok" -eq 0 ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — $detail"
    FAILURES=$((FAILURES + 1))
  fi
}

at() { GIT_AUTHOR_DATE="$1T12:00:00+0000" GIT_COMMITTER_DATE="$1T12:00:00+0000" "${@:2}"; }

# =====================================================================================
# Fixture forqsite clone
# =====================================================================================
q() { git -C "$FQ" "$@"; }
qcommit() { q add -A && at "$1" git -C "$FQ" commit -q -m "$2" && q rev-parse HEAD; }

git -c init.defaultBranch=main init -q "$FQ"
printf 'fixture forqsite\n' > "$FQ/README"
qcommit 2026-01-01 "base" > /dev/null
printf 'alpha\n' > "$FQ/a.txt"
printf 'beta\n' > "$FQ/b.txt"
R="$(qcommit 2026-01-10 "release R")"
printf 'alpha\nand more\n' > "$FQ/a.txt"
T1="$(qcommit 2026-01-20 "edit a, keep alpha $MARKER")"
printf 'gamma\n' > "$FQ/c.txt"
T2="$(qcommit 2026-01-25 "add c")"
q checkout -q -b stale
printf 'no longer\n' > "$FQ/b.txt"
S="$(qcommit 2026-01-28 "remove beta $MARKER")"
q checkout -q main
q tag cp-PM9-main "$T1"
q tag cp-PM10-main "$T2"
q tag cp-PM999-rc-main "$S"
R8="${R:0:8}"
T1_8="${T1:0:8}"
T2_8="${T2:0:8}"

cp -a "$FQ" "$FQ_NOCP"
for t in cp-PM9-main cp-PM10-main cp-PM999-rc-main; do git -C "$FQ_NOCP" tag -d "$t" > /dev/null; done

# =====================================================================================
# Helper: bundles and manifest
# =====================================================================================
cat > "$HELPER" <<'PYEOF'
import importlib.util, json, os, sys

SLUG = 'fixture/forqsite'


def bt(repo):
    spec = importlib.util.spec_from_file_location(
        'bundle_template', os.path.join(repo, 'scripts', 'bundle-template.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def wrap(encoded, title):
    return ('<!doctype html><html><head><meta charset="utf-8"><title>' + title +
            '</title></head><body><script type="__bundler/template">' + encoded +
            '</script></body></html>\n')


def templates(r8):
    ref = f'{SLUG}@{r8}'
    index = ('<!doctype html><html><body>\n'
             '<nav><a href="gap-handoff.html">Known gaps</a></nav>\n'
             f'<p class="stamp">verified 2026-01-10 against {ref}</p>\n'
             '<section><p>alpha is documented</p></section>\n'
             '</body></html>\n')
    gap = ('<!doctype html><html><body><h1>Gaps</h1>\n'
           '<p>gap beta is open</p>\n'
           f'<footer>known gaps · verified against {ref} · 10 january 2026</footer>\n'
           '</body></html>\n')
    return {'index.html': index, 'gap-handoff.html': gap}


def manifest(r, r8):
    ref = f'{SLUG}@{r8}'
    ev = lambda p, s: {'path': p, 'symbol': s}
    return {
        'release': {'repo': SLUG, 'commit': r, 'committed': '2026-01-10',
                    'pinned': '2026-01-10'},
        'stamps': [
            {'id': 'S-01', 'page': 'index.html', 'location': 'header',
             'text': f'verified 2026-01-10 against {ref}', 'commit': r8,
             'date': '2026-01-10', 'scope': 'the page'},
            {'id': 'S-02', 'page': 'gap-handoff.html', 'location': 'page footer',
             'text': f'known gaps · verified against {ref} · 10 january 2026',
             'commit': r8, 'date': '2026-01-10', 'scope': 'every GAP entry'},
        ],
        'claims': [
            {'id': 'C-001', 'page': 'index.html', 'location': 'nav',
             'claim': 'the gaps list is current', 'quote': 'Known gaps',
             'evidence': [ev('b.txt', 'beta')], 'stamp': 'S-01',
             'note': 'Evidence is the union of the evidence of every claim whose stamp '
                     'is S-02, the gap-handoff.html footer stamp.'},
            {'id': 'C-002', 'page': 'index.html', 'location': 'section',
             'claim': 'alpha is documented', 'quote': 'alpha is documented',
             'evidence': [ev('a.txt', 'alpha')], 'stamp': 'S-01', 'result': 'open'},
            {'id': 'C-003', 'page': 'gap-handoff.html', 'location': 'gap beta',
             'claim': 'gap beta is open', 'quote': 'gap beta is open',
             'evidence': [ev('b.txt', 'beta')], 'stamp': 'S-02', 'result': 'open'},
        ],
    }


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == 'seed':                       # seed <repo> <r> <r8>
        repo, r, r8 = args
        mod = bt(repo)
        for page, tpl in templates(r8).items():
            with open(os.path.join(repo, page), 'w', encoding='utf-8') as f:
                f.write(wrap(mod.encode(tpl), page))
        with open(os.path.join(repo, 'docs', 'claims-manifest.json'), 'w',
                  encoding='utf-8') as f:
            f.write(json.dumps(manifest(r, r8), indent=2, ensure_ascii=False) + '\n')
    elif cmd == 'unescape-slash':           # unescape-slash <repo> <page>
        path = os.path.join(args[0], args[1])
        src = open(path, encoding='utf-8').read()
        if '\\u002F' not in src:
            sys.exit('no escaped slash')
        open(path, 'w', encoding='utf-8').write(src.replace('\\u002F', '/', 1))
    else:
        sys.exit(f'unknown helper command {cmd}')


main()
PYEOF

# =====================================================================================
# Fixture forqsite.help seed and its bare origin
# =====================================================================================
git -c init.defaultBranch=main init -q "$SEED"
mkdir -p "$SEED/scripts" "$SEED/docs"
for f in release.sh restamp.py stale-claims.py bundle-template.py deploy.sh drift-check.sh \
  make-provenance.sh read-deploy-env.sh; do
  cp "$SRC_SCRIPTS/$f" "$SEED/scripts/$f"
done
chmod +x "$SEED/scripts/release.sh" "$SEED/scripts/deploy.sh" "$SEED/scripts/drift-check.sh" \
  "$SEED/scripts/make-provenance.sh"
cp "$REPO_ROOT/.gitignore" "$SEED/.gitignore"
cat > "$SEED/scripts/fixture-selftest.sh" <<'STEOF'
#!/usr/bin/env bash
# The fixture's only selftest. FIXTURE_SELFTEST_FAIL=pre: always fails.
# FIXTURE_SELFTEST_FAIL=post: fails once the manifest differs from HEAD.
here="$(cd "$(dirname "$0")/.." && pwd)"
case "${FIXTURE_SELFTEST_FAIL:-}" in
  pre) echo "fixture-selftest: failing on request"; exit 1 ;;
  post)
    if ! git -C "$here" diff --quiet HEAD -- docs/claims-manifest.json; then
      echo "fixture-selftest: the manifest differs from HEAD"; exit 1
    fi
    ;;
esac
echo "fixture-selftest: 1 passed, 0 failed"
STEOF
printf 'fixture forqsite.help\n' > "$SEED/README"
python3 "$HELPER" seed "$SEED" "$R" "$R8"
git -C "$SEED" add -A
at 2026-01-11 git -C "$SEED" commit -q -m "fixture: pages pinned at R"
at 2026-01-12 git -C "$SEED" tag -a -m "release $SLUG@$R8" "rel-$R8"
git -c init.defaultBranch=main init -q --bare "$SEED_ORIGIN"
git -C "$SEED" push -q "$SEED_ORIGIN" main "refs/tags/rel-$R8"

# =====================================================================================
# Stubs, first on PATH: ssh (dash-backed, with a refuse mode) and a logging git
# =====================================================================================
REAL_GIT="$(command -v git)"
cat > "$STUB_BIN/ssh" <<STUB
#!/usr/bin/env bash
# Stub ssh: records the call, then either refuses like a closed port or runs the remote
# command under dash against the local target directory.
alias="\$1"
echo "invoked" >> "$SSH_MARKER"
if [ -f "$SSH_HOOK" ]; then
  mv "$SSH_HOOK" "$SSH_HOOK.ran"
  bash "$SSH_HOOK.ran" < /dev/null > /dev/null 2>&1
fi
echo "Warning: Permanently added '\$alias' (ED25519) to the list of known hosts." >&2
if [ -f "$SSH_REFUSE" ]; then
  echo "ssh: connect to host \$alias port 22: Connection refused" >&2
  exit 255
fi
shift
exec dash -c "\$1"
STUB
cat > "$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
# Logging git: records each call's subcommand, then runs the real git.
args=("\$@")
i=0
while [ "\$i" -lt "\${#args[@]}" ]; do
  case "\${args[\$i]}" in
    -C|-c|--git-dir|--work-tree|--namespace) i=\$((i + 2)) ;;
    -*) i=\$((i + 1)) ;;
    *) break ;;
  esac
done
printf '%s\n' "\${args[\$i]:-}" >> "$GIT_LOG"
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$STUB_BIN/ssh" "$STUB_BIN/git"
export PATH="$STUB_BIN:$PATH"
# Safety: no case may ever reach a real ssh.
if [ "$(command -v ssh)" != "$STUB_BIN/ssh" ]; then
  echo "release-selftest: the stub ssh is not first on PATH; refusing to run" >&2
  exit 1
fi

# =====================================================================================
# Local server on 127.0.0.1: serves the deploy target, or an override per name
# =====================================================================================
cat > "$SERVER_SCRIPT" <<'PYEOF'
import http.server
import os
import socketserver
import sys

SERVE_DIR, CONTROL_DIR, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.lstrip("/")
        override = os.path.join(CONTROL_DIR, "override-" + name)
        target = override if os.path.exists(override) else os.path.join(SERVE_DIR, name)
        if "/" in name or not os.path.isfile(target):
            self.send_response(404)
            self.end_headers()
            return
        with open(target, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        pass


class Server(socketserver.TCPServer):
    allow_reuse_address = True


with Server(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
PYEOF
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 "$SERVER_SCRIPT" "$TARGET" "$CONTROL_DIR" "$PORT" &
SERVER_PID=$!
for _ in $(seq 1 50); do
  if (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null; then
    break
  fi
  sleep 0.1
done

export FORQSITE_CLONE="$FQ"
export FORQSITE_HELP_DEPLOY_HOST="$ALIAS"
export FORQSITE_HELP_DEPLOY_DIR="$TARGET"
export FORQSITE_HELP_SITE_URL="http://127.0.0.1:${PORT}"

# =====================================================================================
# Per-case plumbing
# =====================================================================================
CASE_N=0
C=""
O=""
new_case() {
  CASE_N=$((CASE_N + 1))
  local d="$WORK_DIR/case-$CASE_N"
  mkdir -p "$d"
  cp -a "$SEED_ORIGIN" "$d/origin.git"
  git clone -q "$d/origin.git" "$d/repo"
  C="$d/repo"
  O="$d/origin.git"
  find "$TARGET" -mindepth 1 -delete
  rm -f "$CONTROL_DIR"/override-* "$SSH_MARKER" "$SSH_REFUSE" "$SSH_HOOK" "$SSH_HOOK.ran"
}

# run_release [VAR=value ...] -- <release.sh args>: runs in $C; sets OUT, ERR, RC.
run_release() {
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  : > "$GIT_LOG"
  set +e
  OUT="$(cd "$C" && env "${envs[@]}" scripts/release.sh "$@" 2> "$WORK_DIR/stderr")"
  RC=$?
  set -e
  ERR="$(cat "$WORK_DIR/stderr")"
  printf '%s\n%s\n' "$OUT" "$ERR" >> "$ALL_OUTPUT"
}

state() {
  git -C "$C" rev-parse HEAD
  git -C "$C" for-each-ref --format='%(refname) %(objectname)' refs/tags
  echo "-- origin"
  git -C "$O" for-each-ref --format='%(refname) %(objectname)'
  echo "-- status"
  git -C "$C" status --porcelain --untracked-files=no
}
snap() { BEFORE="$(state)"; rm -f "$SSH_MARKER"; }
# untouched: 0 when nothing was touched since snap, and ssh was never invoked.
untouched() {
  WHY=""
  if [ "$(state)" != "$BEFORE" ]; then WHY="HEAD, tags, origin refs or tracked status changed"; return 1; fi
  if [ -e "$SSH_MARKER" ]; then WHY="the stub ssh was invoked"; return 1; fi
  return 0
}
expect() { # expect <TOKEN> <name> <code>: exit code, and nothing touched
  local ok=0 detail=""
  if [ "$RC" -ne "$3" ]; then ok=1; detail="expected exit $3, got $RC; stdout: $OUT; stderr: $ERR"
  elif ! untouched; then ok=1; detail="$WHY"
  fi
  report "$1" "$2" "$ok" "$detail"
}
has() { [[ "$1" == *"$2"* ]]; }
served() { curl -q --globoff -s -f "http://127.0.0.1:${PORT}/$1"; }
origin_unchanged() { [ "$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')" = "$ORIGIN_BEFORE" ]; }

# =====================================================================================
# CLEAN, NOOP, LATEST — one repository
# =====================================================================================
new_case
printf 'operator note\n' > "$C/operator-notes.txt"
run_release -- --yes "$T1"
CLEAN_OUT="$OUT"
SUBJ="$(git -C "$C" log -1 --format=%s)"
BODY="$(git -C "$C" log -1 --format=%b)"
report CLEAN "clean release (exit 0)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "exit $RC; stdout: $OUT; stderr: $ERR"
want_subj="release: $SLUG@$T1_8, 3 claims: 2 untouched, 1 holds, 0 unverified"
report CLEAN "exact commit subject" "$([ "$SUBJ" = "$want_subj" ] && echo 0 || echo 1)" "got: $SUBJ"
ok=1
if grep -qxF "holds: C-002" <<< "$BODY" && grep -qF "restamp: $SLUG $R8 -> $T1_8 on " <<< "$BODY" \
  && ! grep -qF "$MARKER" <<< "$BODY"; then ok=0; fi
report CLEAN "body names restamp's line and holds: C-002, and no forqsite subject" "$ok" "body: $BODY"
report CLEAN "the commit holds exactly the three files" \
  "$([ "$(git -C "$C" diff --name-only HEAD^ HEAD | sort)" = "$FILES3" ] && echo 0 || echo 1)" \
  "got: $(git -C "$C" diff --name-only HEAD^ HEAD | tr '\n' ' ')"
ok=1
if [ "$(git -C "$C" cat-file -t "rel-$T1_8" 2>/dev/null)" = "tag" ] \
  && [ "$(git -C "$C" rev-parse "rel-$T1_8^{commit}")" = "$(git -C "$C" rev-parse HEAD)" ]; then ok=0; fi
report CLEAN "rel-<T1_8> is an annotated tag object at HEAD" "$ok" "not a tag object at HEAD"
ok=1
if [ "$(git -C "$O" rev-parse main)" = "$(git -C "$C" rev-parse HEAD)" ] \
  && [ "$(git -C "$O" rev-parse "refs/tags/rel-$T1_8" 2>/dev/null)" = "$(git -C "$C" rev-parse "refs/tags/rel-$T1_8")" ]; then ok=0; fi
report CLEAN "origin's main and tag equal the local ones" "$ok" "origin differs"
ok=1
if [ "$(served index.html | sha256sum)" = "$(git -C "$C" show HEAD:index.html | sha256sum)" ] \
  && served gap-handoff.html | grep -qF "$T1_8"; then ok=0; fi
report CLEAN "served index.html equals HEAD's; served gap-handoff.html names <T1_8>" "$ok" "served bytes differ"
report CLEAN "the untracked file is untouched" \
  "$([ "$(cat "$C/operator-notes.txt")" = "operator note" ] && [ -z "$(git -C "$C" ls-files operator-notes.txt)" ] && echo 0 || echo 1)" "changed or committed"
report CLEAN "no fetch or pull in the git log" \
  "$(grep -qxE 'fetch|pull' "$GIT_LOG" && echo 1 || echo 0)" "a fetch or pull ran"
report CLEAN "no ahead-of-origin listing when level with origin, and no forqsite subject printed" \
  "$( (has "$OUT$ERR" "ahead of origin" || has "$OUT$ERR" "$MARKER") && echo 1 || echo 0)" "stdout: $OUT"

snap
run_release -- --yes "$T1"
expect NOOP "same target again (exit 0, nothing touched)" 0
report NOOP "says already released" "$(has "$OUT" "already released" && echo 0 || echo 1)" "stdout: $OUT"

# A new deploy in the same second as the last would collide on its backup stamp.
find "$TARGET" -name '*.bak-*' -delete
find "$TARGET" -name '.deploy-verified-*' -delete
run_release -- --yes --latest-checkpoint
report LATEST "--latest-checkpoint (exit 0)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "exit $RC; stdout: $OUT; stderr: $ERR"
report LATEST "picks cp-PM10-main by version sort" \
  "$(has "$OUT" "release: target cp-PM10-main ($T2_8)" && echo 0 || echo 1)" "stdout: $OUT"
report LATEST "rel-<T2_8> is on origin" \
  "$([ "$(git -C "$O" rev-parse -q --verify "refs/tags/rel-$T2_8")" = "$(git -C "$C" rev-parse "refs/tags/rel-$T2_8")" ] && echo 0 || echo 1)" "missing on origin"
report LATEST "an empty holds list reads holds: none" \
  "$(git -C "$C" log -1 --format=%b | grep -qxF "holds: none" && echo 0 || echo 1)" "body: $(git -C "$C" log -1 --format=%b)"

# =====================================================================================
# AHEAD
# =====================================================================================
new_case
printf 'one\n' > "$C/work-one.txt"
git -C "$C" add work-one.txt
git -C "$C" commit -q -m "local work one"
ONE="$(git -C "$C" rev-parse HEAD)"
printf 'two\n' > "$C/work-two.txt"
git -C "$C" add work-two.txt
git -C "$C" commit -q -m "local work two"
TWO="$(git -C "$C" rev-parse HEAD)"
want="release: main is 2 commit(s) ahead of origin; the push will also carry:
release:   ${ONE:0:8} local work one
release:   ${TWO:0:8} local work two"
snap
run_release -- "$T1"
expect AHEAD "dry run while ahead (exit 0, nothing touched)" 0
report AHEAD "dry run lists the unpushed commits, oldest first" \
  "$([[ "$OUT" == *"$want"* ]] && echo 0 || echo 1)" "stdout: $OUT"
run_release -- --yes "$T1"
report AHEAD "release while ahead (exit 0)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "exit $RC; stdout: $OUT; stderr: $ERR"
report AHEAD "the listing comes before the restamp line" \
  "$([[ "$OUT" == *"$want"*"restamp: "* ]] && echo 0 || echo 1)" "stdout: $OUT"
report AHEAD "origin's main^ is the second local commit" \
  "$([ "$(git -C "$O" rev-parse 'main^')" = "$TWO" ] && echo 0 || echo 1)" "origin main^ differs"

# =====================================================================================
# DRYRUN
# =====================================================================================
new_case
snap
run_release -- "$T1"
expect DRYRUN "default dry run (exit 0, nothing touched)" 0
report DRYRUN "prints the would-commit subject and says nothing was written" \
  "$(has "$OUT" "release: would commit: release: $SLUG@$T1_8, 3 claims: 2 untouched, 1 holds, 0 unverified" \
     && has "$OUT" "dry run: nothing was written; run again with --yes" && echo 0 || echo 1)" "stdout: $OUT"
report DRYRUN "writes no report" "$([ ! -e "$C/.release-report.txt" ] && echo 0 || echo 1)" "report exists"

# =====================================================================================
# STALE, with --yes and without
# =====================================================================================
new_case
for mode in --yes ""; do
  snap
  rm -f "$C/.release-report.txt"
  if [ -n "$mode" ]; then run_release -- "$mode" "$S"; label="with --yes"; else run_release -- "$S"; label="dry run"; fi
  expect STALE "stale target, $label (exit 3, nothing touched)" 3
  ok=1
  if has "$OUT" "(--no-commits)" && has "$OUT" "C-003 stale" && ! grep -qE '^  commit:' <<< "$OUT" \
    && ! has "$OUT" "$MARKER" && has "$OUT" ".release-report.txt"; then ok=0; fi
  report STALE "stale target, $label: stdout is the --no-commits report, names the report file, carries no subject" "$ok" "stdout: $OUT"
  ok=1
  if [ -f "$C/.release-report.txt" ] && grep -qF "$MARKER" "$C/.release-report.txt" \
    && git -C "$C" check-ignore -q .release-report.txt \
    && [ "$(stat -c %a "$C/.release-report.txt")" = "600" ]; then ok=0; fi
  report STALE "stale target, $label: the full report holds the subjects, is mode 600 and is gitignored" "$ok" "report missing, wrong or not ignored"
done

# =====================================================================================
# DRIFT
# =====================================================================================
new_case
printf 'previous index\n' > "$TARGET/index.html"
printf 'previous gap\n' > "$TARGET/gap-handoff.html"
printf '{"previous": true}\n' > "$TARGET/site-provenance.json"
printf 'not the release\n' > "$CONTROL_DIR/override-index.html"
PRE="$(git -C "$C" rev-parse HEAD)"
ORIGIN_BEFORE="$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')"
run_release -- --yes "$T1"
report DRIFT "drift after the deploy (exit 16)" "$([ "$RC" -eq 16 ] && echo 0 || echo 1)" "exit $RC; stdout: $OUT; stderr: $ERR"
report DRIFT "origin unchanged and no push ran" \
  "$(origin_unchanged && ! grep -qx push "$GIT_LOG" && echo 0 || echo 1)" "origin changed or a push ran"
report DRIFT "the annotated tag exists locally" \
  "$([ "$(git -C "$C" cat-file -t "rel-$T1_8" 2>/dev/null)" = "tag" ] && echo 0 || echo 1)" "no tag object"
ok=1
if has "$OUT" "release:   scripts/deploy.sh --ref rel-$T1_8" && has "$OUT" "release:   scripts/drift-check.sh --ref rel-$T1_8" \
  && has "$OUT" "release:   git push --atomic origin $(git -C "$C" rev-parse HEAD):refs/heads/main $(git -C "$C" rev-parse "refs/tags/rel-$T1_8"):refs/tags/rel-$T1_8" && has "$OUT" "release:   git tag -d rel-$T1_8" \
  && has "$OUT" "release:   git reset --keep $PRE"; then ok=0; fi
report DRIFT "prints the finish and abandon steps with PRE" "$ok" "stdout: $OUT"
DSTAMP="$(sed -n 's/^stamp  *\([0-9]\{8\}T[0-9]\{6\}Z\)$/\1/p' <<< "$OUT" | head -n 1)"
report DRIFT "prints the ready-to-paste rollback command for the deploy's own stamp" \
  "$([ -n "$DSTAMP" ] && grep -qxF "release:   scripts/deploy.sh --rollback $DSTAMP" <<< "$OUT" && echo 0 || echo 1)" "stamp '$DSTAMP'; stdout: $OUT"
report DRIFT "no incomplete-set line when the rollback set is whole" \
  "$(has "$OUT" "has no backup of" && echo 1 || echo 0)" "stdout: $OUT"
report DRIFT "release.sh did not roll back: the target holds the release bytes" \
  "$(cmp -s "$TARGET/index.html" <(git -C "$C" show "rel-$T1_8:index.html") && echo 0 || echo 1)" "target differs"
rm -f "$CONTROL_DIR/override-index.html"
snap
run_release -- --yes "$T1"
expect DRIFT "rerun after the drift failure refuses as unfinished (exit 10, nothing touched)" 10
sleep 1
set +e
(cd "$C" && scripts/deploy.sh --rollback "$DSTAMP") >> "$ALL_OUTPUT" 2>&1
rb=$?
set -e
report DRIFT "the printed rollback command restores the previous files (exit 0)" \
  "$([ "$rb" -eq 0 ] && [ "$(cat "$TARGET/index.html")" = "previous index" ] && echo 0 || echo 1)" "rollback exit $rb"
new_case
printf 'not the release\n' > "$CONTROL_DIR/override-index.html"
run_release -- --yes "$T1"
DSTAMP="$(sed -n 's/^stamp  *\([0-9]\{8\}T[0-9]\{6\}Z\)$/\1/p' <<< "$OUT" | head -n 1)"
ok=1
if [ "$RC" -eq 16 ] && [ -n "$DSTAMP" ] && grep -qxF "release:   scripts/deploy.sh --rollback $DSTAMP" <<< "$OUT" \
  && has "$OUT" "backup set $DSTAMP has no backup of index.html"; then ok=0; fi
report DRIFT "empty target: exit 16 still prints the rollback command, with the incomplete-set line" "$ok" "exit $RC; stdout: $OUT"

# =====================================================================================
# DEPLOY and PUSH
# =====================================================================================
new_case
: > "$SSH_REFUSE"
ORIGIN_BEFORE="$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')"
run_release -- --yes "$T1"
report DEPLOY "deploy fails (exit 15), origin unchanged, the tag-delete step printed" \
  "$([ "$RC" -eq 15 ] && origin_unchanged && has "$OUT" "release:   git tag -d rel-$T1_8" && echo 0 || echo 1)" "exit $RC; stdout: $OUT; stderr: $ERR"

new_case
printf '#!/bin/sh\nexit 1\n' > "$O/hooks/pre-receive"
chmod +x "$O/hooks/pre-receive"
ORIGIN_BEFORE="$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')"
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 17 ] && origin_unchanged \
  && [ "$(served index.html | sha256sum)" = "$(git -C "$C" show "rel-$T1_8:index.html" | sha256sum)" ] \
  && has "$OUT" "release:   git push --atomic origin $(git -C "$C" rev-parse HEAD):refs/heads/main $(git -C "$C" rev-parse "refs/tags/rel-$T1_8"):refs/tags/rel-$T1_8"; then ok=0; fi
report PUSH "push rejected (exit 17), origin unchanged, release served, push step printed" "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

# =====================================================================================
# REFUSE
# =====================================================================================
new_case
for form in "" "--latest-checkpoint $T1" "$T1 $T2" "--bogus $T1" "--yes --dry-run $T1" \
  "--yes --yes $T1" "--dry-run --dry-run $T1" "--latest-checkpoint --latest-checkpoint" \
  "-x" ".hidden" "q\"b"; do
  snap
  # shellcheck disable=SC2086
  run_release -- $form
  expect REFUSE "usage [${form//$WORK_DIR/}] (exit 64, nothing touched)" 64
done
snap
run_release -- "q b"
expect REFUSE "usage, a target with a space (exit 64, nothing touched)" 64

snap
run_release -u FORQSITE_CLONE -- "$T1"
expect REFUSE "FORQSITE_CLONE unset (exit 2, nothing touched)" 2
snap
run_release -u FORQSITE_HELP_DEPLOY_HOST -- "$T1"
expect REFUSE "FORQSITE_HELP_DEPLOY_HOST unset (exit 2, nothing touched)" 2
snap
run_release -u FORQSITE_HELP_SITE_URL -- "$T1"
expect REFUSE "FORQSITE_HELP_SITE_URL unset (exit 2, nothing touched)" 2

git -C "$C" checkout -q -b other
snap
run_release -- "$T1"
expect REFUSE "not on main (exit 7, nothing touched)" 7
git -C "$C" checkout -q main
git -C "$C" branch -q -D other

printf 'changed\n' >> "$C/README"
snap
run_release -- "$T1"
expect REFUSE "tracked change (exit 6, nothing touched)" 6
git -C "$C" checkout -q -- README

git clone -q "$O" "$WORK_DIR/other-clone"
printf 'elsewhere\n' > "$WORK_DIR/other-clone/elsewhere.txt"
git -C "$WORK_DIR/other-clone" add elsewhere.txt
git -C "$WORK_DIR/other-clone" commit -q -m "pushed from another clone"
git -C "$WORK_DIR/other-clone" push -q origin main
TRACKING="$(git -C "$C" rev-parse refs/remotes/origin/main)"
snap
run_release -- "$T1"
expect REFUSE "behind origin (exit 8, nothing touched)" 8
report REFUSE "behind origin: the remote-tracking ref is unchanged, so nothing was fetched" \
  "$([ "$(git -C "$C" rev-parse refs/remotes/origin/main)" = "$TRACKING" ] && ! grep -qxE 'fetch|pull' "$GIT_LOG" && echo 0 || echo 1)" "origin/main moved"

new_case
git -C "$C" remote set-url origin "$WORK_DIR/nowhere.git"
snap
run_release -- "$T1"
expect REFUSE "origin points nowhere (exit 5, nothing touched)" 5
git -C "$C" remote set-url origin "$O"

snap
run_release -- 0123456789abcdef0123456789abcdef01234567
expect REFUSE "unknown target sha (exit 4, nothing touched)" 4
snap
run_release FORQSITE_CLONE="$FQ_NOCP" -- --latest-checkpoint
expect REFUSE "no cp-PM tag in the clone (exit 4, nothing touched)" 4

snap
run_release FIXTURE_SELFTEST_FAIL=pre -- --yes "$T1"
expect REFUSE "a selftest fails before the restamp (exit 9, nothing touched)" 9
report REFUSE "a failing selftest is named (exit 9)" \
  "$(has "$OUT" "selftest failed: fixture-selftest.sh" && echo 0 || echo 1)" "stdout: $OUT"

git -C "$C" tag -a -m "never pushed" rel-ffffffff
snap
run_release -- --yes "$T1"
expect REFUSE "a local rel- tag origin lacks (exit 10, nothing touched)" 10
git -C "$C" tag -d rel-ffffffff > /dev/null

new_case
python3 "$HELPER" unescape-slash "$C" index.html
git -C "$C" commit -q -am "a bundle with a literal slash"
snap
run_release -- --yes "$T1"
expect REFUSE "restamp refuses a bundle that fails verify (exit 11, nothing touched)" 11

new_case
OLD_HEAD="$(git -C "$C" rev-parse HEAD)"
TAGS_BEFORE="$(git -C "$C" for-each-ref refs/tags)"
run_release FIXTURE_SELFTEST_FAIL=post -- --yes "$T1"
ok=1
if [ "$RC" -eq 12 ] && [ "$(git -C "$C" rev-parse HEAD)" = "$OLD_HEAD" ] \
  && [ "$(git -C "$C" for-each-ref refs/tags)" = "$TAGS_BEFORE" ] && [ ! -e "$SSH_MARKER" ] \
  && has "$OUT" "release:   git restore --staged --worktree -- docs/claims-manifest.json index.html gap-handoff.html"; then ok=0; fi
report REFUSE "a selftest fails after the restamp (exit 12): no commit, no tag, no ssh, restore printed" "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

new_case
OLD_HEAD="$(git -C "$C" rev-parse HEAD)"
printf '#!/bin/sh\nexit 1\n' > "$C/.git/hooks/pre-commit"
chmod +x "$C/.git/hooks/pre-commit"
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 13 ] && [ "$(git -C "$C" rev-parse HEAD)" = "$OLD_HEAD" ] && [ ! -e "$SSH_MARKER" ]; then ok=0; fi
report REFUSE "git commit fails (exit 13): HEAD unchanged, no ssh" "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

new_case
OLD_HEAD="$(git -C "$C" rev-parse HEAD)"
: > "$C/.git/refs/tags/rel-$T1_8.lock"
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 14 ] && [ "$(git -C "$C" rev-parse 'HEAD^')" = "$OLD_HEAD" ] && [ ! -e "$SSH_MARKER" ] \
  && grep -qxF "release:   git reset --keep $OLD_HEAD" <<< "$OUT"; then ok=0; fi
report REFUSE "git tag fails (exit 14): the commit exists, no ssh, reset step printed" "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"
rm -f "$C/.git/refs/tags/rel-$T1_8.lock"
snap
run_release -- --yes "$T1"
expect REFUSE "rerun after exit 14: release.commit pins the target without its tag (exit 10, nothing touched)" 10
report REFUSE "rerun after exit 14 prints the reset step (exit 10)" \
  "$(grep -qxF "release:   git reset --keep $OLD_HEAD" <<< "$OUT" && echo 0 || echo 1)" "stdout: $OUT"

new_case
git -C "$C" tag -a -m "elsewhere" "rel-$T1_8"
git -C "$C" push -q origin "refs/tags/rel-$T1_8"
snap
run_release -- --yes "$T1"
expect REFUSE "rel-<t8> exists but release.commit differs (exit 10, nothing touched)" 10

# =====================================================================================
# PARTIAL (INFRA-023): restamp.py fails after a partial write
# =====================================================================================
# restamp.py writes both bundles at the repo root first and the manifest last, each through
# mkstemp in the file's own directory. With docs/ unwritable, both bundle renames land and
# then the manifest's mkstemp fails, so restamp exits 5: a real partial write through the
# production path. The probe tests that precondition itself (root, or a filesystem that
# ignores modes, leaves docs/ writable), and the case is skipped, never passed, without it.
refs_state() {
  git -C "$C" rev-parse HEAD
  git -C "$C" for-each-ref --format='%(refname) %(objectname)' refs/tags
  echo "-- origin"
  git -C "$O" for-each-ref --format='%(refname) %(objectname)'
}
new_case
chmod a-w "$C/docs"
if ( : > "$C/docs/.write-probe" ) 2>/dev/null; then
  rm -f "$C/docs/.write-probe"
  chmod u+w "$C/docs"
  echo "SKIP: a partial restamp write (exit 11) — INFRA-023/PARTIAL — docs/ stays writable after chmod a-w (root, or a filesystem that ignores modes)"
else
  REFS_BEFORE="$(refs_state)"
  run_release -- --yes "$T1"
  PARTIAL_STATUS="$(git -C "$C" status --porcelain --untracked-files=no)"
  ok=1
  if [ "$RC" -eq 11 ] && has "$ERR" "restamp.py exited 5" \
    && [ "$PARTIAL_STATUS" = "$(printf ' M gap-handoff.html\n M index.html')" ] \
    && [ "$(refs_state)" = "$REFS_BEFORE" ] && [ ! -e "$SSH_MARKER" ]; then ok=0; fi
  report INFRA-023/PARTIAL "a partial restamp write (exit 11): restamp.py exited 5, only the two bundles changed, HEAD, tags and origin unchanged, no ssh" \
    "$ok" "exit $RC; status: $PARTIAL_STATUS; stdout: $OUT; stderr: $ERR"
  RESTORE_LINE="$(grep -xF 'release:   git restore --staged --worktree -- .' <<< "$OUT" | head -n 1 || true)"
  report INFRA-023/PARTIAL "exit 11 after a partial write prints the restore line" \
    "$([ -n "$RESTORE_LINE" ] && echo 0 || echo 1)" "stdout: $OUT"
  RESTORE_CMD="${RESTORE_LINE#release:   }"
  set +e
  (cd "$C" && bash -c "$RESTORE_CMD") > "$WORK_DIR/partial-restore.out" 2>&1
  rrc=$?
  set -e
  ok=1
  if [ -n "$RESTORE_CMD" ] && [ "$rrc" -eq 0 ] && [ -z "$(git -C "$C" status --porcelain)" ]; then ok=0; fi
  report INFRA-023/PARTIAL "the printed restore line, run with docs/ still read-only, exits 0 and leaves a clean tree" \
    "$ok" "exit $rrc; status: $(git -C "$C" status --porcelain | tr '\n' ' ')"
  chmod u+w "$C/docs"
fi

# =====================================================================================
# PUSHURL (INFRA-023): origin is pushed where it is read
# =====================================================================================
new_case
ELSEWHERE="$(dirname "$O")/elsewhere.git"
cp -a "$O" "$ELSEWHERE"
elsewhere_refs() { git -C "$ELSEWHERE" for-each-ref --format='%(refname) %(objectname)'; }
ELSEWHERE_BEFORE="$(elsewhere_refs)"

git -C "$C" config remote.origin.pushurl "$ELSEWHERE"
snap
run_release -- --yes "$T1"
expect INFRA-023/PUSHURL "a pushurl that differs from the url (exit 2, nothing touched)" 2
ok=0
for s in "$O" "$ELSEWHERE" "$(basename "$ELSEWHERE")"; do
  if has "$OUT$ERR" "$s"; then ok=1; fi
done
has "$ERR" "remote.origin.pushurl" || ok=1
report INFRA-023/PUSHURL "the split-pushurl refusal names the key and prints neither URL" "$ok" "stdout: $OUT; stderr: $ERR"

git -C "$C" config --unset-all remote.origin.pushurl
git -C "$C" config --add remote.origin.pushurl "$O"
git -C "$C" config --add remote.origin.pushurl "$ELSEWHERE"
snap
run_release -- --yes "$T1"
expect INFRA-023/PUSHURL "two pushurls, only the second differing (exit 2, nothing touched)" 2
report INFRA-023/PUSHURL "two pushurls: the other repository's refs are unchanged" \
  "$([ "$(elsewhere_refs)" = "$ELSEWHERE_BEFORE" ] && echo 0 || echo 1)" "the other repository's refs changed"

git -C "$C" config --unset-all remote.origin.pushurl
git -C "$C" config remote.origin.pushurl "$ELSEWHERE"
snap
run_release GIT_CONFIG=/dev/null -- --yes "$T1"
expect INFRA-023/PUSHURL "a split pushurl with GIT_CONFIG=/dev/null in the environment (exit 2, nothing touched)" 2

git -C "$C" config --unset-all remote.origin.pushurl
git -C "$C" config --add remote.origin.pushurl "$O"
git -C "$C" config --add remote.origin.pushurl "$O"
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 0 ] && [ -n "$(git -C "$C" rev-parse -q --verify "refs/tags/rel-$T1_8" || true)" ] \
  && [ "$(git -C "$O" rev-parse -q --verify "refs/tags/rel-$T1_8" || true)" = "$(git -C "$C" rev-parse -q --verify "refs/tags/rel-$T1_8" || true)" ]; then ok=0; fi
report INFRA-023/PUSHURL "two pushurls both equal to the url are not refused (exit 0, origin holds rel-<T1_8>)" \
  "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"
report INFRA-023/PUSHURL "two equal pushurls: the other repository's refs are unchanged" \
  "$([ "$(elsewhere_refs)" = "$ELSEWHERE_BEFORE" ] && echo 0 || echo 1)" "the other repository's refs changed"

# =====================================================================================
# REFSPEC (INFRA-023): no remote.origin.push refspec remaps a push
# =====================================================================================
hijack_refspecs() {
  git -C "$C" config --add remote.origin.push '+refs/heads/main:refs/heads/hijack'
  git -C "$C" config --add remote.origin.push '+refs/tags/*:refs/tags/hijack/*'
}
# landed_unhijacked: origin's main is local HEAD, origin's rel-<T1_8> is the local tag
# object, and no origin ref name contains "hijack".
landed_unhijacked() {
  local tag_obj
  tag_obj="$(git -C "$C" rev-parse -q --verify "refs/tags/rel-$T1_8" || true)"
  [ -n "$tag_obj" ] \
    && [ "$(git -C "$O" rev-parse -q --verify refs/heads/main || true)" = "$(git -C "$C" rev-parse HEAD)" ] \
    && [ "$(git -C "$O" rev-parse -q --verify "refs/tags/rel-$T1_8" || true)" = "$tag_obj" ] \
    && ! git -C "$O" for-each-ref --format='%(refname)' | grep -qF hijack
}

new_case
hijack_refspecs
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 0 ] && landed_unhijacked; then ok=0; fi
report INFRA-023/REFSPEC "the release's own push with hijacking remote.origin.push refspecs (exit 0, origin's main and rel-<T1_8> equal the local ones, no hijack ref)" \
  "$ok" "exit $RC; origin refs: $(git -C "$O" for-each-ref --format='%(refname)' | tr '\n' ' ')"

new_case
hijack_refspecs
printf '#!/bin/sh\nexit 1\n' > "$O/hooks/pre-receive"
chmod +x "$O/hooks/pre-receive"
run_release -- --yes "$T1"
report INFRA-023/REFSPEC "push rejected with hijacking remote.origin.push refspecs (exit 17)" \
  "$([ "$RC" -eq 17 ] && echo 0 || echo 1)" "exit $RC; stdout: $OUT; stderr: $ERR"
rm -f "$O/hooks/pre-receive"
PUSH_LINE="$(grep -E '^release:   git push ' <<< "$OUT" | head -n 1 || true)"
PUSH_CMD="${PUSH_LINE#release:   }"
# git's own output names origin's path and is not release.sh output, so it goes to its own
# file, never to the HYGIENE capture.
set +e
(cd "$C" && bash -c "$PUSH_CMD") > "$WORK_DIR/printed-push.out" 2>&1
prc=$?
set -e
ok=1
if [ -n "$PUSH_CMD" ] && [ "$prc" -eq 0 ] && landed_unhijacked; then ok=0; fi
report INFRA-023/REFSPEC "the printed exit-17 push line, run verbatim with hijacking remote.origin.push refspecs (exit 0, origin's main and rel-<T1_8> equal the local ones, no hijack ref)" \
  "$ok" "exit $prc; line: $PUSH_LINE; origin refs: $(git -C "$O" for-each-ref --format='%(refname)' | tr '\n' ' ')"

# =====================================================================================
# EXACT (INFRA-024): the job pushes exactly the commit and the tag object it deployed
# =====================================================================================
# origin_ref <ref>: origin's object for <ref>, or nothing.
origin_ref() { git -C "$O" rev-parse -q --verify "$1" 2>/dev/null || true; }
# exact_wrappers: commit wrappers over deploy.sh and drift-check.sh. Each moves the real
# script to <name>-real.sh and, for --ref rel-* only, acts as EXACT_WRAP selects: deploy.sh
# moves the tag to a same-tree child before the real run (move-before) or repeats its
# deployed line (dup); drift-check.sh moves the tag after the real run (move-after).
exact_wrappers() {
  local s
  for s in deploy drift-check; do
    git -C "$C" mv "scripts/$s.sh" "scripts/$s-real.sh"
    cat > "$C/scripts/$s.sh" <<'WRAPEOF'
#!/usr/bin/env bash
# Selftest wrapper (INFRA-024/EXACT) over <name>-real.sh.
here="$(cd "$(dirname "$0")" && pwd)"
self="$(basename "$0" .sh)"
real="$here/$self-real.sh"
ref=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--ref" ]; then ref="$a"; fi
  prev="$a"
done
move() {
  local child
  child="$(git commit-tree -m "moved by the wrapper" -p "${ref}^{commit}" "${ref}^{tree}")"
  git tag -f -a -m "moved by the wrapper" "$ref" "$child" > /dev/null 2>&1
}
case "$self:$ref:${EXACT_WRAP:-}" in
  deploy:rel-*:move-before)
    move
    exec "$real" "$@"
    ;;
  deploy:rel-*:dup)
    rc=0
    out="$("$real" "$@")" || rc=$?
    printf '%s\n' "$out"
    grep '^deployed ' <<< "$out"
    exit "$rc"
    ;;
  drift-check:rel-*:move-after)
    rc=0
    "$real" "$@" || rc=$?
    move
    exit "$rc"
    ;;
esac
exec "$real" "$@"
WRAPEOF
    chmod +x "$C/scripts/$s.sh"
  done
  git -C "$C" add -A scripts
  git -C "$C" commit -q -m "fixture: EXACT wrappers over deploy.sh and drift-check.sh"
}

# --- the normal path
new_case
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 0 ] && [ "$(origin_ref refs/heads/main)" = "$(git -C "$C" rev-parse HEAD)" ] \
  && [ "$(origin_ref "refs/tags/rel-$T1_8")" = "$(git -C "$C" rev-parse "refs/tags/rel-$T1_8")" ] \
  && ! has "$OUT" "moved during the run"; then ok=0; fi
report INFRA-024/EXACT "normal path (exit 0): origin's main is the release commit, origin's rel-<T1_8> is the local tag object, no moved note" \
  "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

# --- main moves in the deploy window
new_case
cat > "$SSH_HOOK" <<HOOKEOF
git -C "$C" commit -q --allow-empty -m "landed on main in the deploy window"
HOOKEOF
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 0 ] && [ -e "$SSH_HOOK.ran" ] \
  && [ "$(origin_ref refs/heads/main)" = "$(git -C "$C" rev-parse "rel-$T1_8^{commit}")" ] \
  && [ "$(origin_ref refs/heads/main)" = "$(git -C "$C" rev-parse 'main^')" ] \
  && ! git -C "$O" cat-file -e "$(git -C "$C" rev-parse main)" 2>/dev/null \
  && has "$OUT" "release: note: main moved during the run; origin's main is the release commit $(git -C "$C" rev-parse 'main^')"; then ok=0; fi
report INFRA-024/EXACT "a commit added to main in the deploy window is not pushed (exit 0, origin's main is the release commit, the note printed)" \
  "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

# --- a post-commit hook commits on top of the release commit (operator ruling 3)
new_case
cat > "$C/.git/hooks/post-commit" <<'HOOKEOF'
#!/bin/sh
[ -z "${EXACT_POST_COMMIT:-}" ] || exit 0
EXACT_POST_COMMIT=1 git commit -q --allow-empty -m "a hook's commit on top of the release commit"
HOOKEOF
chmod +x "$C/.git/hooks/post-commit"
XPRE="$(git -C "$C" rev-parse HEAD)"
ORIGIN_BEFORE="$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')"
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 18 ] && [ ! -e "$SSH_MARKER" ] && ! grep -qx push "$GIT_LOG" && origin_unchanged \
  && [ -z "$(git -C "$C" rev-parse -q --verify "refs/tags/rel-$T1_8" || true)" ] \
  && has "$ERR" "is not a commit whose only parent is $XPRE" \
  && grep -qxF "release:   git reset --keep $XPRE" <<< "$OUT"; then ok=0; fi
report INFRA-024/EXACT "a post-commit hook's empty commit on top of the release commit is refused (exit 18, no ssh, no push, origin unchanged, no tag)" \
  "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

# --- the tag is re-pointed in the deploy window; the rerun; the printed recovery
new_case
cat > "$SSH_HOOK" <<HOOKEOF
cd "$C" || exit 1
git rev-parse "refs/tags/rel-$T1_8" > "$WORK_DIR/exact-saved-tag"
child="\$(git commit-tree -m "moved in the deploy window" -p "rel-$T1_8^{commit}" "rel-$T1_8^{tree}")"
git tag -f -a -m "moved in the deploy window" "rel-$T1_8" "\$child"
HOOKEOF
ORIGIN_BEFORE="$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')"
run_release -- --yes "$T1"
MOVED_OUT="$OUT"
XRC="$(git -C "$C" rev-parse HEAD)"
SAVED="$(cat "$WORK_DIR/exact-saved-tag" 2>/dev/null || true)"
ok=1
if [ "$RC" -eq 18 ] && [ -n "$SAVED" ] && origin_unchanged && ! grep -qx push "$GIT_LOG" \
  && has "$ERR" "drift-check.sh's ref line names" \
  && grep -qxF "release:   git update-ref refs/tags/rel-$T1_8 $SAVED" <<< "$OUT" \
  && grep -qxF "release:   git push --atomic origin $XRC:refs/heads/main $SAVED:refs/tags/rel-$T1_8" <<< "$OUT"; then ok=0; fi
report INFRA-024/EXACT "rel-<T1_8> re-pointed in the deploy window is caught by the drift check's ref line (exit 18, origin unchanged, no push, the update-ref and sha push lines printed)" \
  "$ok" "exit $RC; saved '$SAVED'; stdout: $OUT; stderr: $ERR"
snap
run_release -- --yes "$T1"
expect INFRA-024/EXACT "rerun after exit 18 refuses as unfinished (exit 10, nothing touched)" 10
report INFRA-024/EXACT "rerun after exit 18 prints the tag-only push by sha, naming the moved tag object" \
  "$(grep -qxF "release:   git push --atomic origin $(git -C "$C" rev-parse "refs/tags/rel-$T1_8"):refs/tags/rel-$T1_8" <<< "$OUT" && echo 0 || echo 1)" "stdout: $OUT"
# A new deploy in the same second as the last would collide on its backup stamp.
sleep 1
ok=0
detail=""
for want in "^release:   git update-ref " "^release:   scripts/deploy\\.sh --ref " \
  "^release:   scripts/drift-check\\.sh --ref " "^release:   git push "; do
  line="$(grep -E "$want" <<< "$MOVED_OUT" | head -n 1 || true)"
  if [ -z "$line" ]; then ok=1; detail="no line matching $want"; break; fi
  set +e
  (cd "$C" && bash -c "${line#release:   }") >> "$WORK_DIR/exact-recovery.out" 2>&1
  lrc=$?
  set -e
  if [ "$lrc" -ne 0 ]; then ok=1; detail="exit $lrc from: $line"; break; fi
done
if [ "$ok" -eq 0 ] && { [ "$(origin_ref refs/heads/main)" != "$XRC" ] || [ "$(origin_ref "refs/tags/rel-$T1_8")" != "$SAVED" ]; }; then
  ok=1; detail="origin's main or rel-<T1_8> is not the release commit and the saved tag object"
fi
report INFRA-024/EXACT "printed exit-18 update-ref and finish lines, run verbatim, exit 0 and land the release commit and the saved tag object on origin" \
  "$ok" "$detail"

# --- the tag is re-pointed before the deploy resolves it
new_case
exact_wrappers
ORIGIN_BEFORE="$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')"
run_release EXACT_WRAP=move-before -- --yes "$T1"
ok=1
if [ "$RC" -eq 18 ] && has "$ERR" "deploy.sh's deployed line names" && ! grep -qE '^result ' <<< "$OUT" \
  && origin_unchanged; then ok=0; fi
report INFRA-024/EXACT "rel-<T1_8> re-pointed before the deploy resolves it is caught by the deploy's deployed line (exit 18, the drift check never ran, origin unchanged)" \
  "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

# --- the deployed line is repeated
new_case
exact_wrappers
ORIGIN_BEFORE="$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')"
run_release EXACT_WRAP=dup -- --yes "$T1"
ok=1
if [ "$RC" -eq 18 ] && has "$ERR" "deploy.sh's deployed line names no single commit" && origin_unchanged; then ok=0; fi
report INFRA-024/EXACT "a repeated deployed line is no single commit (exit 18, origin unchanged)" \
  "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

# --- the tag is re-pointed after the drift check passed
new_case
exact_wrappers
run_release EXACT_WRAP=move-after -- --yes "$T1"
XRC="$(git -C "$C" rev-parse HEAD)"
ok=1
if [ "$RC" -eq 0 ] && [ "$(git -C "$O" rev-parse -q --verify "refs/tags/rel-$T1_8^{commit}" 2>/dev/null || true)" = "$XRC" ] \
  && [ "$(git -C "$C" rev-parse "rel-$T1_8^{commit}")" != "$XRC" ]; then ok=0; fi
report INFRA-024/EXACT "rel-<T1_8> re-pointed after the drift check passed is not pushed (exit 0, origin's rel-<T1_8> peels to the release commit, the local one does not)" \
  "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

# --- the tag is re-pointed as git tag writes it
new_case
cat > "$C/.git/hooks/reference-transaction" <<HOOKEOF
#!/bin/sh
[ "\$1" = committed ] || exit 0
[ -z "\${EXACT_REF_TX:-}" ] || exit 0
while read -r old new ref; do
  if [ "\$ref" = "refs/tags/rel-$T1_8" ]; then
    EXACT_REF_TX=1 git update-ref "refs/tags/rel-$T1_8" "\$(git rev-parse "refs/tags/rel-$R8")" < /dev/null
  fi
done
HOOKEOF
chmod +x "$C/.git/hooks/reference-transaction"
XPRE="$(git -C "$C" rev-parse HEAD)"
ORIGIN_BEFORE="$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')"
run_release -- --yes "$T1"
ok=1
if [ "$RC" -eq 18 ] && [ ! -e "$SSH_MARKER" ] && origin_unchanged && has "$ERR" "right after git tag" \
  && grep -qxF "release:   git tag -d rel-$T1_8" <<< "$OUT" \
  && grep -qxF "release:   git reset --keep $XPRE" <<< "$OUT"; then ok=0; fi
report INFRA-024/EXACT "rel-<T1_8> re-pointed as git tag writes it (exit 18, no ssh, origin unchanged, the abandon steps printed)" \
  "$ok" "exit $RC; stdout: $OUT; stderr: $ERR"

# --- the exit-17 line, run after main and the tag moved
new_case
printf '#!/bin/sh\nexit 1\n' > "$O/hooks/pre-receive"
chmod +x "$O/hooks/pre-receive"
run_release -- --yes "$T1"
XRC="$(git -C "$C" rev-parse HEAD)"
XOBJ="$(git -C "$C" rev-parse "refs/tags/rel-$T1_8")"
STOP_RC="$RC"
git -C "$C" commit -q --allow-empty -m "after the exit-17 stop"
git -C "$C" tag -f -a -m "moved after the exit-17 stop" "rel-$T1_8" HEAD > /dev/null 2>&1
rm -f "$O/hooks/pre-receive"
PUSH_LINE="$(grep -E '^release:   git push ' <<< "$OUT" | head -n 1 || true)"
set +e
(cd "$C" && bash -c "${PUSH_LINE#release:   }") > "$WORK_DIR/exact-printed-push.out" 2>&1
prc=$?
set -e
ok=1
if [ "$STOP_RC" -eq 17 ] && [ -n "$PUSH_LINE" ] && [ "$prc" -eq 0 ] \
  && [ "$(origin_ref refs/heads/main)" = "$XRC" ] && [ "$(origin_ref "refs/tags/rel-$T1_8")" = "$XOBJ" ]; then ok=0; fi
report INFRA-024/EXACT "printed exit-17 push line, run after main and rel-<T1_8> moved, lands the release commit and the tag object made (exit 0)" \
  "$ok" "stop exit $STOP_RC; push exit $prc; line: $PUSH_LINE"

# =====================================================================================
# HYGIENE
# =====================================================================================
ok=0
detail=""
if ! grep -qF "deployed  " "$ALL_OUTPUT"; then ok=1; detail="the captured output holds no deploy block, so the check would be vacuous"
elif grep -qF "$WORK_DIR" "$ALL_OUTPUT"; then ok=1; detail="the work-directory path was printed"
elif grep -qF "$ALIAS" "$ALL_OUTPUT"; then ok=1; detail="the ssh alias was printed"
elif grep -qF "127.0.0.1" "$ALL_OUTPUT"; then ok=1; detail="the loopback address was printed"
elif grep -qF ":${PORT}" "$ALL_OUTPUT"; then ok=1; detail="the port was printed"
fi
report HYGIENE "no work-directory path, alias, 127.0.0.1 or port in any release.sh output" "$ok" "$detail"

echo ""
echo "release-selftest: $PASS_COUNT passed, $FAILURES failed"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
exit 0
