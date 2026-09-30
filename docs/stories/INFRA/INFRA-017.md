---
id: INFRA-017
rail: INFRA
title: Deploy configuration safe for unattended runs
status: planned
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/deploy.sh

touches:
  - scripts/drift-check.sh
  - scripts/read-deploy-env.sh
  - scripts/make-provenance.sh
  - scripts/deploy-selftest.sh
  - scripts/drift-check-selftest.sh
  - scripts/provenance-selftest.sh
  - docs/architecture.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-015, CER-033, CER-034 and CER-035: the four input-hygiene defects that matter once
`release.sh` (INFRA-021) branches on these scripts' exit codes, rather than a person reading
their output.
- `deploy.sh` gets a usage-error exit code of its own (64, as `stale-claims.py` uses), distinct
  from "configuration missing" (CER-015).
- `make-provenance.sh --ref` is restricted to a safe character class (CER-033).
- `drift-check.sh`'s curl calls pass `-q` first, plus `--globoff` (CER-034).
- **Operator ruling 2026-09-30 for CER-035: the environment wins.** `deploy.env` fills only keys
  the environment leaves unset, and never overrides one that is set.

Update the exit-code tables in `docs/architecture.md` and each script's header. Each fix gets a
selftest case that fails without it.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

## Requires

None. This is the first story in Phase 14's ordering, and INFRA-018 edits `deploy.sh` after it.
The pre-story commit used by the Tests block is `68b39ecbb4d0b178d97ee681c6350a3b15949033`
(main when this spec was written).

## Ensures

The four fixes hold, each proven by a selftest case whose report name carries
`INFRA-017/CER-0NN`. Each case passes on the fixed tree and fails when its script is reverted
to the pre-story commit. The headers, `docs/architecture.md` and the four backlog rows state
the new behaviour, and every existing selftest still passes. The fixes are:
- `deploy.sh` exits 64 on bad usage.
- `deploy.sh` and `make-provenance.sh` refuse (64) a `--ref` outside one shared class.
- `drift-check.sh`'s curl calls ignore the user's curl configuration and do not glob.
- A key set in the environment is never overridden by `deploy.env`.

## Instructions

1. **CER-015, `deploy.sh`.** An unrecognised argument, or `--ref` with no value, prints the
   existing usage line and exits `64`. Replace the `${2:?}` form, which exits 1, with an
   explicit `$# -lt 2` check, as `drift-check.sh` has. Add a `64  usage error (…)` row to the
   header's exit-code table, written exactly as `#   64  usage error` at the start of the line.
2. **CER-033, `make-provenance.sh` and `deploy.sh`.** Both scripts define
   `REF_RE='^[A-Za-z0-9_][A-Za-z0-9._/~^-]*$'` as that literal single-quoted line, and refuse any
   `--ref` that does not match it with exit `64`. The class keeps branch, tag and sha forms plus
   `~`/`^` revision suffixes. It excludes every character JSON would need to escape, and a
   leading `-`. The refusal message names the class, never the value.
   Operator ruling 2026-09-30: dropping reflog syntax (`@{u}`, `HEAD@{1}`) and refs that start
   with `.`, `/` or `-` is accepted. The release job passes `rel-<sha>` tags and `HEAD`.
   - `make-provenance.sh`: check straight after argument parsing, before anything is printed.
     Its header claim that no field needs escaping is then true; say why, and add the class to
     its `64` row.
   - `deploy.sh`: check straight after argument parsing, before any git or ssh work. Without
     this, a bad ref would pass the dirty check, copy both bundles, and only then fail in the
     sidecar step, leaving a half-finished deploy behind a usage code. The comment next to
     `REF_RE` says that `make-provenance.sh` holds the same class.
3. **CER-034, `drift-check.sh`.** Both curl calls begin `curl -q --globoff `, with `-q` as the
   very first argument. curl ignores `-q` anywhere else; this was measured on curl 8.5. Replace
   the header note that says curl's redirect-following "is off by default" with a note that `-q`
   stops `~/.curlrc` from turning it on, and that `--globoff` takes the URL literally.
4. **CER-035, `deploy.sh`.** Reverse the fallback to `HOST="${HOST:-$DEPLOY_ENV_HOST}"`, and the
   same for `DIR`. Rewrite the header bullet and the inline comment so that neither says a file
   value overrides the environment. `drift-check.sh` reads its single key only when the
   environment leaves it unset, so it needs no code change. Fix its header bullet and inline
   comment the same way. `read-deploy-env.sh` needs no change unless its comments state a
   precedence.
5. **Selftests.** Add or rewrite these cases. Each report name ends with its token, and no other
   case carries an `INFRA-017/` token. Update each selftest's header case list.
   - `deploy-selftest.sh`:
     - **CER-035, replacing case 13f.** (f1) Environment DIR is a fresh target, environment
       HOST is unset, and the file sets both keys. Expect exit 0, bytes landed in the
       environment's DIR and not in the file's. (f2) Environment HOST is valid, environment DIR
       is unset, the file's HOST is `-oProxyCommand=false` and the file's DIR is a fresh
       target. Expect exit 0 into the file's DIR. Before the fix, the file's HOST wins and the
       alias rule refuses it with exit 2.
     - **CER-015.** Run with `--bogus`, and separately with a bare `--ref`. Expect exit 64 and
       no ssh invocation.
     - **CER-033.** Create a fixture branch named `q"b`. `--ref 'q"b'` gives exit 64, no ssh,
       and the value is absent from the output. Create a branch `rel/a-1.b_2`;
       `--dry-run --ref rel/a-1.b_2` gives exit 0.
   - `provenance-selftest.sh`, CER-033: `--ref 'q"b'` (a real branch) and `--ref -x` each give
     exit 64 with empty stdout. `--ref rel/a-1.b_2` gives exit 0, and `json.load` of the output
     yields `repo_ref == "rel/a-1.b_2"`.
   - `drift-check-selftest.sh`, CER-034:
     - **curlrc.** A scratch `CURL_HOME` holds a `.curlrc` containing `location`.
       `index.html` redirects to a fixture path that serves HEAD's `index.html` bytes. Run with
       `CURL_HOME` set for that run only, and expect exit 4 with "redirected" in the output.
       Before the fix, curl follows the redirect and the run exits 0. Add a precondition case,
       without the token, which asserts that plain `curl` under the same `CURL_HOME` gets
       `200`, so the case is not vacuous.
     - **Glob.** Serve HEAD's bundles under a literal `{g}/` directory in the served root, and
       set the site URL to `<fixture URL>/{g}`. Expect exit 0, and the request log holds the
       literal line `{g}/index.html`. Before the fix, curl requests `g/index.html`, gets a 404,
       and exits 4. Remove the directory afterwards.
6. **Docs.**
   - `docs/architecture.md` § Exit-code contract: replace "(CER-015 records where `deploy.sh`
     does not yet hold this)" with a statement that it now holds.
   - § Configuration surface: add a sentence containing the exact phrase "the file fills only
     keys the environment leaves unset".
   - `docs/cer/backlog.md`: append `**RESOLVED Phase 14 — INFRA-017.**` to the Finding cell of
     each of the four rows, leaving the rows in place.

Ideology/architecture adjustment: `docs/architecture.md` deliberately keeps no exit-code tables.
Each script's header owns its own table, so a second copy would drift. The stub's "update the
exit-code tables in `docs/architecture.md`" is therefore met by the class-level sentence in
step 6, and the tables themselves change only in the script headers.
Spec-preflight names three constants and all three are intended. `REF_RE` is created by this
story. `CURL_HOME` is curl's own environment variable. `DIR` is `deploy.sh`'s existing
variable, which the scanner misses.
Proportionality: this spec is longer than the baseline because it carries four independent
fixes across three scripts, and each fix needs its own failing-without-fix case.

## Tests

Run from the repository root.

```bash
for t in scripts/*-selftest.sh; do bash "$t" && continue; exit 1; done
```

```bash
set -u
fail() { echo "FAIL: $*"; exit 1; }
out_deploy="$(bash scripts/deploy-selftest.sh 2>&1)"
out_prov="$(bash scripts/provenance-selftest.sh 2>&1)"
out_drift="$(bash scripts/drift-check-selftest.sh 2>&1)"
for c in CER-015 CER-033 CER-035; do
  printf '%s\n' "$out_deploy" | grep -q "^PASS: .*INFRA-017/$c" || fail "no passing INFRA-017/$c case in deploy-selftest"
done
printf '%s\n' "$out_prov" | grep -q '^PASS: .*INFRA-017/CER-033' || fail "no passing INFRA-017/CER-033 case in provenance-selftest"
[ "$(printf '%s\n' "$out_drift" | grep -c '^PASS: .*INFRA-017/CER-034')" -ge 2 ] || fail "fewer than two passing INFRA-017/CER-034 cases in drift-check-selftest"

# Each case fails without its fix: a throwaway copy of scripts/ with one script reverted
# to the pre-story commit. The unreverted copy is the control. Each copy is deleted.
PRE=68b39ecbb4d0b178d97ee681c6350a3b15949033
mutant() {  # $1 script to revert ("" for the control), $2 selftest; prints its output
  local t; t="$(mktemp -d)"; mkdir "$t/scripts"
  cp scripts/*.sh scripts/*.py "$t/scripts/"; git -C "$t" init -q
  [ -z "$1" ] || git show "$PRE:scripts/$1" > "$t/scripts/$1"
  bash "$t/scripts/$2" 2>&1; local s=$?; rm -rf "$t"; return "$s"
}
for s in deploy provenance drift-check; do
  mutant "" "$s-selftest.sh" >/dev/null || fail "control copy: $s-selftest fails with no script reverted"
done
m="$(mutant deploy.sh deploy-selftest.sh)"
for c in CER-015 CER-033 CER-035; do
  printf '%s\n' "$m" | grep -q "^FAIL: .*INFRA-017/$c" || fail "deploy-selftest INFRA-017/$c case passes with deploy.sh reverted"
done
mutant make-provenance.sh provenance-selftest.sh | grep -q '^FAIL: .*INFRA-017/CER-033' \
  || fail "provenance-selftest INFRA-017/CER-033 case passes with make-provenance.sh reverted"
[ "$(mutant drift-check.sh drift-check-selftest.sh | grep -c '^FAIL: .*INFRA-017/CER-034')" -ge 2 ] \
  || fail "drift-check-selftest INFRA-017/CER-034 cases do not both fail with drift-check.sh reverted"

# Content-level checks on the current files (comment prefixes and line wraps normalised).
norm() { sed 's/^[[:space:]]*#[[:space:]]*//' "$1" | tr '\n' ' ' | tr -s ' '; }
for f in scripts/deploy.sh scripts/drift-check.sh; do
  norm "$f" | grep -qi 'overrides the environment' && fail "$f still says a file value overrides the environment"
done
grep -Eq '^#   64  usage error' scripts/deploy.sh || fail "deploy.sh exit-code table has no 64 usage-error row"
for f in scripts/deploy.sh scripts/make-provenance.sh; do
  grep -qF "'^[A-Za-z0-9_][A-Za-z0-9._/~^-]*\$'" "$f" || fail "$f does not carry the --ref class"
done
[ "$(grep -cE '\$\(curl ' scripts/drift-check.sh)" -eq 2 ] || fail "drift-check.sh does not have exactly two curl calls"
[ "$(grep -cE '\$\(curl -q --globoff ' scripts/drift-check.sh)" -eq 2 ] || fail "a drift-check.sh curl call does not begin -q --globoff"
arch="$(tr -s ' \n' ' ' < docs/architecture.md)"
printf '%s' "$arch" | grep -qF 'does not yet hold this' && fail "architecture.md still says deploy.sh does not hold the usage-code rule"
printf '%s' "$arch" | grep -qF 'fills only keys the environment leaves unset' || fail "architecture.md does not state the precedence"
for c in 015 033 034 035; do
  grep -E "^\| CER-$c \|" docs/cer/backlog.md | grep -qF 'RESOLVED Phase 14 — INFRA-017' || fail "CER-$c not resolved"
done
echo "INFRA-017 checks: all passed"
```

Acceptance: the suite is green, and the second block prints `INFRA-017 checks: all passed`.
When this spec was written, every check in the second block except the control and the
two-curl count failed against main. The whole block passed against a throwaway
implementation, which has since been deleted.

## Out of scope

- Restricting `drift-check.sh --ref`. It is passed only to git and is not published, and no CER
  covers it.
- Validating the site URL's scheme or shape beyond `--globoff`. INFRA-010 already restricts
  schemes with `--proto`.
- Rollback and the backup report for `deploy.sh`, which are INFRA-018.
- Changing `scripts/deploy.env.example`. It states no precedence.
- CER-036 and CER-047, which stay in Do Later by the operator decision of 2026-09-30.
