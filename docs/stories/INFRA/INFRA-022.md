---
id: INFRA-022
rail: INFRA
title: Deploy records the commit an annotated tag points to
status: planned
phase: "14-post1"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/make-provenance.sh

touches:
  - scripts/deploy.sh
  - scripts/drift-check.sh
  - scripts/provenance-selftest.sh
  - scripts/deploy-selftest.sh
  - scripts/drift-check-selftest.sh
  - docs/architecture.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-063. The first attended release (`rel-94f5c339`, 2026-10-01) exposed it.
`deploy.sh --ref rel-94f5c339` printed `deployed 60fd0cf…`, and the drift check's `ref` line
and the served provenance sidecar both name `60fd0cf`. That sha is the annotated tag
*object*. The commit it points to is `d4c3991`. The bytes were correct, but the published
provenance claim is not a commit id, and `release.sh` always passes an annotated tag.

Resolve `--ref` to its commit (`<ref>^{commit}`) wherever a sha is recorded or printed, in
`make-provenance.sh`, `deploy.sh` and `drift-check.sh`. Add a selftest case per script that
uses an annotated tag and fails without the fix. Keep the INFRA-017 `REF_RE` check and
validate the ref before resolving it.

The live sidecar still names `60fd0cf` until the next release redeploys it. Do not hand-edit
production; the second release corrects it. Say so in the spec.

The operator chose to run this hardening phase before Phase 15 (2026-10-01), pulling these items forward from the backlog.

Peeling with `^{commit}` creates one new failure: a ref that names no commit, such as a tag of
a tree. Today `make-provenance.sh --ref <tree tag>` exits 0 and publishes the tree's sha as
`repo_commit`, with an empty date (measured on main). After the fix, `rev-parse` fails on such a
ref. If nothing catches that failure, `deploy.sh` stops halfway, after both bundles are copied,
with a transport exit code. So each script resolves the ref once, at its existing
"not tracked at the ref" refusal, and refuses there with that refusal's existing code.

## Requires

INFRA-017 is complete. It provides `REF_RE` in `deploy.sh` and `make-provenance.sh`.
INFRA-023 runs in parallel. It edits `release.sh` and the CER-064 backlog row, and touches
none of this story's scripts.

The Tests block pins the pre-story commit `da5fb0cecedbf7526c50fbbd3a4adfaf58a57ee2`, which
was main when this spec was written.

## Ensures

Given an annotated tag, each script records and prints the commit the tag points to and never
the tag object:
- `make-provenance.sh`'s `repo_commit` is that commit. `repo_ref` stays the tag name.
- `deploy.sh`'s dry-run `resolved` sha and its `deployed` line name that commit.
- `drift-check.sh`'s `ref` line names that commit.

A ref that names no commit is refused before any output, ssh or request, with the script's
existing untracked-at-the-ref code: 5, 3 and 5 respectively. Each behaviour is proven by
selftest cases tagged `INFRA-022/CER-063` that pass on the fixed tree and fail with their
script reverted to the pre-story commit. The sidecar's JSON shape is unchanged.

## Instructions

1. **Resolve once, after validation.** In each script, at the top of its existing
   tracked-at-ref check, resolve the ref:
   `git rev-parse -q --verify --end-of-options "${REF}^{commit}"`.
   - Use exactly that literal form, which the Tests block greps for. `--end-of-options` matters
     in `drift-check.sh`, which has no `REF_RE`, because without it a ref such as
     `--abbrev-ref=strict` is parsed as an option (measured on git 2.43). In the other two
     scripts it is harmless.
   - In `make-provenance.sh` and `deploy.sh` this comes after `REF_RE`.
   - On failure, print `<script>: ref ${REF} does not name a commit` to stderr and exit with
     the untracked code: `make-provenance.sh` 5 (before anything is printed), `deploy.sh` 3
     (in the dirty check, before any ssh, and skipped under `--rollback`), `drift-check.sh` 5
     (before the bundle loop, so before any fetch).
   - Every printed or recorded sha comes from this one value:
     - `make-provenance.sh`: `REPO_COMMIT`.
     - `deploy.sh`: the dry-run `(resolved …)` and `deployed  <sha>   (${REF})`. Drop the two
       bare `git rev-parse "${REF}"` calls.
     - `drift-check.sh`: `REF_FULL`, and `REF_SHORT` taken from `REF_FULL`.

   No `git rev-parse` of the bare ref may remain in the three scripts.
2. **Leave the rest alone.** These uses peel tags inside git and mean the same with a tag as
   with its commit, so they stay as they are:
   - `git cat-file -e`, `git show <ref>:<bundle>`, `git diff [--cached] <ref>`, and
     `git log -1 <ref>` (the date and subject come from the commit);
   - `drift-check.sh`'s `git rev-list <ref>` and `<match>..<ref>`.

   `deploy.sh`'s refusal when the bundles differ from the ref is `git diff` against a tree, so
   it is unaffected. No script compares the sidecar's `repo_commit` to the ref's sha. `deploy.sh`
   keeps passing `--ref "$REF"`, not the sha, to `make-provenance.sh`, so `repo_ref` stays the
   tag name.
3. **What a tag prints.**
   - `deploy.sh` already shows the ref as given in parentheses, and its line format is
     unchanged.
   - `drift-check.sh`'s `ref` line format is unchanged: full sha, short sha, and the subject,
     which was already the commit's. `release.sh` already names the tag it passed.
4. **Selftests.** Add cases whose report names end in `INFRA-022/CER-063`. Create the fixture
   tags with `git tag -a -m … rel-fixture <commit>` and `git tag -a -m … tree-fixture
   '<commit>^{tree}'`. Each annotated-tag case also fails, as a vacuity guard, if the tag
   object's sha equals the commit's. Update each selftest's header case list.
   - `provenance-selftest.sh`, after case 3a:
     - `--ref rel-fixture` exits 0. `json.load` gives `repo_commit` equal to the commit,
       `repo_ref == "rel-fixture"`, and `repo_commit_date` equal to the commit's date. The
       tag object's short sha does not appear.
     - `--ref tree-fixture` exits 5 with empty stdout.
   - `deploy-selftest.sh`, at the end, each run in a fresh, empty target:
     - `--dry-run --ref rel-fixture` exits 0 and prints
       `would deploy ref rel-fixture (resolved <commit>)`.
     - `--ref rel-fixture` exits 0, prints exactly the line `deployed  <commit>   (rel-fixture)`,
       and the target's sidecar has `repo_commit` equal to the commit.
     - In neither run does the tag object's short sha appear.
     - `--ref tree-fixture` exits 3, makes no ssh call, and says "does not name a commit".
   - `drift-check-selftest.sh`, at the end, with the tag at HEAD:
     - A matching site exits 0. Serving `index v1` exits 3 and still reports "2 commits behind
       the ref".
     - In both runs, fields 2 and 3 of the `ref` line are the commit's full and short sha, and
       the tag object's short sha does not appear.
     - `--ref tree-fixture` exits 5, and the request log is empty.
5. **Docs.**
   - Each script's header exit-code row for that code adds "the ref does not name a commit".
   - `make-provenance.sh`'s "Resolves the given ref" bullet names `<ref>^{commit}` and CER-063.
   - In `docs/architecture.md` § Deploy, drift-check and provenance scripts, add a sentence to
     the `make-provenance.sh` bullet. It contains the exact phrase "an annotated tag is recorded
     as the commit it points to", says it holds for all three outputs, and says `repo_ref` keeps
     the ref as given.
   - In `docs/cer/backlog.md`, append the following to the end of CER-063's Finding cell and
     leave the row in place:
     `**RESOLVED Phase 14-post1 — INFRA-022.** The live sidecar keeps naming the tag object until the second release redeploys it; production is not hand-edited.`

Ideology: the checks assert the invariant itself, that the recorded sha *is* the commit, and
not a proxy such as "the output contains 40 hex characters". Prose checks normalise
whitespace (CER-011). There are no whole-line `git diff` scans.

Proportionality: this spec is longer than the baseline because it changes three scripts, and
each needs its own failing-without-fix cases plus the not-a-commit refusal that peeling
introduces.

Spec-preflight warns that `REF_FULL`, `REF_RE`, `REF_SHORT` and `REPO_COMMIT` are undefined.
All four are existing shell variables in these scripts, which the scanner does not detect.

## Tests

Run from the repository root.

```bash
for t in scripts/*-selftest.sh; do bash "$t" && continue; exit 1; done
```

```bash
set -u
F=0; fail() { echo "FAIL: $*"; F=$((F + 1)); }
T=INFRA-022/CER-063
# Each case fails without the fix: a throwaway copy of scripts/ with one script reverted
# to the pre-story commit, running that script's selftest. Each copy is deleted.
PRE=da5fb0cecedbf7526c50fbbd3a4adfaf58a57ee2
mutant() {  # $1 script to revert ("" for none), $2 selftest; prints its output
  local t; t="$(mktemp -d)"; mkdir "$t/scripts"
  cp scripts/*.sh scripts/*.py "$t/scripts/"; git -C "$t" init -q
  [ -z "$1" ] || git show "$PRE:scripts/$1" > "$t/scripts/$1"
  bash "$t/scripts/$2" 2>&1; rm -rf "$t"
}
for trio in make-provenance.sh:provenance-selftest.sh:2 deploy.sh:deploy-selftest.sh:3 drift-check.sh:drift-check-selftest.sh:3; do
  s="${trio%%:*}"; rest="${trio#*:}"; st="${rest%%:*}"; min="${rest##*:}"
  out="$(mutant "" "$st")"; mut="$(mutant "$s" "$st")"
  n="$(printf '%s\n' "$out" | grep -c "^PASS: .*$T\$")"
  m="$(printf '%s\n' "$mut" | grep -c "^FAIL: .*$T ")"
  [ "$n" -ge "$min" ] || fail "$st: fewer than $min passing $T cases ($n)"
  [ "$m" -eq "$n" ] || fail "$st: $m of $n $T cases fail with $s reverted"
  printf '%s\n' "$out" | grep -q '^FAIL: ' && fail "$st has a failing case"
done

# No sha is taken from the bare ref, and the ref is validated before it is resolved.
for f in scripts/make-provenance.sh scripts/deploy.sh scripts/drift-check.sh; do
  code="$(grep -n . "$f" | grep -v '^[0-9]*:[[:space:]]*#')"
  printf '%s\n' "$code" | grep -E 'git rev-parse[^#]*\$\{?REF[}"]' | grep -vF '^{commit}' | grep -q . \
    && fail "$f takes a sha from the bare ref"
  printf '%s\n' "$code" | grep -qF -- '--end-of-options "${REF}^{commit}"' || fail "$f does not resolve \${REF}^{commit}"
  grep '^#' "$f" | sed 's/^#[[:space:]]*//' | tr '\n' ' ' | tr -s ' ' | grep -qF 'does not name a commit' \
    || fail "$f header does not state the not-a-commit refusal"
done
for f in scripts/make-provenance.sh scripts/deploy.sh; do
  code="$(grep -n . "$f" | grep -v '^[0-9]*:[[:space:]]*#')"
  re="$(printf '%s\n' "$code" | grep -m1 -F "REF_RE='" | cut -d: -f1)"
  pc="$(printf '%s\n' "$code" | grep -m1 -F '^{commit}' | cut -d: -f1)"
  [ -n "$re" ] && [ -n "$pc" ] && [ "$re" -lt "$pc" ] || fail "$f resolves the ref before the REF_RE check"
done
tr -s ' \n' ' ' < docs/architecture.md | grep -qF 'an annotated tag is recorded as the commit it points to' \
  || fail "architecture.md does not state that a tag is recorded as its commit"
row="$(grep -E '^\| CER-063 \|' docs/cer/backlog.md)"
printf '%s' "$row" | grep -qF 'RESOLVED Phase 14-post1 — INFRA-022' || fail "CER-063 not resolved"
printf '%s' "$row" | grep -qF 'until the second release redeploys it' || fail "CER-063 row does not say the live sidecar waits for the second release"
[ "$F" -eq 0 ] && echo "INFRA-022 checks: all passed" || { echo "INFRA-022 checks: $F failed"; exit 1; }
```

Acceptance: the suite is green, and the second block prints `INFRA-022 checks: all passed`.

Verification when this spec was written, run in throwaway clones that have since been deleted:
- **Against main at `da5fb0c`.** 17 checks failed: every count check, every code, header and
  doc check, and both ordering checks. The `m -eq n` equalities hold at 0 = 0 and are gated by
  the count check beside them.
- **Against a prototype of the Instructions.** The whole block passed. Reverting each script
  failed every one of its cases (2, 3 and 3), and all six selftests were green.

## Out of scope

- Correcting the live sidecar. It keeps naming the tag object `60fd0cf` until the second
  release redeploys it through `release.sh`. Production is never hand-edited, and this story
  makes no remote write.
- Changing the sidecar's JSON shape or `schema` number, adding a tag-object field, or naming
  the tag on `drift-check.sh`'s `ref` line.
- Adding `REF_RE` to `drift-check.sh`. INFRA-017 ruled it out: that ref goes only to git and
  is never published. `--end-of-options` covers the one new `rev-parse` call.
- Reading bundles through the resolved sha instead of the ref, to close the window in which a
  ref moves during a run. Nothing reports this as a defect.
- `release.sh` and CER-061, CER-062 and CER-064, which are INFRA-023 or stay in Do Later.
