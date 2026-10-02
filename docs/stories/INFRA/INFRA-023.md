---
id: INFRA-023
rail: INFRA
title: release.sh: test the partial-restamp recovery, state the environment, refuse a split push URL
status: planned
phase: "14-post1"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/release.sh

touches:
  - scripts/release-selftest.sh
  - docs/architecture.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-062, CER-064 and item (4) of CER-061. Items (1) to (3) stay open in CER-061.
- **CER-062.** Add a selftest case for the exit-11 partial-write path, the recovery
  amended into INFRA-021's spec in commit ebff15c. Make restamp fail mid-write, for example
  with a read-only `docs/`. Assert exit 11, the `git restore --staged --worktree -- .` line,
  and a clean tree after running that line.
- **CER-064.** Add one header sentence: `release.sh` unsets only the `GIT_*` variables that
  redirect the repository. Inherited `GIT_CONFIG_*`, `GIT_SSH_COMMAND` and similar variables
  apply on purpose, because the push needs the operator's ssh setup. The read-only and
  never-fetches claims therefore hold only for a benign environment.
- **CER-061 (4).** Add a precondition that refuses, with an existing configuration exit code
  or a justified new one, when `remote.origin.pushurl` is set and differs from the fetch
  URL. Otherwise the push lands somewhere `ls-remote` never reads, and every later run
  refuses with exit 10. Add a selftest case for it. The refusal must not print either URL.

The operator chose to run this hardening phase before Phase 15 (2026-10-01), pulling these items forward from the backlog.

## Requires

- INFRA-021 is complete. `scripts/release.sh` and `scripts/release-selftest.sh` are on main
  at `da5fb0c`, including the exit-11 amendment (ebff15c).
- No ordering against INFRA-022. INFRA-022 shares only `docs/architecture.md`, in a
  different paragraph, and `docs/cer/backlog.md`, in a different row.

## Ensures

- `release-selftest.sh` forces a real partial restamp write and proves three things: exit 11,
  the printed restore line, and a clean tree after running that line.
- `release.sh` refuses with exit 2 whenever any `remote.origin.pushurl` value differs from the
  first `remote.origin.url`, and prints neither URL.
- Its header carries the exact `GIT_*` sentence in Instruction 1.
- Every INFRA-021 selftest case still passes.
- `release.sh`'s code outside the new pushurl block is byte-identical to `da5fb0c`.

## Instructions

1. **CER-064: the header sentence, no code change.** In `release.sh`'s "What it does" list,
   directly after the bullet about reading the forqsite clone, add one bullet. Its text,
   whitespace-normalised, is exactly:

   > For this repository and its siblings it unsets only the GIT_* variables that point git
   > at another repository; every other inherited variable, GIT_CONFIG_* and GIT_SSH_COMMAND
   > included, applies on purpose, because the push needs the operator's ssh setup, so the
   > read-only and never-fetches claims hold only for a benign environment.

   The clone bullet stays true as written: clone reads still drop every `GIT_*`.

2. **CER-061 (4): the pushurl precondition, exit 2.**
   - **Exit code.** No new code. Exit 2 is already the configuration refusal, and a split push
     URL is a configuration error that one `git config` command fixes. Exit 5 means origin
     could not be read, which is not the case here.
   - **Header row 2.** Append: `or remote.origin.pushurl is set and any of its values differs
     from the first remote.origin.url, the one git ls-remote reads (neither URL is printed)`.
   - **Placement.** Add a new section headed exactly
     `# --- 2: origin is pushed where it is read ---…`. It goes after the
     `FORQSITE_HELP_SITE_URL` check and immediately before `# --- 5: origin, read from origin`,
     so it is the last configuration check before origin is first read. Add no other code.
   - **Reading the keys.** Read both keys NUL-separated with `mapfile -d ''`:
     - `git config -z --get-all remote.origin.url`
     - `git config -z --get-all remote.origin.pushurl`

     Append `|| true` to each, because a missing key exits 1.
   - **The rule.**
     - No pushurl: pass.
     - Any pushurl value that is not byte-equal to the **first** url value: `fail 2`. This
       covers several pushurls where only one differs. When a pushurl is set, git pushes to
       every pushurl and never to the url, so a single differing value is enough to carry the
       release where `ls-remote` does not read.
     - Every pushurl equal to the first url, duplicates included: pass. The push target is then
       the fetch target, because `insteadOf` rewrites both sides alike and `pushInsteadOf` is
       never applied to an explicit pushurl (verified on git 2.43).
   - **Why the first url.** `ls-remote` reads the first url, but `git config --get` returns the
     *last* value. Do not use `--get`.
   - **The message.** It names the key, says the push would land where `git ls-remote` never
     reads and every later run would refuse with 10, and gives the fix: run
     `git config --unset-all remote.origin.pushurl`, or make the pushurl equal to the url. It
     prints no URL and no `git config` output.
   - **architecture.md, § Deployment, Release job paragraph.** Make the refusal sentence read:
     "unless the tree is clean on `main`, the deploy configuration is present, origin is pushed
     where it is read (every `remote.origin.pushurl`, if any, equals its url), and this
     repository is not behind origin." Exit codes stay in the header.

3. **Tokens in `release-selftest.sh`.** `report()` maps a token that contains `/` to itself,
   so the new case names end ` — INFRA-023/<TOKEN>`. Every existing name keeps its
   ` — INFRA-021/<TOKEN>` ending. Add PARTIAL and PUSHURL to the header's case list.

4. **CER-062: the PARTIAL case.** Place it after the REFUSE block and before HYGIENE.
   - **Why a read-only `docs/`.** `restamp.py` writes both bundles at the repo root first and
     the manifest last. Each write goes through `mkstemp` in the file's own directory. With
     `docs/` unwritable, both bundle renames land and then the manifest's `mkstemp` fails, so
     restamp's write handler exits 5. That is a real partial write through the production
     path, and it needs no fault-injection hook in `restamp.py`, which is out of scope.
   - **Root guard.** After `chmod a-w "$C/docs"`, probe it with
     `( : > "$C/docs/.write-probe" )`. If the probe succeeds (root, or a filesystem that ignores
     modes):
     - remove the probe file;
     - restore `u+w`;
     - print `SKIP: … — INFRA-023/PARTIAL — <reason>`, and never PASS or FAIL.

     The probe tests the precondition itself rather than the uid.
   - **Otherwise,** run `--yes "$T1"` and assert:
     - exit 11;
     - stderr contains `restamp.py exited 5`;
     - `git status --porcelain --untracked-files=no` is exactly ` M gap-handoff.html` and
       ` M index.html`, which proves the write was partial;
     - HEAD, the tags and origin are unchanged, and there was no ssh;
     - stdout has the exact line `release:   git restore --staged --worktree -- .`.
   - **Then run the printed line.** Extract the command from that stdout line and run it with
     `bash -c` in `$C`, with `docs/` still read-only. Assert exit 0 and an empty
     `git status --porcelain` (untracked files included). Restore `u+w` afterwards.

5. **The PUSHURL cases.** Start a fresh case, and let `ELSEWHERE` be a copy of `$O` under the
   work directory.
   - **Split.** Set `remote.origin.pushurl=$ELSEWHERE`, then run `--yes "$T1"`.
     - `expect … 2`.
     - Stdout and stderr contain none of `$O`, `$ELSEWHERE` or its basename.
   - **Two pushurls.** Set `$O`, then `$ELSEWHERE`.
     - `expect … 2`.
     - `$ELSEWHERE`'s refs are unchanged.
   - **Equal.** Set two pushurls, both `$O`, then run `--yes "$T1"`.
     - It exits 0, and origin holds `rel-<T1_8>`.
     - Name this case so the name contains `not refused` and `exit 0`.

   HYGIENE already fails on any work-directory path in the output.

6. **CER backlog.**
   - **CER-062 and CER-064.** Append
     `**RESOLVED Phase 14-post1 — INFRA-023:** <one clause on what closed it>.`
   - **CER-061.** Append
     `Item (4) closed in Phase 14-post1 by INFRA-023: <the rule, exit 2>; items (1) to (3) stay open.`
     The row must not contain `resolved`, `superseded` or `obsolete` in any case. The marker
     grammar would read any of them as closing the whole row.

**Mutations for the reviewer.** Each must turn the selftest red. Each went red on the
prototype or is red by construction:
- **`release.sh` as it was at `da5fb0c`.** The four PUSHURL cases fail. The split push
  really lands on `ELSEWHERE`, and the equal case then exits 10, which reproduces
  CER-061 (4).
- **Exit 11 always printing "wrote nothing".** PARTIAL's restore-line and clean-tree cases
  fail.
- **Checking only the first pushurl.** The two-pushurls case fails.
- **Refusing any pushurl at all.** The equal case fails.

**Ideology.** No conflict.
- *Assert the invariant.* PARTIAL proves the partial state before it trusts the recovery, and
  runs the printed line rather than a copy of it.
- *Name the class.* No URL is printed or committed.

**Length.** This spec runs past the baseline because three CERs close here. The exact texts
and the Tests block are load-bearing. Preflight may flag `T1`, `O`, `C`, `ELSEWHERE` and
`FORQSITE_HELP_SITE_URL`. They are selftest and environment variables.

## Tests

Run from the repo root at the story's tip, as a non-root user. No real host is contacted.
`PRE` is main at `da5fb0c`.
- **Against a clone of `PRE`,** every new check failed: all seven INFRA-023 selftest cases,
  the pushurl block, the header sentence, row 2, architecture.md and the backlog rows.
- **Against the prototype copy,** the block printed `docs ok` and `ALL-OK`.

Check 2 runs PRE's own selftest from a `git archive`, so a dropped INFRA-021 case cannot pass
unnoticed.

```bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PRE=da5fb0cecedbf7526c50fbbd3a4adfaf58a57ee2
[ "$(id -u)" -ne 0 ] || { echo "FAIL: run as a non-root user (PARTIAL needs an unwritable docs/)"; exit 1; }
S=$(mktemp -d); trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "${S:?}"' EXIT

# 1. the selftest is green, and the INFRA-023 cases pass (none skipped)
bash scripts/release-selftest.sh > "$S/new.out" 2>&1 || true
tail -1 "$S/new.out" | grep -qE '^release-selftest: [0-9]+ passed, 0 failed$' || { echo "FAIL: release-selftest not green"; exit 1; }
if grep -q '^SKIP: .* — INFRA-023/' "$S/new.out"; then echo "FAIL: an INFRA-023 case was skipped"; exit 1; fi
for want in 'exit 11[^—]* — INFRA-023/PARTIAL$' 'restore line — INFRA-023/PARTIAL$' 'clean tree — INFRA-023/PARTIAL$' \
  'differs from the url \(exit 2, nothing touched\) — INFRA-023/PUSHURL$' 'neither URL — INFRA-023/PUSHURL$' \
  'two pushurls[^—]*exit 2[^—]* — INFRA-023/PUSHURL$' 'not refused[^—]*exit 0[^—]* — INFRA-023/PUSHURL$'; do
  grep -qE "^PASS: .*$want" "$S/new.out" || { echo "FAIL: no passing case matching: $want"; exit 1; }
done

# 2. every INFRA-021 case that passed at PRE still passes (PRE's own selftest, run from an archive)
mkdir "$S/pre"; git archive "$PRE" | tar -x -C "$S/pre"; git -C "$S/pre" init -q
(cd "$S/pre" && bash scripts/release-selftest.sh) > "$S/pre.out" 2>&1 || true
grep '^PASS: .* — INFRA-021/' "$S/pre.out" | sort > "$S/pre.pass"
grep '^PASS: .* — INFRA-021/' "$S/new.out" | sort > "$S/new.pass"
[ -s "$S/pre.pass" ] || { echo "FAIL: PRE's selftest produced no INFRA-021 passes"; exit 1; }
if [ -n "$(comm -23 "$S/pre.pass" "$S/new.pass")" ]; then echo "FAIL: INFRA-021 cases lost:"; comm -23 "$S/pre.pass" "$S/new.pass"; exit 1; fi

# 3. release.sh's code is PRE's plus only the pushurl block; header sentence; row 2; docs; backlog
git show "$PRE:scripts/release.sh" > "$S/release.pre"
bash scripts/release.sh --help > "$S/help"
python3 - "$S/release.pre" "$S/help" <<'PY'
import re, sys
norm = lambda s: re.sub(r'\s+', ' ', s)
body = lambda s: s[s.index('\nset -euo pipefail\n'):]
new = open('scripts/release.sh').read()
a = new.index('# --- 2: origin is pushed where it is read'); b = new.index('# --- 5: origin, read from origin')
assert 'remote.origin.pushurl' in new[a:b], 'pushurl block'
assert body(new[:a] + new[b:]) == body(open(sys.argv[1]).read()), 'code outside the pushurl block changed'
help_ = norm(open(sys.argv[2]).read())
sentence = ("For this repository and its siblings it unsets only the GIT_* variables that point git at "
            "another repository; every other inherited variable, GIT_CONFIG_* and GIT_SSH_COMMAND included, "
            "applies on purpose, because the push needs the operator's ssh setup, so the read-only and "
            "never-fetches claims hold only for a benign environment.")
assert sentence in help_, 'GIT_* header sentence'
row2 = help_[help_.index(' 2 configuration:'):help_.index(' 7 the current branch')]
assert 'remote.origin.pushurl' in row2, 'exit-code row 2'
arch = open('docs/architecture.md').read(); i = arch.index('**Release job**')
assert 'remote.origin.pushurl' in norm(arch[i:arch.index('\n\n', i)]), 'architecture Release job'
rows = {m.group(1): m.group(0) for m in re.finditer(r'^\| (CER-06[124]) \|.*$', open('docs/cer/backlog.md').read(), re.M)}
for c in ('CER-062', 'CER-064'):
    assert '**RESOLVED Phase 14-post1 — INFRA-023' in rows[c], c
assert 'INFRA-023' in rows['CER-061'] and 'Item (4) closed' in rows['CER-061'], 'CER-061 item 4'
assert not re.search(r'(?i)\b(resolved|superseded|obsolete)\b', rows['CER-061']), 'CER-061 must stay open'
print('docs ok')
PY

# 4. every selftest green; no host, local path or URL in added text (word-diff, not whole lines)
for t in scripts/*-selftest.sh; do bash "$t" > /dev/null 2>&1 || { echo "FAIL: $t"; exit 1; }; done
if git diff --word-diff=porcelain "$PRE" -- scripts/release.sh scripts/release-selftest.sh docs/architecture.md docs/cer/backlog.md \
  | grep -E '^\+[^+]' | grep -nE '/mnt/|/home/|~/|https?://'; then exit 1; fi
echo ALL-OK
```

**Acceptance.**
- The block prints `docs ok` and `ALL-OK`, and every command exits 0.
- The reviewer applies the mutations above.
- The reviewer confirms that the story's diff leaves `restamp.py`, the other scripts, both
  bundles and the manifest unchanged. INFRA-022 may merge after `PRE`, so this check cannot be
  pinned to `PRE`.

## Out of scope

- CER-061 items (1) to (3) and CER-060. They stay in Do Later.
- **`url.<base>.pushInsteadOf` with no pushurl.** It can split push from fetch too, but it is
  not checked, because it is commonly used to reach the same repository over another
  transport. This is an open question for the operator.
- **Several `remote.origin.url` values with no pushurl.** The push goes to all of them,
  including the one `ls-remote` reads, so the release is still seen.
- Unsetting or sanitising any further inherited variable. CER-064's fix is the sentence alone.
- Any change to `restamp.py`, such as a fault-injection hook for PARTIAL.
- Making PARTIAL run as root.
