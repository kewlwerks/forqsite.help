---
id: INFRA-019
rail: INFRA
title: Checker hardening and a paste-safe report
status: planned
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/stale-claims.py

touches:
  - scripts/stale-claims-selftest.sh
  - README.md
  - docs/architecture.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-052 to CER-055 before the checker becomes a job's dependency.
- Pass `--` before `ls-tree` paths (CER-053).
- Scrub `GIT_*` from the child environment, except the variables the script itself sets, and
  pass `--no-ext-diff --no-textconv` wherever git can produce a patch (CER-054).
- Add selftest cases for exit 5 (CER-052) and for targets starting with `-`, such as `--output=…`
  and `-- -x` (CER-055).
- Add a `--no-commits` flag that omits `commit:` lines. The report then contains only text
  sourced from the manifest (IDs, verdicts, paths, symbols) and is safe to quote in a tracked
  story. Forqsite commit subjects can name deployment instances, so the full report never goes
  into a tracked file.

Remove "except 5" from `docs/architecture.md`'s selftest sentence.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

INFRA-021's release job prints the `--no-commits` report when the checker exits 3, and
review stories quote it. So this story defines exactly what that report may contain. Two
strings in the full report come from forqsite's history rather than from the manifest: the
target (as given, and its sha) and a renamed path's new name. The stub's rule, "only text
sourced from the manifest", excludes both, so `--no-commits` omits them too (Instructions 3).

**Recon (spec-writer, 2026-09-30, git 2.43, nothing written to the repo).**
- `git ls-tree -z --name-only <c> -dash/` exits 129 (`unknown switch`), and the checker turns
  that into exit 5. With `--` before the path, it lists the directory.
- A clone whose own config sets `diff.external` and a `textconv` driver ran that program for
  `git diff -p` and for `git show --textconv`. It did not run it for any of the checker's
  current calls: `diff --quiet`, `diff --name-status`, `log --format`, `show <c>:<path>` and
  `cat-file`. So the flags change no behaviour on this git version (as CER-054 says), and the
  selftest checks them in the argv log. A behavioural check still runs, because newer git can
  run an external diff for `--quiet`/`--exit-code`.
- `GIT_DIR=<plain dir>` makes the unfixed checker exit 2. `GIT_CONFIG_COUNT`/`KEY_0`/`VALUE_0`
  setting `core.abbrev=40` changes its `commit:` lines.
- A prototype of Instructions 1–5 in a throwaway clone passed the selftest (63 checks). Against
  it, every mutation in § Tests failed its named case. Against the unfixed checker, (g), both
  (h) env cases, (j) and the (f) argv check failed.
- The existing header check `first="$(printf '%s\n' "$OUT" | head -1)"` aborted the selftest
  once with exit 141 under `set -o pipefail` (SIGPIPE), and printed no summary. It failed red,
  but a `printf … | grep -q` inside an `if` fails the other way. If `grep -q` exits early, the
  pipeline returns 141, and a "found" reads as "not found". That would pass a leak check
  vacuously. Instructions 5 fixes this.

## Requires

- INFRA-016 is merged, which provides `scripts/stale-claims.py` and its selftest. This story
  is independent of INFRA-017 and INFRA-018 (phase-14.md § Story ordering).

## Ensures

`stale-claims.py` passes `--` before every `ls-tree` path. It runs git with no inherited
`GIT_*` variable except the three it sets, and passes `--no-ext-diff --no-textconv` on every
`diff`, `log` and `show`. `--no-commits` prints exactly the report grammar of Instructions 3
and never runs `git log`. `scripts/stale-claims-selftest.sh` gains cases (e)+, (g), (h), (i),
(j) and the (f) argv check with the exact labels in Instructions 5, and passes. Each fix makes
its named case FAIL when reverted (§ Tests). `README.md`, `docs/architecture.md` and CER-052 to
CER-055 carry the text in Instructions 6 to 8.

## Instructions

1. **CER-053.** In `Git.count()`, pass `'--'` between the commit and `f'{path}/'`. No other
   call needs it: `diff` and `log` already pass `--`, and `cat-file`/`show` take one
   `<commit>:<path>` argument.
2. **CER-054.**
   - Build `self.env` from `os.environ`, dropping every key that starts with `GIT_`. Then set
     the three variables the script already sets (`GIT_LITERAL_PATHSPECS`,
     `GIT_OPTIONAL_LOCKS`, `GIT_TERMINAL_PROMPT`).
   - Pass `--no-ext-diff --no-textconv`, before the revisions, in these four calls:
     - the `show` in `blob()`;
     - the `diff --quiet` in `touched()`;
     - the `diff --name-status` in `renames()`;
     - the `log` in `commits()`.

     The other allowlisted subcommands produce no patch.
3. **`--no-commits`.** Parse it like `--manifest`: accepted anywhere before `--`, and an
   unknown option still exits 64. Add it to `USAGE`. With the flag, stdout contains only:
   - **Header:** `stale-claims: <release.repo> <release.commit[:8]> -> <N> commits later (--no-commits)`.
     `<N>` is the same count the full header prints. There is no target and no target sha.
   - **Record lines,** identical to the full report except for two changes:
     - there are no `  commit:` lines, including `  commit: (none in range touched these paths)`;
     - the failure suffix `, renamed to <new>` becomes `, renamed`.

     Everything else is manifest text or fixed vocabulary, and is unchanged: ids, verdicts,
     `touched:`/`untouched`/`gap <gap>`, `whitespace-only match: <path>`, the six `fail:`
     forms, `reason:`, `note:`, `marker:`, and the numbers in `counts`.
   - **Summary line,** unchanged.

   With the flag, the checker does not call `commits()`, so `git log` never runs. The exit
   codes, the verdicts and stderr are unchanged. stderr messages name no commit subject, and
   the flag governs stdout only.
4. **Header docstring.**
   - Update the usage line.
   - Document `--no-commits` under the options: what it omits and why. The full report can
     carry forqsite commit subjects, so it is never committed.
   - Extend the "Git is invoked" paragraph: git runs with inherited `GIT_*` variables
     removed, and with external diff and textconv disabled.

   Leave the exit-code table unchanged, because no code is added.
5. **Selftest** (`scripts/stale-claims-selftest.sh`). Run every new case before (f), so that
   its output and git calls are covered by (f). Update the header comment's case list. Report
   labels are exact, because § Tests greps them.
   - **No `printf "$OUT" | grep -q/head` under pipefail.** Match against a here-string
     (`grep -qF -- "$x" <<<"$OUT"`) or a bash pattern. Replace the existing
     `first="$(printf '%s\n' "$OUT" | head -1)"` with `first="${OUT%%$'\n'*}"`.
   - **Hermetic git config for the checker.** The scrub now removes the selftest's exported
     `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM` from the checker's environment. So every
     `run_checker` mode runs the checker with `HOME` set to an empty directory under
     `$WORK_DIR`, and with `XDG_CONFIG_HOME` unset. Otherwise a caller's `core.abbrev` would
     break the short-sha assertions. Give `run_checker` a way to add environment variables for
     one run, and two more modes: `hostile` (clone = the hostile clone below) and `failgit`
     (the failing wrapper first on `PATH`).
   - **Wrapper.** The existing `git` wrapper also appends its full argv, one invocation per
     line, to a second log file.
   - **Fixture.** At `R`, add `./-dash/a.sql` and `./-dash/b.sql`. The existing verdicts,
     summary and `8 commits` header are unchanged, because no existing claim names `-dash`.
   - **(e), added after the existing runs.** For each target spec — `--output=injected-1`,
     `-- --output=injected-2` and `-- -x`, word-split into arguments after
     `--manifest "$M_MAIN"` — report `(e) target '<spec>' exits 64` and
     `(e) target '<spec>' writes no file and runs no git`. The second label asserts two
     things:
     - no `injected-1`/`injected-2` exists in `$WORK_DIR` or in `$FIXTURE_REPO`;
     - the wrapper's subcommand log gained no line during the run.

     Use relative file names, because `unknown option <arg>` echoes the argument, and (f)
     forbids `$WORK_DIR` in any output.
   - **(g) `--no-commits`,** with the main manifest at `T`, target given as the full sha `$T`.
     Every label below also requires exit 3, so none can pass vacuously on an error exit.
     - `(g) --no-commits output is (a) without commit lines, target or rename destination`:
       stdout+stderr equals case (a)'s saved output, transformed three ways. Line 1 is
       replaced by the exact Instructions 3 header, every `  commit: ` line is removed, and
       `, renamed to src/renamed.txt` becomes `, renamed`.
     - `(g) --no-commits prints no fixture commit sha, subject or rename destination`. For
       every commit in `git rev-list R..T`, neither the full sha nor its first 7 characters
       appears. No subject from `git log --all --format=%s` appears. Neither `renamed to` nor
       `src/renamed.txt` appears.
     - `(g) --no-commits never runs git log`: the wrapper's subcommand log gains no `log`
       line during the run.
   - **(h) Hostile environment and config (CER-054).**
     - `(h) an inherited GIT_DIR is ignored`: with `GIT_DIR` set to the plain directory, the
       run exits 3 and its output equals case (a)'s.
     - `(h) inherited GIT_CONFIG_* is ignored`: with `GIT_CONFIG_COUNT=1`,
       `GIT_CONFIG_KEY_0=core.abbrev` and `GIT_CONFIG_VALUE_0=40`, the run exits 3 and its
       output equals case (a)'s.
     - Next, `git clone -q` the fixture into `$WORK_DIR/hostile-repo`. In that clone's own
       config, set `diff.external` and `diff.fx.textconv` to a script under `$WORK_DIR` that
       appends to a marker file, and write `* diff=fx` to its `.git/info/attributes`.
     - `(h) the hostile clone's config runs an external program on a patch`, a sanity check
       that the setup is not inert: the selftest's own `git -C <hostile> diff R T -- holds.txt`
       creates the marker. Delete the marker afterwards.
     - `(h) no external diff or textconv program runs`: the checker in `hostile` mode, with
       `GIT_EXTERNAL_DIFF` also set to the marker script, exits 3, and the marker does not
       exist.
   - **(i) Exit 5 (CER-052).** A second wrapper directory, placed first on `PATH` in
     `failgit` mode, holds a `git` that writes `fatal: simulated failure in $FIXTURE_REPO` to
     stderr and exits 128 when any argument is `ls-tree`. For every other call, it `exec`s
     the logging wrapper. `(i) a failing git call exits 5 with no verdicts and no clone path`
     asserts four things with the main manifest at `T`:
     - exit 5;
     - the output contains `git ls-tree failed unexpectedly in the clone named by FORQSITE_CLONE`;
     - no line matches `^C-[0-9]`;
     - `$FIXTURE_REPO` does not appear.
     A wrapper is used rather than a corrupted object because it is deterministic across git
     versions. It also plants the clone path in git's own stderr, so the test proves the
     checker withholds it.
   - **(j) CER-053.** A manifest with the single claim
     `{id C-001, result open, evidence [], counts [{path "-dash", suffix ".sql", n 2}]}` at
     `T`. `(j) a counts path beginning with - is read as a path` asserts exit 0 and C-001
     `untouched`.
   - **(f), added.** `(f) every diff, log and show disables external diff and textconv`:
     every argv-log line whose subcommand (the first word after skipping `-C <dir>`/`-c <kv>`
     and other options) is `diff`, `log` or `show` contains both `--no-ext-diff` and
     `--no-textconv` as whole words. Add `$M_DASH` to the unchanged-manifests list.
6. **`README.md` § Updating.** After "Its header lists every exit code.", add:

   > With `--no-commits`, it prints the same verdicts without the commit lines, the target or
   > a renamed path's new name, so the report holds only text from the manifest and can be
   > quoted in a tracked file. Never commit the full report: forqsite commit subjects can
   > name a deployment.
7. **`docs/architecture.md`,** in the **Stale-claim checker** paragraph.
   - Replace "exercises each verdict and every exit code except 5 (an unexpected git failure,
     untested: CER-052) against a fixture repository." with "exercises each verdict and every
     exit code against a fixture repository."
   - Before "Its usage, verdicts and exit codes live in its own header docstring", add: "It
     runs git with every inherited `GIT_*` variable removed and with external diff and
     textconv disabled (CER-054). `--no-commits` omits everything the report takes from
     forqsite's history rather than from the manifest, so that report can be quoted in a
     tracked file; the full report is never committed."
8. **`docs/cer/backlog.md`.** Append ` **RESOLVED Phase 14 — INFRA-019.**` to the Finding
   cell of each of CER-052, CER-053, CER-054 and CER-055, after its `**Swept …**` note. Change
   nothing else.

Ideology check:
- The pages and the manifest are untouched ("Zero runtime dependencies").
- `--no-commits` is the "Name the class, not the instance" rule applied to a report. Its
  grammar is manifest text only, and (g) asserts the absence of every history-sourced string
  rather than just the `commit:` prefix ("Assert the invariant, not a proxy for it").
- The (f) argv check is a proxy. It is accepted because the invariant (no external program
  runs) is unobservable with the current calls on git 2.43, and the (h) marker check asserts
  the invariant itself alongside it.

Preflight note: `-dash`, `injected-1/2`, `hostile-repo`, `src/renamed.txt` and `C-001` are
fixture names, and `GIT_*`/`HOME`/`XDG_CONFIG_HOME` are environment variables, not repo paths
or constants. Length: past the ~100-line guideline, because it carries five independent fixes,
a report grammar that INFRA-021 consumes, and a mutation list for each.

## Tests

Run from the worktree root:

```bash
out="$(bash scripts/stale-claims-selftest.sh)"; rc=$?; tail -1 <<<"$out"; test "$rc" -eq 0
! grep -q '^FAIL' <<<"$out"
test "$(grep -cE "^PASS: \(e\) target '" <<<"$out")" -eq 6
test "$(grep -cE '^PASS: \((g|h|i|j)\) ' <<<"$out")" -eq 9
grep -qxF 'PASS: (f) every diff, log and show disables external diff and textconv' <<<"$out"
python3 scripts/stale-claims.py --help | grep -qF -- '--no-commits'
! tr -s '[:space:]' ' ' < docs/architecture.md | grep -qF 'except 5'
tr -s '[:space:]' ' ' < docs/architecture.md | grep -qF -- '`--no-commits` omits everything'
grep -qF -- 'With `--no-commits`' README.md
for id in 052 053 054 055; do grep -E "^\| CER-$id \|" docs/cer/backlog.md | grep -qF '**RESOLVED Phase 14 — INFRA-019.**' || exit 1; done
sh -c 'for t in scripts/*-selftest.sh; do bash "$t" && continue; exit 1; done' >/dev/null
git diff --quiet main -- docs/claims-manifest.json index.html gap-handoff.html
if git diff --word-diff=porcelain main -- README.md docs/architecture.md docs/cer/backlog.md scripts/ \
   | grep '^+' | grep -v '^+++ ' | grep -nE '/mnt/|/home/|~/'; then exit 1; fi
```

On `main`, lines 3–10 fail, which the spec-writer confirmed. Lines 1, 2 and 11–13 are guards
that pass on `main` too. The leak scan diffs by word, so a pre-existing path on an edited line
cannot match.

Acceptance: every line exits 0, and the selftest's last line reads `… passed, 0 failed`.

The reviewer then confirms the new cases are not vacuous. Apply each mutation below, one at a
time, to the worktree's `scripts/stale-claims.py`. Run the selftest, and check its exit status
and its summary line, not only the FAIL lines: an aborted run prints no summary. Confirm that
the named case FAILs, then restore with `git checkout -- scripts/stale-claims.py`.
- Drop `'--'` from `count()`: (j).
- `self.env = dict(os.environ)`: both (h) env cases.
- Scrub only `GIT_DIR`: `(h) inherited GIT_CONFIG_* is ignored`.
- Drop `--no-textconv` from the `show` call (or either flag from any one of the four calls):
  the (f) argv check.
- Delete the `positional[0].startswith('-')` target guard: the `-- --output=injected-2` and
  `-- -x` cases of (e).
- Make `must()` return instead of raising: (i).
- Pass git's stderr through, for example `stdout=subprocess.PIPE` in place of
  `capture_output=True`: (i).
- Ignore `--no-commits` when printing commit lines, print the target in its header, or keep
  `renamed to <new>` under it: the first two (g) cases.
- Call `commits()` under `--no-commits` and discard the result: `(g) --no-commits never runs git log`.

## Out of scope

- `--json`, or any other machine format. INFRA-021 consumes the text report.
- Making the checker ignore the clone's own config or the system config
  (`GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_GLOBAL`). The scrub removes inherited overrides only.
  A clone owned by another user may need the caller's `safe.directory`.
- The `release.sh` call site, the gitignored full-report file, and any change to exit codes
  (INFRA-021).
- Two related weaknesses found during recon, which this story does not fix:
  - `cat-file -e` exits 1 for a blob that the tree names but the object store lacks, so an
    `absent {path}` check on a damaged clone passes.
  - A partial (`--filter=blob:none`) clone would lazily fetch a missing blob during `show`,
    against "never fetches". `GIT_NO_LAZY_FETCH=1` prevents that on git 2.44 and later, but
    it is not set.

  Both are for the operator to triage.
