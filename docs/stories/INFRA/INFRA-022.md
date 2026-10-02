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

**Operator rulings, 2026-10-01, on the first draft of this spec:**
1. **Accepted.** A ref that names no commit, such as a tag of a tree, is refused. Each script
   uses its existing untracked-at-the-ref code: `make-provenance.sh` 5, `deploy.sh` 3,
   `drift-check.sh` 5. On main today, `make-provenance.sh --ref <tree tag>` exits 0 and
   publishes the tree's sha with an empty date. If the fix only peeled, `rev-parse` would fail on
   such a ref, and `deploy.sh` would stop with a transport code after copying both bundles.
2. **Widened.** Each script resolves the ref to a commit sha once. Everything after that is
   read through the sha, never through the ref name again: the bundle bytes, `cat-file -e`,
   `git diff`, `log`, `rev-list` and the `<match>..` count. A ref that moves mid-run then cannot
   mix two commits. `repo_ref` and `deploy.sh`'s `(ref)` parenthetical still show the name as
   given.
3. **Unchanged.** `drift-check.sh`'s `ref` line keeps its format: full sha, short sha,
   subject.

## Requires

INFRA-017 is complete. It provides `REF_RE` in `deploy.sh` and `make-provenance.sh`.
INFRA-023 runs in parallel. It edits `release.sh` and the CER-064 backlog row, and touches
none of this story's scripts.

The Tests block pins the pre-story commit `da5fb0cecedbf7526c50fbbd3a4adfaf58a57ee2`. `scripts/`
is unchanged from there to main at `132c462`, where this revision was verified.

## Ensures

Each script resolves `--ref` to a commit exactly once, after `REF_RE` where the script has one.
Every later git read and every recorded or printed sha goes through that commit, so:
- An annotated tag is recorded as the commit it points to, never as the tag object.
  - `make-provenance.sh`: `repo_commit` is that commit, and `repo_ref` stays the tag name.
  - `deploy.sh`: the dry-run `resolved` sha and the `deployed` line name that commit.
  - `drift-check.sh`: the `ref` line names that commit.
- A ref that names no commit is refused before any output, ssh call or request. The codes are
  5, 3 and 5.
- A ref that moves mid-run cannot change what the run reads or reports.

Each behaviour is proven by selftest cases tagged `INFRA-022/CER-063` or `INFRA-022/MOVE`.
Those cases pass on the fixed tree and fail when their script is reverted to the pre-story
commit. The sidecar's JSON shape is unchanged.

## Instructions

1. **Resolve once.** In each script, at the top of its existing tracked-at-ref check, resolve
   the ref with exactly `git rev-parse -q --verify --end-of-options "${REF}^{commit}"`. This
   literal appears once per script, and the Tests block greps for it.
   - `--end-of-options` matters for `drift-check.sh`, which has no `REF_RE`. Without it, a ref
     such as `--abbrev-ref=strict` is parsed as an option (measured on git 2.43).
   - On failure, print `<script>: ref ${REF} does not name a commit` to stderr and exit:
     - `make-provenance.sh`: 5, before anything is printed.
     - `deploy.sh`: 3, in the dirty check, before any ssh call. Skip it under `--rollback`.
     - `drift-check.sh`: 5, before the bundle loop, so before any fetch.
   - Store the result in `REPO_COMMIT` (`make-provenance.sh`), `COMMIT` (`deploy.sh`) or
     `REF_FULL` (`drift-check.sh`). Take `REF_SHORT` from `REF_FULL`.
2. **Read only through the sha.** Every git command after the resolution takes the resolved
   sha and never `$REF`. This covers:
   - `make-provenance.sh`: `cat-file -e`, the `log -1` date, and both `git show`s.
   - `deploy.sh`: `cat-file -e`, both `git diff`s, and the three `git show`s (dry run, local
     hash, copy). Replace the dry-run `$(git rev-parse "${REF}")` and `RESOLVED_REF` with
     `${COMMIT}`.
   - `drift-check.sh`: `cat-file -e`, `git show`, the subject `log -1`, `rev-list`, and
     `${match_commit}..${REF_FULL}`.

   `$REF` remains only in messages, in the `(ref)` parenthetical, and as `repo_ref`.
3. **`make-provenance.sh --commit <sha>`.** This is the seam between the two processes. Without
   it, `deploy.sh` hands `make-provenance.sh` the ref name, which is a second resolution.
   - `--commit <sha>` accepts only `^[0-9a-f]{40}$`. Anything else exits 64 with a message
     beginning `make-provenance.sh: --commit takes`, and the check runs straight after
     argument parsing.
   - When `--commit` is given, the script resolves `"${COMMIT_GIVEN}^{commit}"` with the same
     `rev-parse` options instead of the ref. It refuses with 5 as in step 1, and `--ref` is
     only recorded as `repo_ref`.
   - Keep the `"${REF}^{commit}"` literal on its own line in the other branch.
   - Both `deploy.sh` calls become `"$MAKE_PROVENANCE_SH" --ref "$REF" --commit "$COMMIT"`.
   - Add `--commit` to the usage line and to the 64 row of the exit-code table.
4. **Selftests.** Report names end in `INFRA-022/CER-063` or `INFRA-022/MOVE`.
   - **Fixture tags.** Create them with `git tag -a -m … <name> <commit>`: `rel-fixture`,
     `tree-fixture` (at `'<commit>^{tree}'`) and `rel-move`.
   - **Vacuity guards.** Each annotated-tag case fails if the tag object's sha equals the
     commit's. Each MOVE case fails unless the seam fired and `rel-move^{commit}` now names
     the move target.
   - **The moving-ref seam.** Each selftest writes a `git` wrapper into its work directory. It
     is put first on `PATH` for the one MOVE run only, never exported to other cases.
     - It runs the real git (whose path was captured before the wrapper existed).
     - On the first call whose arguments name `rel-move` while a trigger file exists, it
       deletes the trigger, runs that call, then runs `tag -f -a` to re-point `rel-move` at
       `$MOVE_TO`. It returns the call's own exit status.

     Why this seam: git is the only channel through which these scripts read a ref. A PATH
     stub is how the selftests already fake `ssh`. "Straight after the first git call naming
     the ref" is precisely the window the ruling closes. In a fixed script that first call is
     the resolution. In the pre-story scripts and in a peel-only fix it is a read, so any later
     read through the name sees the moved commit. In the prototype, a peel-only `drift-check.sh`
     failed its MOVE case with exit 3.
   - **`provenance-selftest.sh`**, after case 3a:
     - (CER-063) `--ref rel-fixture` exits 0. `json.load` gives `repo_commit` equal to the
       commit, `repo_ref == "rel-fixture"`, and the commit's date. The tag object's short sha
       does not appear.
     - (CER-063) `--ref tree-fixture` exits 5 with empty stdout.
     - (MOVE) `rel-move` is at HEAD and moves to COMMIT1. The run exits 0, and `repo_commit`
       and the `index.html` hash are HEAD's.
     - (MOVE) `--ref rel-fixture --commit <COMMIT1>` records COMMIT1 and its `index.html` hash
       under `repo_ref` `rel-fixture`. `--commit not-a-sha` exits 64 with `--commit takes`.
   - **`deploy-selftest.sh`**, at the end. Each run uses a fresh, empty target.
     - (CER-063) `--dry-run --ref rel-fixture` prints
       `would deploy ref rel-fixture (resolved <commit>)`.
     - (CER-063) `--ref rel-fixture` prints exactly `deployed  <commit>   (rel-fixture)`. The
       sidecar has that `repo_commit` and `repo_ref`. Neither run prints the tag object's short
       sha.
     - (CER-063) `--ref tree-fixture` exits 3, makes no ssh call, and says "does not name a
       commit".
     - (MOVE) `rel-move` is at HEAD and moves to a side commit with a different `index.html`.
       Build the side commit with `hash-object`, `mktree` and `commit-tree`, so that HEAD and
       the working tree stay put.

       The run exits 0 and prints `deployed  <HEAD>   (rel-move)`. The target's `index.html`
       is HEAD's bytes. The sidecar has HEAD's `repo_commit`, `repo_ref` `rel-move`, and HEAD's
       `index.html` hash.
   - **`drift-check-selftest.sh`**, at the end:
     - (CER-063) With the tag at HEAD, a matching site exits 0. Serving `index v1` exits 3 and
       still reports "2 commits behind the ref".
     - (CER-063) In both of those runs, fields 2 and 3 of the `ref` line are the commit's full
       and short sha, and the tag object's short sha does not appear.
     - (CER-063) `--ref tree-fixture` exits 5, and the request log is empty.
     - (MOVE) `rel-move` is at COMMIT3, the served bytes, and moves to COMMIT2. The run exits 0,
       and the `ref` line names COMMIT3.
   - Update each selftest's header case list.
5. **Docs.**
   - Each script's exit-code row for its refusal code adds "the ref does not name a commit".
   - `make-provenance.sh`'s "Resolves the given ref" bullet states the resolve-once rule and
     what `--commit` is for, and cites CER-063.
   - In `docs/architecture.md` § Deploy, drift-check and provenance scripts, add a sentence to
     the `make-provenance.sh` bullet. It contains the exact phrases "an annotated tag is
     recorded as the commit it points to" and "a ref moved mid-run cannot mix commits", says
     this holds for all three scripts, and says `repo_ref` keeps the ref as given.
   - In `docs/cer/backlog.md`, append the following to the end of CER-063's Finding cell and
     leave the row in place:
     `**RESOLVED Phase 14-post1 — INFRA-022.** The live sidecar keeps naming the tag object until the second release redeploys it; production is not hand-edited.`

Ideology: the checks assert the invariant itself, that the recorded sha *is* the resolved
commit and the bytes are that commit's. They do not assert a proxy such as "40 hex
characters". Prose checks normalise whitespace (CER-011). There are no whole-line `git diff`
scans.

Proportionality: this spec is longer than the baseline. Ruling 2 widened it to every git read
in three scripts and added a cross-process seam (`--commit`), and each script needs
failing-without-fix cases for the tag, the not-a-commit refusal and the moving ref.

Spec-preflight warns that `REF_FULL`, `REF_RE`, `REF_SHORT`, `REPO_COMMIT`, `RESOLVED_REF`,
`COMMIT`, `COMMIT_GIVEN` and `MOVE_TO` are undefined. The first five are existing shell
variables, which the scanner does not detect. This story creates the last three.

## Tests

Run from the repository root.

```bash
for t in scripts/*-selftest.sh; do bash "$t" && continue; exit 1; done
```

```bash
set -u
F=0; fail() { echo "FAIL: $*"; F=$((F + 1)); }
# Each case fails without the fix: a throwaway copy of scripts/ with one script reverted
# to the pre-story commit, running that script's selftest. Each copy is deleted.
PRE=da5fb0cecedbf7526c50fbbd3a4adfaf58a57ee2
mutant() {  # $1 script to revert ("" for none), $2 selftest; prints its output
  local t; t="$(mktemp -d)"; mkdir "$t/scripts"
  cp scripts/*.sh scripts/*.py "$t/scripts/"; git -C "$t" init -q
  [ -z "$1" ] || git show "$PRE:scripts/$1" > "$t/scripts/$1"
  bash "$t/scripts/$2" 2>&1; rm -rf "$t"
}
# script:selftest:min CER-063 cases:min MOVE cases
for row in make-provenance.sh:provenance-selftest.sh:2:2 deploy.sh:deploy-selftest.sh:3:1 drift-check.sh:drift-check-selftest.sh:3:1; do
  IFS=: read -r s st min_tag min_move <<< "$row"
  out="$(mutant "" "$st")"; mut="$(mutant "$s" "$st")"
  for pair in CER-063:$min_tag MOVE:$min_move; do
    T="INFRA-022/${pair%%:*}"; min="${pair##*:}"
    n="$(printf '%s\n' "$out" | grep -c "^PASS: .*$T\$")"
    m="$(printf '%s\n' "$mut" | grep -c "^FAIL: .*$T ")"
    [ "$n" -ge "$min" ] || fail "$st: fewer than $min passing $T cases ($n)"
    [ "$m" -eq "$n" ] || fail "$st: $m of $n $T cases fail with $s reverted"
  done
  printf '%s\n' "$out" | grep -q '^FAIL: ' && fail "$st has a failing case"
done

# The ref is resolved once, after REF_RE, and no git command reads the bare ref after that.
RESOLVE='--end-of-options "${REF}^{commit}"'
for f in scripts/make-provenance.sh scripts/deploy.sh scripts/drift-check.sh; do
  code="$(grep -n . "$f" | grep -v '^[0-9]*:[[:space:]]*#')"
  [ "$(printf '%s\n' "$code" | grep -cF -- "$RESOLVE")" -eq 1 ] || fail "$f does not resolve \${REF}^{commit} exactly once"
  printf '%s\n' "$code" | grep -E 'git [^#]*\$\{?REF[}"]' | grep -vF -- "$RESOLVE" | grep -q . \
    && fail "$f has a git command that reads the bare ref"
  grep '^#' "$f" | sed 's/^#[[:space:]]*//' | tr '\n' ' ' | tr -s ' ' | grep -qF 'does not name a commit' \
    || fail "$f header does not state the not-a-commit refusal"
done
for f in scripts/make-provenance.sh scripts/deploy.sh; do
  code="$(grep -n . "$f" | grep -v '^[0-9]*:[[:space:]]*#')"
  re="$(printf '%s\n' "$code" | grep -m1 -F "REF_RE='" | cut -d: -f1)"
  pc="$(printf '%s\n' "$code" | grep -m1 -F '^{commit}' | cut -d: -f1)"
  [ -n "$re" ] && [ -n "$pc" ] && [ "$re" -lt "$pc" ] || fail "$f resolves the ref before the REF_RE check"
done
calls="$(grep -v '^[[:space:]]*#' scripts/deploy.sh | grep -cF '"$MAKE_PROVENANCE_SH" --ref')"
pinned="$(grep -v '^[[:space:]]*#' scripts/deploy.sh | grep -cF '"$MAKE_PROVENANCE_SH" --ref "$REF" --commit "$COMMIT"')"
[ "$calls" -ge 2 ] && [ "$pinned" -eq "$calls" ] || fail "deploy.sh calls make-provenance.sh without --commit \"\$COMMIT\" ($pinned of $calls)"
arch="$(tr -s ' \n' ' ' < docs/architecture.md)"
printf '%s' "$arch" | grep -qF 'an annotated tag is recorded as the commit it points to' \
  || fail "architecture.md does not state that a tag is recorded as its commit"
printf '%s' "$arch" | grep -qF 'a ref moved mid-run cannot mix commits' \
  || fail "architecture.md does not state the resolve-once rule"
row="$(grep -E '^\| CER-063 \|' docs/cer/backlog.md)"
printf '%s' "$row" | grep -qF 'RESOLVED Phase 14-post1 — INFRA-022' || fail "CER-063 not resolved"
printf '%s' "$row" | grep -qF 'until the second release redeploys it' || fail "CER-063 row does not say the live sidecar waits for the second release"
[ "$F" -eq 0 ] && echo "INFRA-022 checks: all passed" || { echo "INFRA-022 checks: $F failed"; exit 1; }
```

Acceptance: the suite is green, and the second block prints `INFRA-022 checks: all passed`.

Verification of this revision, run in throwaway clones that have since been deleted:
- **Against main at `132c462`.** 22 checks failed: every count, code, header and doc check,
  both ordering checks, and the `--commit` check. The `m -eq n` equalities hold at 0 = 0 and are
  gated by the count check beside them.
- **Against a prototype of the Instructions.** The whole block passed, and all six selftests
  were green. Reverting each script failed every one of its cases: provenance 2 + 2, deploy
  3 + 1, drift-check 3 + 1.

## Out of scope

- Correcting the live sidecar. It keeps naming the tag object `60fd0cf` until the second
  release redeploys it through `release.sh`. Production is never hand-edited, and this story
  makes no remote write.
- Changing the sidecar's JSON shape or `schema` number, adding a tag-object field, or changing
  `drift-check.sh`'s `ref` line format (ruling 3).
- Adding `REF_RE` to `drift-check.sh`. INFRA-017 ruled it out: that ref goes only to git and
  is never published. `--end-of-options` covers the one `rev-parse` call that names it.
- Detecting or refusing a ref that moved during a run. The ruling asks only that a run not mix
  commits, and it reports the commit it resolved.
- `release.sh` and CER-061, CER-062 and CER-064, which are INFRA-023 or stay in Do Later.
