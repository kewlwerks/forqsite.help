#!/usr/bin/env bash
#
# drift-check-selftest.sh — exercises scripts/drift-check.sh against a throwaway
# fixture git repository and a throwaway local static server bound to 127.0.0.1,
# using a control directory to make the server return bytes that differ from the
# file it would otherwise serve on disk (the shape needed to reproduce the
# stale-inode/forbidden-proxy case locally). Contacts no host other than 127.0.0.1.
#
# Cases (see docs/stories/INFRA/INFRA-007.md § Tests):
#   1. match                   — exit 0, no "DRIFT" in output, nginx.conf line present
#   2. drift, matching commit  — exit 3, names the matching commit's short sha, subject
#                                 and commits-behind count, names the ref's short sha,
#                                 reports gap-handoff.html ok
#   3. drift, no matching commit — exit 3, states no commit in this history matches,
#                                 not presented as a tool error
#   4. forbidden proxy (stale inode) — file on disk in the served directory holds the
#                                 HEAD bytes, but the server returns different bytes;
#                                 exit 3 proves the check asserts on the request, not
#                                 the file
#   5. fetch failure (non-2xx)  — exit 4, message names the bundle and the reason, not
#                                 3; hygiene: configured base URL/host/port absent from
#                                 captured output, and the 404/HTTP reason still named
#                                 (INFRA-009)
#   6. missing config           — exit 2, message names FORQSITE_HELP_SITE_URL, no
#                                 request attempted
#   7. usage error               — exit 64, not 2 (CER-015)
#   8. connection failure (INFRA-009) — exit 4 against an ephemeral 127.0.0.1 port with
#                                 nothing listening; hygiene: configured base URL/host/
#                                 port absent, curl's own exit code/label still named.
#                                 Timeout is deliberately not a separate case — same
#                                 status -ne 0 branch, differs only in the exit-code
#                                 label, and --max-time 60 makes it a minute-long test
#                                 for no additional coverage.
#   9. redirect (INFRA-009)      — exit 4 against a 302 whose Location is a target that
#                                 is not the fixture URL; hygiene: configured base URL/
#                                 host/port AND the redirect target absent, the 3xx
#                                 status still named
#   10. hostile sidecar (INFRA-010) — the served sidecar's four fields carry ESC/CSI,
#                                 CR and BEL bytes, with the index.html claim set to
#                                 `\033[m` followed by the real served sha256; exit 6
#                                 (the raw claim disagrees even though it sanitises to
#                                 the correct hash), no control byte in the captured
#                                 output, and the removed-characters line present
#   11. file:// refused (INFRA-010) — FORQSITE_HELP_SITE_URL points at a local
#                                 directory holding planted copies of the fixture's own
#                                 HEAD bundles; exit 4, the scheme refusal is named, and
#                                 the configured path is absent from the output
#   12. oversized bundle (INFRA-010) — the server streams an unbounded body with no
#                                 Content-Length for index.html; exit 4, the size-limit
#                                 label, well before --max-time, and not "timed out"
#   13. oversized sidecar (INFRA-010) — as above but for site-provenance.json, with the
#                                 bundles otherwise matching; exit 0, and the sidecar
#                                 still reports "absent or unreadable"
#   14. config file read as data (INFRA-013, CER-024), FORQSITE_HELP_SITE_URL unset in the
#       environment unless stated:
#       a. accepted forms — the example's form (comment, blank line, double-quoted URL,
#                           the deploy keys too); `export` + single-quoted URL; a bare
#                           URL with a CRLF ending: each exit 0, result ok
#       b. payloads       — URL set to "$(touch M)" and to a backtick `touch M` in double
#                           quotes: every marker absent
#       c. command line   — line 3 is `touch M3`: exit 2, names line 3, does not print the
#                           line, M3 absent, no request made
#       e. env complete   — URL in the environment, malformed file present: exit 0 (the
#                           file is never read)
#   15. curlrc ignored (INFRA-017/CER-034) — a scratch CURL_HOME holds a .curlrc with
#                                 `location`; index.html redirects to a fixture path that
#                                 serves HEAD's index.html bytes; with CURL_HOME set for
#                                 that run only: exit 4, "redirected" in the output.
#                                 Precondition (no token): plain curl under the same
#                                 CURL_HOME follows the redirect and gets 200, so the
#                                 case is not vacuous
#   16. no URL globbing (INFRA-017/CER-034) — HEAD's bundles served under a literal
#                                 `{g}/` directory, site URL `<fixture URL>/{g}`: exit 0,
#                                 and the request log holds the literal `{g}/index.html`
#   17. resolve once (INFRA-022), on annotated fixture tags rel-fixture (at HEAD),
#       tree-fixture (a tag of HEAD's tree) and rel-move (at COMMIT3):
#       a. CER-063: --ref rel-fixture, matching site — exit 0; fields 2 and 3 of the
#                                 `ref` line are the commit's full and short sha; the
#                                 tag object's short sha absent
#       b. CER-063: --ref rel-fixture, serving `index v1` — exit 3, "2 commits behind
#                                 the ref", the same ref-line checks
#                                 (vacuity guard for a and b: tag object sha != commit)
#       c. CER-063: --ref tree-fixture — exit 5, the request log is empty, "does not
#                                 name a commit"
#       d. MOVE: --ref rel-move with a git wrapper, first on PATH for this run only,
#                                 that re-points rel-move at COMMIT2 straight after the
#                                 first git call naming it: exit 0, the ref line names
#                                 COMMIT3 (vacuity guard: the seam fired and
#                                 rel-move^{commit} is now COMMIT2)
#
# Exits non-zero if any case fails.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
DRIFT_CHECK_SH="$REPO_ROOT/scripts/drift-check.sh"

WORK_DIR="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

FIXTURE_REPO="$WORK_DIR/fixture-repo"
SERVE_DIR="$WORK_DIR/serve-dir"
CONTROL_DIR="$WORK_DIR/control-dir"
REQUEST_LOG="$WORK_DIR/request-log"
SERVER_SCRIPT="$WORK_DIR/fixture-server.py"

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

# --- Build fixture git repo: 3 commits touching index.html, 1 touching gap-handoff --
mkdir -p "$FIXTURE_REPO"
git -C "$FIXTURE_REPO" init -q
git -C "$FIXTURE_REPO" config user.email "selftest@example.invalid"
git -C "$FIXTURE_REPO" config user.name "drift-check-selftest"

printf 'index v1\n' > "$FIXTURE_REPO/index.html"
printf 'gap v1\n' > "$FIXTURE_REPO/gap-handoff.html"
git -C "$FIXTURE_REPO" add index.html gap-handoff.html
git -C "$FIXTURE_REPO" commit -q -m "fixture: initial bundles"
COMMIT1="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"

printf 'index v2\n' > "$FIXTURE_REPO/index.html"
git -C "$FIXTURE_REPO" add index.html
git -C "$FIXTURE_REPO" commit -q -m "fixture: index v2"
COMMIT2="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"

printf 'index v3\n' > "$FIXTURE_REPO/index.html"
git -C "$FIXTURE_REPO" add index.html
git -C "$FIXTURE_REPO" commit -q -m "fixture: index v3"
COMMIT3="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"

COMMIT1_SHORT="$(git -C "$FIXTURE_REPO" rev-parse --short "$COMMIT1")"
HEAD_SHORT="$(git -C "$FIXTURE_REPO" rev-parse --short HEAD)"
COMMIT1_INDEX_SHA="$(printf 'index v1\n' | sha256sum | cut -d' ' -f1)"

# --- Build served directory + control directory --------------------------------------
mkdir -p "$SERVE_DIR" "$CONTROL_DIR"
cp "$FIXTURE_REPO/index.html" "$SERVE_DIR/index.html"
cp "$FIXTURE_REPO/gap-handoff.html" "$SERVE_DIR/gap-handoff.html"

reset_control() {
  rm -f "$CONTROL_DIR"/override-* "$CONTROL_DIR"/404-* "$CONTROL_DIR"/redirect-* "$CONTROL_DIR"/stream-* 2>/dev/null || true
  : > "$REQUEST_LOG"
}
reset_control

# --- Fixture static server ------------------------------------------------------------
# Serves files from $SERVE_DIR by default. If $CONTROL_DIR/override-<name> exists, its
# bytes are served for a request to /<name> instead of the file in $SERVE_DIR — this is
# what makes the stale-inode/forbidden-proxy case reproducible locally: the file on disk
# in the served directory can hold one set of bytes while the server answers a request
# with another. If $CONTROL_DIR/404-<name> exists, a request for /<name> gets a 404. If
# $CONTROL_DIR/redirect-<name> exists, a request for /<name> gets a 302 whose Location
# is that file's contents (INFRA-009) — used to prove the redirect target is withheld
# from drift-check.sh's output rather than merely proving the base URL happens to be
# absent, its target is deliberately not the fixture URL. If $CONTROL_DIR/stream-<name>
# exists, a request for /<name> gets a 200 with no Content-Length, and the server
# writes chunks until the client disconnects (INFRA-010) — this is the shape needed to
# prove --max-filesize is enforced mid-transfer, not merely against a declared
# Content-Length a hostile origin would simply omit. Every request is logged to
# $REQUEST_LOG.
cat > "$SERVER_SCRIPT" <<'PYEOF'
import http.server
import os
import socketserver
import sys

SERVE_DIR, CONTROL_DIR, REQUEST_LOG, PORT = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.lstrip("/")
        with open(REQUEST_LOG, "a") as log:
            log.write(name + "\n")
        notfound = os.path.join(CONTROL_DIR, "404-" + name)
        if os.path.exists(notfound):
            self.send_response(404)
            self.end_headers()
            return
        redirect = os.path.join(CONTROL_DIR, "redirect-" + name)
        if os.path.exists(redirect):
            with open(redirect) as f:
                location = f.read().strip()
            self.send_response(302)
            self.send_header("Location", location)
            self.end_headers()
            return
        stream = os.path.join(CONTROL_DIR, "stream-" + name)
        if os.path.exists(stream):
            self.send_response(200)
            self.end_headers()
            try:
                while True:
                    self.wfile.write(b"x" * 65536)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        override = os.path.join(CONTROL_DIR, "override-" + name)
        target = override if os.path.exists(override) else os.path.join(SERVE_DIR, name)
        if not os.path.exists(target):
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
python3 "$SERVER_SCRIPT" "$SERVE_DIR" "$CONTROL_DIR" "$REQUEST_LOG" "$PORT" &
SERVER_PID=$!

# Wait for the port to accept a connection before running any case.
for _ in $(seq 1 50); do
  if (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null; then
    exec 3>&- 3<&-
    break
  fi
  sleep 0.1
done

FIXTURE_URL="http://127.0.0.1:${PORT}"

run_drift_check() {
  ( cd "$FIXTURE_REPO" && "$DRIFT_CHECK_SH" "$@" )
}

# =====================================================================================
# Case 1: match
# =====================================================================================
reset_control
export FORQSITE_HELP_SITE_URL="$FIXTURE_URL"

set +e
out_case1="$(run_drift_check 2>&1)"
status_case1=$?
set -e

ok=0
detail=""
if [ "$status_case1" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_case1: $out_case1"
elif printf '%s' "$out_case1" | grep -q "DRIFT"; then
  ok=1; detail="output contains DRIFT on a matching site"
elif ! printf '%s' "$out_case1" | grep -q "nginx.conf"; then
  ok=1; detail="nginx.conf not-served line missing"
fi
report "match (exit 0, no DRIFT, nginx.conf line present)" "$ok" "$detail"

# =====================================================================================
# Case 2: drift, matching commit
# =====================================================================================
reset_control
printf 'index v1\n' > "$CONTROL_DIR/override-index.html"

set +e
out_case2="$(run_drift_check 2>&1)"
status_case2=$?
set -e

ok=0
detail=""
if [ "$status_case2" -ne 3 ]; then
  ok=1; detail="expected exit 3, got $status_case2: $out_case2"
elif ! printf '%s' "$out_case2" | grep -q "$COMMIT1_SHORT"; then
  ok=1; detail="output did not name the matching commit's short sha ($COMMIT1_SHORT)"
elif ! printf '%s' "$out_case2" | grep -q "fixture: initial bundles"; then
  ok=1; detail="output did not name the matching commit's subject"
elif ! printf '%s' "$out_case2" | grep -q "2 commits behind the ref"; then
  ok=1; detail="output did not name the commits-behind count"
elif ! printf '%s' "$out_case2" | grep -q "$HEAD_SHORT"; then
  ok=1; detail="output did not name the ref's own short sha ($HEAD_SHORT)"
elif ! printf '%s' "$out_case2" | grep -q "gap-handoff.html.*ok"; then
  ok=1; detail="gap-handoff.html not reported ok"
fi
report "drift, matching commit (exit 3, names commit + count + ref, gap-handoff ok)" "$ok" "$detail"

# =====================================================================================
# Case 3: drift, no matching commit
# =====================================================================================
reset_control
printf 'index v1 mutated on the host\n' > "$CONTROL_DIR/override-index.html"

set +e
out_case3="$(run_drift_check 2>&1)"
status_case3=$?
set -e

ok=0
detail=""
if [ "$status_case3" -ne 3 ]; then
  ok=1; detail="expected exit 3, got $status_case3: $out_case3"
elif ! printf '%s' "$out_case3" | grep -q "match no commit in this history"; then
  ok=1; detail="output did not state that no commit in this history matches"
fi
report "drift, no matching commit (exit 3, states no match, not a tool error)" "$ok" "$detail"

# =====================================================================================
# Case 4: forbidden proxy (stale inode)
# =====================================================================================
reset_control
# The file on disk in the served directory holds the HEAD bytes...
on_disk_sha="$(sha256sum "$SERVE_DIR/index.html" | cut -d' ' -f1)"
head_sha="$(git -C "$FIXTURE_REPO" show HEAD:index.html | sha256sum | cut -d' ' -f1)"
# ...but the server is made to answer with the first commit's bytes instead.
printf 'index v1\n' > "$CONTROL_DIR/override-index.html"

ok=0
detail=""
if [ "$on_disk_sha" != "$head_sha" ]; then
  ok=1; detail="fixture setup broken: file on disk does not hold HEAD bytes before the case even runs"
else
  set +e
  out_case4="$(run_drift_check 2>&1)"
  status_case4=$?
  set -e
  if [ "$status_case4" -ne 3 ]; then
    ok=1; detail="expected exit 3, got $status_case4 — a check that hashed the on-disk file (which matches HEAD, sha $on_disk_sha) would wrongly report a match here; only a request-based check catches this"
  fi
fi
report "forbidden proxy / stale inode (on-disk file matches HEAD, served bytes do not — exit 3)" "$ok" "$detail"

# =====================================================================================
# Case 5: fetch failure
# =====================================================================================
reset_control
: > "$CONTROL_DIR/404-index.html"

set +e
out_case5="$(run_drift_check 2>&1)"
status_case5=$?
set -e

ok=0
detail=""
if [ "$status_case5" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_case5: $out_case5"
elif ! printf '%s' "$out_case5" | grep -q "index.html"; then
  ok=1; detail="message did not name index.html"
elif printf '%s' "$out_case5" | grep -qF "$FIXTURE_URL"; then
  ok=1; detail="output leaked the configured base URL (INFRA-009)"
elif printf '%s' "$out_case5" | grep -qF "127.0.0.1"; then
  ok=1; detail="output leaked the configured host (INFRA-009)"
elif printf '%s' "$out_case5" | grep -qF ":${PORT}"; then
  # Bare-digit grep for the port is ambiguous here (the block legitimately prints
  # other digits, e.g. an HTTP status code), so this is narrowed to the port with
  # its ":" prefix per the story's guidance.
  ok=1; detail="output leaked the configured port (INFRA-009)"
elif ! printf '%s' "$out_case5" | grep -qE "404|HTTP"; then
  ok=1; detail="output did not name the distinguishing reason (404/HTTP) — a pure-suppression fix would fail this"
fi
report "fetch failure / non-2xx (exit 4, names bundle + reason, hygiene: no base URL/host/port — INFRA-009)" "$ok" "$detail"
reset_control

# =====================================================================================
# Case 6: missing config
# =====================================================================================
reset_control
unset FORQSITE_HELP_SITE_URL || true
rm -f "$FIXTURE_REPO/scripts/deploy.env" 2>/dev/null || true

set +e
out_case6="$(run_drift_check 2>&1)"
status_case6=$?
set -e

ok=0
detail=""
if [ "$status_case6" -ne 2 ]; then
  ok=1; detail="expected exit 2, got $status_case6: $out_case6"
elif ! printf '%s' "$out_case6" | grep -q "FORQSITE_HELP_SITE_URL"; then
  ok=1; detail="message did not name FORQSITE_HELP_SITE_URL"
elif [ -s "$REQUEST_LOG" ]; then
  ok=1; detail="a request was made despite missing configuration"
fi
report "missing config (exit 2, names variable, no request attempted)" "$ok" "$detail"

export FORQSITE_HELP_SITE_URL="$FIXTURE_URL"

# =====================================================================================
# Case 7: usage error
# =====================================================================================
reset_control

set +e
out_case7="$(run_drift_check --nonsense-flag 2>&1)"
status_case7=$?
set -e

ok=0
detail=""
if [ "$status_case7" -ne 64 ]; then
  ok=1; detail="expected exit 64, got $status_case7: $out_case7"
elif [ "$status_case7" -eq 2 ]; then
  ok=1; detail="usage error shares exit code 2 with missing-config (CER-015)"
fi
report "usage error (exit 64, distinct from 2 — CER-015)" "$ok" "$detail"

# =====================================================================================
# Case 8: connection failure (INFRA-009)
# =====================================================================================
# Timeout is deliberately not exercised as a separate case: it enters the same
# `status -ne 0` branch as this connection failure and differs only in the curl
# exit-code label, while `--max-time 60` would make it a minute-long test for no
# additional coverage.
reset_control
DEAD_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
DEAD_URL="http://127.0.0.1:${DEAD_PORT}"
export FORQSITE_HELP_SITE_URL="$DEAD_URL"

set +e
out_case8="$(run_drift_check 2>&1)"
status_case8=$?
set -e

ok=0
detail=""
if [ "$status_case8" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_case8: $out_case8"
elif printf '%s' "$out_case8" | grep -qF "$DEAD_URL"; then
  ok=1; detail="output leaked the configured base URL (INFRA-009)"
elif printf '%s' "$out_case8" | grep -qF "127.0.0.1"; then
  ok=1; detail="output leaked the configured host (INFRA-009)"
elif printf '%s' "$out_case8" | grep -qF ":${DEAD_PORT}"; then
  ok=1; detail="output leaked the configured port (INFRA-009)"
elif ! printf '%s' "$out_case8" | grep -qE "curl exit|could not resolve|failed to connect|timed out"; then
  ok=1; detail="output did not name curl's own exit code/label — a pure-suppression fix would fail this"
fi
report "connection failure (exit 4, hygiene: no base URL/host/port, curl exit code/label named — INFRA-009)" "$ok" "$detail"

export FORQSITE_HELP_SITE_URL="$FIXTURE_URL"

# =====================================================================================
# Case 9: redirect (INFRA-009)
# =====================================================================================
reset_control
REDIRECT_TARGET="http://198.51.100.1/elsewhere"
printf '%s' "$REDIRECT_TARGET" > "$CONTROL_DIR/redirect-index.html"

set +e
out_case9="$(run_drift_check 2>&1)"
status_case9=$?
set -e

ok=0
detail=""
if [ "$status_case9" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_case9: $out_case9"
elif printf '%s' "$out_case9" | grep -qF "$FIXTURE_URL"; then
  ok=1; detail="output leaked the configured base URL (INFRA-009)"
elif printf '%s' "$out_case9" | grep -qF "127.0.0.1"; then
  ok=1; detail="output leaked the configured host (INFRA-009)"
elif printf '%s' "$out_case9" | grep -qF ":${PORT}"; then
  ok=1; detail="output leaked the configured port (INFRA-009)"
elif printf '%s' "$out_case9" | grep -qF "$REDIRECT_TARGET"; then
  ok=1; detail="output leaked the origin-supplied redirect target (INFRA-009)"
elif printf '%s' "$out_case9" | grep -qF "198.51.100.1"; then
  ok=1; detail="output leaked the origin-supplied redirect target's host (INFRA-009)"
elif ! printf '%s' "$out_case9" | grep -qE "30[0-9]"; then
  ok=1; detail="output did not name the 3xx status — a pure-suppression fix would fail this"
fi
report "redirect (exit 4, hygiene: no base URL/host/port/redirect target, 3xx status named — INFRA-009)" "$ok" "$detail"
reset_control

HEAD_INDEX_SHA="$(git -C "$FIXTURE_REPO" show HEAD:index.html | sha256sum | cut -d' ' -f1)"

# =====================================================================================
# Case 10: hostile sidecar (INFRA-010)
# =====================================================================================
reset_control
python3 - "$CONTROL_DIR/override-site-provenance.json" "$HEAD_INDEX_SHA" <<'PYEOF'
import sys

dst, head_index_sha = sys.argv[1], sys.argv[2]
noise = "\x1b[m\r\x07"
fake_gap_sha = "f" * 64
lines = [
    "{",
    '  "repo_commit": "' + noise + 'abc123def456",',
    '  "deployed_at": "' + noise + '2026-09-22T00:00:00Z",',
    '  "index.html": "\x1b[m' + head_index_sha + '",',
    '  "gap-handoff.html": "' + noise + fake_gap_sha + '"',
    "}",
    "",
]
with open(dst, "w") as f:
    f.write("\n".join(lines))
PYEOF

set +e
out_case10="$(run_drift_check 2>&1)"
status_case10=$?
set -e

ok=0
detail=""
stripped_case10="$(printf '%s' "$out_case10" | tr -d '\n')"
if [ "$status_case10" -ne 6 ]; then
  ok=1; detail="expected exit 6, got $status_case10: $out_case10"
elif printf '%s' "$stripped_case10" | LC_ALL=C grep -q '[[:cntrl:]]'; then
  ok=1; detail="captured output still contains a control byte (INFRA-010)"
elif ! printf '%s' "$out_case10" | grep -q "characters outside"; then
  ok=1; detail="removed-characters line not present"
fi
report "hostile sidecar (exit 6, no control bytes in output, removed-characters line present — INFRA-010)" "$ok" "$detail"
reset_control

# =====================================================================================
# Case 11: file:// refused (INFRA-010)
# =====================================================================================
reset_control
PLANT_DIR="$WORK_DIR/plant"
mkdir -p "$PLANT_DIR"
git -C "$FIXTURE_REPO" show HEAD:index.html > "$PLANT_DIR/index.html"
git -C "$FIXTURE_REPO" show HEAD:gap-handoff.html > "$PLANT_DIR/gap-handoff.html"
export FORQSITE_HELP_SITE_URL="file://$PLANT_DIR"

set +e
out_case11="$(run_drift_check 2>&1)"
status_case11=$?
set -e

ok=0
detail=""
if [ "$status_case11" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_case11: $out_case11"
elif ! printf '%s' "$out_case11" | grep -qi "scheme refused"; then
  ok=1; detail="output did not name the refused scheme (INFRA-010)"
elif printf '%s' "$out_case11" | grep -qF "$WORK_DIR"; then
  ok=1; detail="output leaked the configured path (INFRA-010)"
fi
report "file:// refused (exit 4, scheme refusal named, configured path absent — INFRA-010)" "$ok" "$detail"

export FORQSITE_HELP_SITE_URL="$FIXTURE_URL"

# =====================================================================================
# Case 12: oversized bundle (INFRA-010)
# =====================================================================================
reset_control
: > "$CONTROL_DIR/stream-index.html"

set +e
out_case12="$(run_drift_check 2>&1)"
status_case12=$?
set -e

ok=0
detail=""
if [ "$status_case12" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_case12: $out_case12"
elif ! printf '%s' "$out_case12" | grep -qi "size limit"; then
  ok=1; detail="output did not name the size-limit label (INFRA-010)"
elif printf '%s' "$out_case12" | grep -qi "timed out"; then
  ok=1; detail="fetch ran to timeout instead of being cut short by --max-filesize"
fi
report "oversized bundle (exit 4, size-limit label, not timed out — INFRA-010)" "$ok" "$detail"
reset_control

# =====================================================================================
# Case 13: oversized sidecar (INFRA-010)
# =====================================================================================
reset_control
: > "$CONTROL_DIR/stream-site-provenance.json"

set +e
out_case13="$(run_drift_check 2>&1)"
status_case13=$?
set -e

ok=0
detail=""
if [ "$status_case13" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_case13: $out_case13"
elif ! printf '%s' "$out_case13" | grep -q "absent or unreadable"; then
  ok=1; detail="output did not fall back to the absent-or-unreadable line (INFRA-010)"
fi
report "oversized sidecar (exit 0, absent-or-unreadable line — INFRA-010)" "$ok" "$detail"
reset_control

# =====================================================================================
# Case 14: scripts/deploy.env is read as KEY=value data, never executed (CER-024).
# The fixture repo has no scripts/ directory of its own, so it is created here.
# FORQSITE_HELP_SITE_URL is unset in the environment unless stated.
# =====================================================================================
ENV_FILE="$FIXTURE_REPO/scripts/deploy.env"
mkdir -p "$FIXTURE_REPO/scripts"

run_drift_check_file_only() {
  ( unset FORQSITE_HELP_SITE_URL; run_drift_check "$@" )
}

# --- 14a: accepted forms -------------------------------------------------------------
check_env_accepted() {
  local name="$1" status="$2" out="$3"
  local ok=0 detail=""
  if [ "$status" -ne 0 ]; then
    ok=1; detail="expected exit 0, got $status: $out"
  elif ! printf '%s' "$out" | grep -q "^result .*ok"; then
    ok=1; detail="no ok result line: $out"
  fi
  report "$name" "$ok" "$detail"
}

reset_control
cat > "$ENV_FILE" <<ENVEOF
# deploy.env in the example's form
FORQSITE_HELP_DEPLOY_HOST="fixture-host-alias"

FORQSITE_HELP_DEPLOY_DIR="/fixture/remote/dir"
FORQSITE_HELP_SITE_URL="$FIXTURE_URL"
ENVEOF
set +e
out_case14a1="$(run_drift_check_file_only 2>&1)"
status_case14a1=$?
set -e
check_env_accepted "config file, example form (double-quoted URL, comment, blank, other keys; exit 0)" "$status_case14a1" "$out_case14a1"

reset_control
printf "export FORQSITE_HELP_SITE_URL='%s'\n" "$FIXTURE_URL" > "$ENV_FILE"
set +e
out_case14a2="$(run_drift_check_file_only 2>&1)"
status_case14a2=$?
set -e
check_env_accepted "config file, export + single-quoted URL (exit 0)" "$status_case14a2" "$out_case14a2"

reset_control
printf 'FORQSITE_HELP_SITE_URL=%s\r\n' "$FIXTURE_URL" > "$ENV_FILE"
set +e
out_case14a3="$(run_drift_check_file_only 2>&1)"
status_case14a3=$?
set -e
check_env_accepted "config file, bare URL with CRLF ending (exit 0)" "$status_case14a3" "$out_case14a3"
rm -f "$ENV_FILE"

# --- 14b: payloads stay literal ------------------------------------------------------
# The evidence is the marker's absence, whatever the exit code.
PAYLOAD_M1="$WORK_DIR/payload-m1"
PAYLOAD_M2="$WORK_DIR/payload-m2"
out_case14b=""
for form in dollar backtick; do
  if [ "$form" = "dollar" ]; then
    marker="$PAYLOAD_M1"; payload="\$(touch $marker)"
  else
    marker="$PAYLOAD_M2"; payload="\`touch $marker\`"
  fi
  rm -f "$PAYLOAD_M1" "$PAYLOAD_M2"
  reset_control
  printf 'FORQSITE_HELP_SITE_URL="%s"\n' "$payload" > "$ENV_FILE"
  set +e
  out_payload="$(run_drift_check_file_only 2>&1)"
  set -e
  out_case14b="${out_case14b}${out_payload}"$'\n'
  ok=0
  detail=""
  if [ -e "$marker" ]; then
    ok=1; detail="payload marker created — the config file was executed: $out_payload"
  fi
  report "config file, $form payload in FORQSITE_HELP_SITE_URL stays literal (marker absent)" "$ok" "$detail"
done
rm -f "$ENV_FILE" "$PAYLOAD_M1" "$PAYLOAD_M2"

# --- 14c: a command line is refused by line number, before any request ---------------
PAYLOAD_M3="$WORK_DIR/payload-m3"
rm -f "$PAYLOAD_M3"
reset_control
{
  echo '# line 1'
  printf 'FORQSITE_HELP_SITE_URL="%s"\n' "$FIXTURE_URL"
  echo "touch $PAYLOAD_M3"
} > "$ENV_FILE"
set +e
out_case14c="$(run_drift_check_file_only 2>&1)"
status_case14c=$?
set -e
ok=0
detail=""
if [ "$status_case14c" -ne 2 ]; then
  ok=1; detail="expected exit 2, got $status_case14c: $out_case14c"
elif ! printf '%s' "$out_case14c" | grep -q "line 3"; then
  ok=1; detail="refusal does not name line 3: $out_case14c"
elif printf '%s' "$out_case14c" | grep -q "touch"; then
  ok=1; detail="refusal printed the refused line's content"
elif [ -e "$PAYLOAD_M3" ]; then
  ok=1; detail="payload marker created — the config file was executed"
elif [ -s "$REQUEST_LOG" ]; then
  ok=1; detail="a request reached the fixture server before the refusal"
fi
report "config file, command line (exit 2, names line 3, content not printed, marker absent, no request)" "$ok" "$detail"
rm -f "$ENV_FILE" "$PAYLOAD_M3"

# --- 14e: a complete environment never reads the file --------------------------------
PAYLOAD_M4="$WORK_DIR/payload-m4"
rm -f "$PAYLOAD_M4"
reset_control
printf 'this line is not KEY=value\ntouch %s\n' "$PAYLOAD_M4" > "$ENV_FILE"
set +e
out_case14e="$( export FORQSITE_HELP_SITE_URL="$FIXTURE_URL"; run_drift_check 2>&1 )"
status_case14e=$?
set -e
ok=0
detail=""
if [ "$status_case14e" -ne 0 ]; then
  ok=1; detail="expected exit 0 with the URL in the environment, got $status_case14e: $out_case14e"
elif [ -e "$PAYLOAD_M4" ]; then
  ok=1; detail="payload marker created — the config file was executed"
fi
report "config file, malformed but env complete (exit 0, file never read)" "$ok" "$detail"
rm -f "$ENV_FILE" "$PAYLOAD_M4"
reset_control

# =====================================================================================
# Case 15: the invoking user's ~/.curlrc is ignored (INFRA-017/CER-034). A .curlrc with
# `location` would make curl follow index.html's redirect to a path serving HEAD's
# bytes, and the run would report ok; with `-q` first, the redirect is a fetch failure.
# =====================================================================================
reset_control
CURLRC_HOME="$WORK_DIR/curl-home"
mkdir -p "$CURLRC_HOME"
printf 'location\n' > "$CURLRC_HOME/.curlrc"
git -C "$FIXTURE_REPO" show HEAD:index.html > "$CONTROL_DIR/override-moved-index.html"
printf '%s' "$FIXTURE_URL/moved-index.html" > "$CONTROL_DIR/redirect-index.html"

# Precondition: plain curl under this CURL_HOME really does follow the redirect.
precond_code="$(CURL_HOME="$CURLRC_HOME" curl --silent --output /dev/null --write-out '%{http_code}' "$FIXTURE_URL/index.html" || true)"
ok=0
detail=""
if [ "$precond_code" != "200" ]; then
  ok=1; detail="plain curl under the scratch CURL_HOME got $precond_code, not 200 — the curlrc case below would be vacuous"
fi
report "precondition: plain curl under the scratch CURL_HOME follows the redirect (200)" "$ok" "$detail"

set +e
out_case15="$(CURL_HOME="$CURLRC_HOME" run_drift_check 2>&1)"
status_case15=$?
set -e
ok=0
detail=""
if [ "$status_case15" -ne 4 ]; then
  ok=1; detail="expected exit 4, got $status_case15: $out_case15"
elif ! printf '%s' "$out_case15" | grep -q "redirected"; then
  ok=1; detail="output does not say the fetch was redirected: $out_case15"
fi
report "curlrc ignored (a .curlrc with location; exit 4, redirected) INFRA-017/CER-034" "$ok" "$detail"
rm -rf "$CURLRC_HOME"
reset_control

# =====================================================================================
# Case 16: the configured URL is taken literally, never globbed (INFRA-017/CER-034).
# =====================================================================================
reset_control
GLOB_DIR="$SERVE_DIR/{g}"
mkdir -p "$GLOB_DIR"
git -C "$FIXTURE_REPO" show HEAD:index.html > "$GLOB_DIR/index.html"
git -C "$FIXTURE_REPO" show HEAD:gap-handoff.html > "$GLOB_DIR/gap-handoff.html"

set +e
out_case16="$( export FORQSITE_HELP_SITE_URL="$FIXTURE_URL/{g}"; run_drift_check 2>&1 )"
status_case16=$?
set -e
ok=0
detail=""
if [ "$status_case16" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_case16: $out_case16"
elif ! grep -qxF '{g}/index.html' "$REQUEST_LOG"; then
  ok=1; detail="the request log has no literal {g}/index.html line: $(cat "$REQUEST_LOG")"
fi
report "no URL globbing (site URL ending /{g}; exit 0, literal {g}/index.html requested) INFRA-017/CER-034" "$ok" "$detail"
rm -rf "$GLOB_DIR"
reset_control

# =====================================================================================
# Case 17 (INFRA-022/CER-063, INFRA-022/MOVE): the ref is resolved to a commit once.
# Fixture tags: rel-fixture (annotated, at HEAD = COMMIT3), tree-fixture (annotated, of
# HEAD's tree), rel-move (annotated, at COMMIT3, re-pointed mid-run by the git wrapper).
# =====================================================================================
git -C "$FIXTURE_REPO" tag -a -m "fixture: release tag" rel-fixture "$COMMIT3"
git -C "$FIXTURE_REPO" tag -a -m "fixture: tag of a tree" tree-fixture "${COMMIT3}^{tree}"
git -C "$FIXTURE_REPO" tag -a -m "fixture: moving tag" rel-move "$COMMIT3"
D17_TAG_OBJ="$(git -C "$FIXTURE_REPO" rev-parse rel-fixture)"
D17_TAG_OBJ_SHORT="$(git -C "$FIXTURE_REPO" rev-parse --short rel-fixture)"
D17_COMMIT3_SHORT="$(git -C "$FIXTURE_REPO" rev-parse --short "$COMMIT3")"

# Prints fields 2 and 3 of the report's `ref` line (full sha, short sha).
d17_ref_fields() { printf '%s\n' "$1" | awk '$1 == "ref" { print $2, $3; exit }'; }

check_tag_ref_line() {  # $1 output; sets ok/detail when the ref line is wrong
  local fields
  fields="$(d17_ref_fields "$1")"
  if [ "$D17_TAG_OBJ" = "$COMMIT3" ]; then
    ok=1; detail="precondition: rel-fixture's tag object sha equals its commit, so the case is vacuous"
  elif [ "$fields" != "$COMMIT3 $D17_COMMIT3_SHORT" ]; then
    ok=1; detail="fields 2 and 3 of the ref line are '$fields', not the commit's full and short sha ($COMMIT3 $D17_COMMIT3_SHORT)"
  elif printf '%s' "$1" | grep -qF "$D17_TAG_OBJ_SHORT"; then
    ok=1; detail="the report prints the tag object's sha ($D17_TAG_OBJ_SHORT)"
  fi
}

# 17a: an annotated tag at HEAD, matching site.
reset_control
set +e
out_17a="$(run_drift_check --ref rel-fixture 2>&1)"
status_17a=$?
set -e
ok=0
detail=""
check_tag_ref_line "$out_17a"
if [ "$ok" -eq 0 ] && [ "$status_17a" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_17a: $out_17a"
fi
report "annotated tag, matching site (exit 0, the ref line names the commit, no tag object sha) INFRA-022/CER-063" "$ok" "$detail"

# 17b: an annotated tag at HEAD, served index v1.
reset_control
printf 'index v1\n' > "$CONTROL_DIR/override-index.html"
set +e
out_17b="$(run_drift_check --ref rel-fixture 2>&1)"
status_17b=$?
set -e
ok=0
detail=""
check_tag_ref_line "$out_17b"
if [ "$ok" -eq 0 ] && [ "$status_17b" -ne 3 ]; then
  ok=1; detail="expected exit 3, got $status_17b: $out_17b"
elif [ "$ok" -eq 0 ] && ! printf '%s' "$out_17b" | grep -q "2 commits behind the ref"; then
  ok=1; detail="output did not report 2 commits behind the ref: $out_17b"
fi
report "annotated tag, served index v1 (exit 3, 2 commits behind, the ref line names the commit, no tag object sha) INFRA-022/CER-063" "$ok" "$detail"
reset_control

# 17c: a ref that names no commit is refused before any fetch.
reset_control
set +e
out_17c="$(run_drift_check --ref tree-fixture 2>&1)"
status_17c=$?
set -e
ok=0
detail=""
if [ "$(git -C "$FIXTURE_REPO" cat-file -t 'tree-fixture^{}' 2>/dev/null)" != "tree" ]; then
  ok=1; detail="precondition: tree-fixture does not peel to a tree, so the case is vacuous"
elif [ "$status_17c" -ne 5 ]; then
  ok=1; detail="expected exit 5, got $status_17c: $out_17c"
elif [ -s "$REQUEST_LOG" ]; then
  ok=1; detail="a request was made: $(cat "$REQUEST_LOG")"
elif ! printf '%s' "$out_17c" | grep -qF 'does not name a commit'; then
  ok=1; detail="the refusal does not say the ref names no commit: $out_17c"
fi
report "a tag of a tree (exit 5, no request, does not name a commit) INFRA-022/CER-063" "$ok" "$detail"

# 17d (MOVE): rel-move is at COMMIT3 (the served bytes) and is re-pointed at COMMIT2
# straight after the first git call that names it. The git wrapper runs the real git
# (captured before the wrapper exists); on the first call naming rel-move while the
# trigger exists, it deletes the trigger, runs that call, then re-points rel-move at
# $MOVE_TO with `tag -f -a`, and returns the call's own status. It is first on PATH for
# this one run only, inside a subshell.
D17_REAL_GIT="$(command -v git)"
D17_WRAP_DIR="$WORK_DIR/git-wrap"
D17_TRIGGER="$WORK_DIR/move-trigger"
mkdir -p "$D17_WRAP_DIR"
cat > "$D17_WRAP_DIR/git" <<WRAP
#!/usr/bin/env bash
names_move=0
for a in "\$@"; do
  case "\$a" in *rel-move*) names_move=1 ;; esac
done
if [ "\$names_move" -eq 1 ] && [ -f "$D17_TRIGGER" ]; then
  rm -f "$D17_TRIGGER"
  status=0
  "$D17_REAL_GIT" "\$@" || status=\$?
  "$D17_REAL_GIT" tag -f -a -m "fixture: moved mid-run" rel-move "\$MOVE_TO" >/dev/null 2>&1
  exit "\$status"
fi
exec "$D17_REAL_GIT" "\$@"
WRAP
chmod +x "$D17_WRAP_DIR/git"

reset_control
: > "$D17_TRIGGER"
set +e
out_17d="$( export PATH="$D17_WRAP_DIR:$PATH"; export MOVE_TO="$COMMIT2"; run_drift_check --ref rel-move 2>&1 )"
status_17d=$?
set -e
d17_moved_to="$(git -C "$FIXTURE_REPO" rev-parse -q --verify 'rel-move^{commit}' 2>/dev/null || true)"
d17_fields="$(d17_ref_fields "$out_17d")"
ok=0
detail=""
if [ -f "$D17_TRIGGER" ]; then
  ok=1; detail="precondition: the seam never fired (no git call named rel-move)"
elif [ "$d17_moved_to" != "$COMMIT2" ]; then
  ok=1; detail="precondition: rel-move^{commit} is $d17_moved_to after the run, not the move target $COMMIT2"
elif [ "$status_17d" -ne 0 ]; then
  ok=1; detail="expected exit 0, got $status_17d: $out_17d"
elif [ "$d17_fields" != "$COMMIT3 $D17_COMMIT3_SHORT" ]; then
  ok=1; detail="the ref line names '$d17_fields', not the resolved commit ($COMMIT3 $D17_COMMIT3_SHORT)"
fi
rm -f "$D17_TRIGGER"
report "a ref moved to COMMIT2 straight after its first read (exit 0, the ref line names the resolved COMMIT3) INFRA-022/MOVE" "$ok" "$detail"
reset_control

# =====================================================================================
echo ""
echo "drift-check-selftest: $PASS_COUNT passed, $FAILURES failed"

echo ""
echo "--- captured output, all cases (for the hygiene grep) ---"
printf '%s\n' "$out_case1" "$out_case2" "$out_case3" "${out_case4:-}" "$out_case5" "$out_case6" "$out_case7" "$out_case8" "$out_case9" "$out_case10" "$out_case11" "$out_case12" "$out_case13" \
  "$out_case14a1" "$out_case14a2" "$out_case14a3" "$out_case14b" "$out_case14c" "$out_case14e" \
  "$out_case15" "$out_case16"
echo "--- end captured output ---"

if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
exit 0
