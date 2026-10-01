---
id: INFRA-021
rail: INFRA
title: release.sh: the attended release job
status: planned
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/release.sh

touches:
  - scripts/release-selftest.sh
  - .gitignore
  - README.md
  - docs/architecture.md
  - docs/checkpoints.md

narrative_roles: []
---

## Context

A bash script following the `deploy.sh` precedent, run by hand on the operator's host. It
never fetches, and the clone comes from `FORQSITE_CLONE`.

**Invocation:** `release.sh <target>` or `release.sh --latest-checkpoint`. The latter picks the
newest `cp-PM*-main` tag in the clone by version sort.

**Preconditions:** a clean tree on the default branch, not behind origin, and green selftests.
When `release.commit` already equals the target, it does nothing and exits 0.

**What it does, by checker exit:**
- **Exit 0.** `restamp.py`, then the selftests, then a commit whose fixed message names only
  the forqsite sha and claim counts, with the IDs of claims that hold in the body. Then it tags
  `rel-<sha>`, runs `deploy.sh`, runs `drift-check.sh --ref HEAD`, and pushes the commit and
  tag only after both pass.
- **Exit 3.** It writes the full report to a gitignored local file and prints the
  `--no-commits` summary (INFRA-019). It tells the operator to review these as a story, and
  exits with a distinct "review needed" code, touching nothing.
- **Any other exit.** It aborts with that code.

**Operator rulings 2026-09-30:**
- `--dry-run` is the default and `--yes` commits, deploys and pushes.
- Any scheduler is operator-local and untracked, and is enabled only after one attended release.
- If the post-deploy drift check fails, the job stops, does not push, and exits nonzero. It
  never rolls back on its own; `deploy.sh --rollback` (INFRA-018) stays the operator's call.

The selftest uses a fixture forqsite repo and the stub ssh and local server of the existing
selftests. It must be written for the stale path, not only the clean one. At forqsite
`origin/main` the checker already finds 5 stale claims, because `docker-compose.yml` was
deleted and a `Dockerfile` added. Name the host and schedule only by class.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

Also (operator ruling 2026-10-01): `rel-<sha>` tags are annotated, so the "newest release tag"
lookup in `restamp.py` (INFRA-020) sorts reliably.

**Operator rulings on the spec's open questions (2026-10-01)**
- **Accepted as specced:**
  - the `git ls-remote` precondition on every run, dry runs included;
  - restamp's summary line in the commit body;
  - writing the stale-path report file even in a dry run;
  - running the selftests twice, once as a precondition and once after the restamp.
- **Changed: ahead of origin.** When local `main` is ahead of origin, the release is
  allowed. Before any write, and in dry runs too, the job lists the unpushed commits that the
  push will carry, by subject. These are subjects from this repository, which may be printed
  (Instruction 2a).
- **Changed: rollback after a drift failure.** After exit 16, the job prints the full
  ready-to-paste `scripts/deploy.sh --rollback <stamp>` command along with the stamp. It
  still never runs that command (Instruction 6).

**Spec-time design (2026-10-01).** A throwaway prototype of `release.sh` and its selftest
was built against main, together with a stand-in `restamp.py` that implements INFRA-020's
specced CLI and exit codes.
- **First run, at `238bdb3`.** Every case and mutation listed below behaved as stated.
- **Revised after the rulings, at `ed83c8e`.** INFRA-018 is merged there, and the run used
  the real merged `deploy.sh`. The selftest passed 112 cases, and the printed
  `--rollback` command was itself run in the fixture and restored the previous files.

The prototype is not committed. It settled five points that the stub left open.
- **"Not behind origin" is read from origin itself, without fetching.** It uses
  `git ls-remote`, which downloads no objects and writes no refs. The remote-tracking ref is
  only as fresh as the operator's last fetch. If it were trusted, an origin that had moved on
  would surface only as a rejected push after the deploy: the site would then serve a commit
  that origin does not have.
- **"Any other exit: abort with that code"** is narrowed to the exit-code contract. Checker
  codes 2 and 4 pass through with their meaning, and anything else maps to 5. Every later
  step gets its own code. Passing `deploy.sh` or `drift-check.sh` codes through unchanged
  would collide with this script's own codes (both use 3 for something else).
- **The no-op must not hide an unfinished release.** After a drift failure, the local commit
  already pins the target, so a bare `release.commit == target` test would report "nothing to
  do" for a release that was never pushed. An unfinished release is detected first: the newest
  local `rel-` tag is missing from origin.
- **The drift check uses `--ref rel-<sha8>`,** which names the same commit as `HEAD` at that
  point. The recovery steps print the same ref.
- **An empty holds list must not abort the job.** The prototype's first run died under
  `pipefail` on a release where no claim held. The body then reads `holds: none`, and a case
  asserts it.

## Requires

- INFRA-019 is merged: `stale-claims.py --no-commits` and its exit codes (0, 2, 3, 4, 5, 64).
- INFRA-018 is merged, as of main `ed83c8e`. This story calls only `deploy.sh --ref` and
  `deploy.sh --dry-run`. It reads two lines of the deploy's success block: `stamp` and
  `backups`. That block names only the backups the far side confirmed. The story prints a
  `--rollback` command but never runs it. `deploy.sh` refuses a repeated option with 64, and
  `release.sh` passes each option once.
- INFRA-020 is merged. `scripts/restamp.py` exists with its specced CLI: `--dry-run`, one
  target, and exit codes 0, 2, 3, 4, 5, 6, 7, 8, 9 and 64. It writes nothing on any non-zero
  exit. The selftest copies the real `restamp.py`.
- The pre-story commit for the Tests block is main
  `ed83c8e8b5b063a0518d2f917b7a32f9b908837d`. It was re-pinned on 2026-10-01, after
  INFRA-018 merged.
- The bootstrap tag `rel-1fda3228` is not needed to build or test this story. The first real
  run (CONTENT-040's post-merge release) needs it on origin.

## Ensures

`scripts/release.sh` behaves as the Instructions below specify:
- each refusal exits with its own code before anything is written;
- the stale path exits 3, writing only the gitignored report;
- the clean path commits, tags, deploys and drift-checks, then pushes;
- every stop after the commit leaves the push undone and prints its exact recovery commands.
  After a drift failure, these include a ready-to-paste `deploy.sh --rollback <stamp>`,
  which the job never runs;
- a branch that is ahead of origin is released, after the unpushed commits are listed by
  subject before any write.

`scripts/release-selftest.sh` proves every exit code against fixtures, and the Tests block
below prints `docs ok` and `ALL-OK`.

## Instructions

1. **CLI.** The usage is `release.sh [--dry-run | --yes] <target>` or
   `release.sh [--dry-run | --yes] --latest-checkpoint`.
   - **Dry run by default.** With no `--yes` it is a dry run, and `--dry-run` says so
     explicitly.
   - **Help.** `-h`/`--help` prints the header comment and exits 0.
   - **Usage errors exit 64,** with no git or ssh work:
     - no target and no `--latest-checkpoint`, or both;
     - a second target;
     - an unknown option;
     - `--yes` together with `--dry-run`;
     - any option given more than once;
     - a target outside `deploy.sh`'s `REF_RE` class (no leading `-`).
   - **Header.** The header carries the usage and an exit-code table, one row per code in the
     form `#   <code>  <meaning>`, and a "What it does" list as `deploy.sh` does.
   - **Repository.** This repository is the git top level containing the script itself.
     `cd` there, and call the sibling scripts from the script's own directory, as `deploy.sh`
     does.

2. **Exit codes, and the order of checks.** The first failure decides the code. Nothing is
   written before the restamp in step 3, except the report on the stale path.

   | Code | Condition, in order |
   | --- | --- |
   | 64 | usage |
   | 2 | `FORQSITE_CLONE` is unset or not a git repository |
   | 7 | the current branch is not `main` (detached included). `RELEASE_BRANCH=main` is a stated constant in the header. |
   | 6 | tracked changes: `git status --porcelain --untracked-files=no` is non-empty. Untracked files do not block. |
   | 2 | `deploy.sh --dry-run --ref HEAD` exits 2, or `FORQSITE_HELP_SITE_URL` resolves empty. Resolve it as drift-check does: the environment wins, then `scripts/deploy.env` through `read-deploy-env.sh`. Any other non-zero from the dry run exits 5. |
   | 5 | `git ls-remote origin refs/heads/main 'refs/tags/rel-*'` fails, or lists no `main` |
   | 8 | behind origin. origin's `main` is not a local commit, or is not an ancestor of `HEAD`; or origin has a `rel-` tag that is missing locally or differs. Name the remedy (fetch and merge by hand), and never fetch. When the branch is ahead instead, print the listing in 2a and continue. |
   | 10 | unfinished release. The newest local tag matching `^rel-[0-9a-f]{8}$` (by `--sort=-creatordate`) is not on origin at the same object. Print the step 6 recovery for that tag when its commit is `HEAD`. |
   | 4 | `--latest-checkpoint` finds no clone tag matching `^cp-PM[0-9]+-main$`, or the target does not resolve in the clone |
   | 0 / 10 | `release.commit` equals the target sha. If the local `rel-<t8>` exists, print `already released` and exit 0, touching nothing. Otherwise exit 10. If the target differs but `rel-<t8>` already exists locally or on origin, exit 10. |
   | 9 | a selftest fails. That is every `scripts/*-selftest.sh`, output captured to scratch, and the failing names printed. |
   | 3 / 2 / 4 / 5 | `stale-claims.py --no-commits <target sha>` exits 3 (step 4), 2, 4, or anything else (5) |
   | 11 | `restamp.py` exits non-zero (with `--dry-run` in a dry run), or changes anything other than the three files. Print its code. |
   | 12 | a selftest fails after the restamp |
   | 13 | `git commit` fails |
   | 14 | `git tag` fails |
   | 15 | `deploy.sh` fails; print its exit code |
   | 16 | `drift-check.sh` fails; print its exit code |
   | 17 | the push fails |
   | 0 | released; or, in a dry run, would release |

   - **Reading the clone.** Read the clone with `git -C "$FORQSITE_CLONE"`, with every
     inherited `GIT_*` variable removed and `GIT_NO_LAZY_FETCH=1`. Use read-only subcommands
     only: `rev-parse` and `for-each-ref`.
   - **Picking the checkpoint.** `--latest-checkpoint` takes the first name from
     `for-each-ref --sort=-version:refname 'refs/tags/cp-PM*-main'` that matches the regex,
     and prints `release: target <name> (<sha8>)`. An explicit target prints the same line.
   - **What is never printed:** the clone path, this repository's absolute path, the alias,
     the directory and the URL.

   2a. **Ahead of origin (operator ruling 2026-10-01).** Let `R` be origin's `main` as
   `ls-remote` reported it. When `git rev-list --count R..HEAD` is N > 0, print this to stdout
   straight after the code-8 check, before any write, in dry runs and with `--yes` alike:
   ```
   release: main is <N> commit(s) ahead of origin; the push will also carry:
   release:   <sha8> <subject>
   ```
   - There is one `release:   <sha8> <subject>` line per commit, oldest first, from
     `git log --reverse --format='%H %s' R..HEAD`, with `%H` cut to 8 characters.
   - Then the run continues. These are this repository's own subjects, which may be printed.
   - When N is 0, print nothing.
   - The release commit is not listed, because it does not exist yet.

3. **The clean path** (checker exit 0).
   - **Dry run.** Run `restamp.py --dry-run <sha>` and print its line. Print
     `release: would commit: <subject>`, then a line naming the tag, the deploy, the drift
     check and the push. Then print `dry run: nothing was written; run again with --yes`, and
     exit 0.
   - **With `--yes`, in order:**
     - Record `PRE=$(git rev-parse HEAD)`.
     - Run `restamp.py <sha>`. `git status --porcelain --untracked-files=no` must then list
       exactly `docs/claims-manifest.json`, `index.html` and `gap-handoff.html`.
     - Run the selftests.
     - Commit. Run `git add --` on those three files and nothing else, then `git commit -F`.
       The message is exactly:
       ```
       release: <slug>@<t8>, <N> claims: <u> untouched, <h> holds, <v> unverified

       <restamp's success line, verbatim>
       holds: <space-separated holds IDs in manifest order, or none>
       ```
       `slug` is `release.repo`. The counts and IDs come from the `--no-commits` run, which
       contains manifest text only, so no forqsite commit subject can reach the message.
     - Tag: `git tag -a -m "release <slug>@<t8>" rel-<t8> <commit>`.
     - Deploy: `deploy.sh --ref rel-<t8>`, shown to the operator. Keep the value of its
       `stamp` line.
     - Check: `drift-check.sh --ref rel-<t8>`, shown.
     - Push, only after both pass: `git push --atomic origin refs/heads/main refs/tags/rel-<t8>`.
     - Print one `released` line and exit 0.

4. **The stale path** (checker exit 3), identical with or without `--yes`.
   - Write the full report (`stale-claims.py <sha>`, without `--no-commits`) to
     `.release-report.txt` in the repo root, under `umask 077`, overwriting any earlier one.
   - Print the `--no-commits` output to stdout, then three fixed lines:
     - that review is needed;
     - `full report (local only; never commit it): .release-report.txt`;
     - review them as a story, then run again.
   - Print no target sha in these lines, so stdout stays quotable.
   - Exit 3.
   - Add `/.release-report.txt` to `.gitignore`, with a one-line comment: forqsite commit
     subjects can name a deployment.

5. **Stops before the commit.**
   - **After 11.** Restamp writes nothing on failure, so there is nothing to undo.
   - **After 12 or 13.** Print `nothing was committed`, then
     `git restore --staged --worktree -- docs/claims-manifest.json index.html gap-handoff.html`.

6. **Stops after the commit.** Nothing is ever pushed before step 3's last check passes. Each
   stop prints a `release: stopped …` line, then the commands, one per line, run from the repo
   root:
   - **After 14 (the commit exists, untagged).** Print `to abandon it:`, then
     `git reset --keep <PRE>`.
   - **After 15 or 16.**
     - Print `to finish it:`, then:
       - `scripts/deploy.sh --ref rel-<t8>`
       - `scripts/drift-check.sh --ref rel-<t8>`
       - `git push --atomic origin main rel-<t8>`
     - Print `to abandon it:`, then:
       - `git tag -d rel-<t8>`
       - `git reset --keep <PRE>`
       - `scripts/deploy.sh`
       - `scripts/drift-check.sh`

       The reset precedes the redeploy because `deploy.sh` refuses bundles that differ from
       its ref.
     - **After 16, the rollback command (operator ruling 2026-10-01).** `S` is the value of
       the deploy's `stamp` line. When S was read, print these three lines after the abandon
       block:
       ```
       release: or, to restore the files this deploy replaced (backup set <S>), instead of the redeploy:
       release:   scripts/deploy.sh --rollback <S>
       release:   scripts/drift-check.sh
       ```
       - **Incomplete set.** If the deploy's `backups` line does not name all three of
         `index.html.bak-<S>`, `gap-handoff.html.bak-<S>` and `site-provenance.json.bak-<S>`,
         add one line saying that this set has no backup of the first missing file, so
         `deploy.sh --rollback` will refuse it (exit 6) and the abandon steps apply.
       - **Never run `--rollback`.** Printing the command is the whole of this step.
   - **After 17 (deployed and drift-checked).** Print `to finish it:`, then
     `git push --atomic origin main rel-<t8>`. Add one line: if origin has moved, resolve it
     by hand.

7. **Docs.**
   - **architecture.md, § Module structure.** List `release.sh` and `release-selftest.sh`.
   - **architecture.md, § Deployment.** Add a `**Release job** (INFRA-021, Phase 14)`
     paragraph before the deploy-scripts paragraph. It contains the phrases
     `rel-<forqsite short sha>`,
     `never pushes a release that has not deployed and passed the drift check`,
     `never rolls back on its own`, `operator-local and untracked` and `ls-remote`. It also
     says the codes live in the header.
   - **README.md, § Updating.** Two sentences and a code block with
     `release.sh --latest-checkpoint` and `release.sh --yes --latest-checkpoint`, with the
     clone written as `<path to your forqsite clone>`.
   - **docs/checkpoints.md, preamble** (before the first `---`). Add one sentence: a release
     is not a checkpoint, a stopped release prints its own recovery steps, and a local `rel-`
     tag that origin lacks makes the next run refuse.

8. **`scripts/release-selftest.sh`.**
   - **Style.** Follow `provenance-selftest.sh`: `set -euo pipefail`, `mktemp -d` with a
     trap, a PASS/FAIL tally ending `release-selftest: N passed, 0 failed`, and
     `GIT_CONFIG_GLOBAL=/dev/null`. Set `HOME` and the git identity inside the work dir. Every
     report name ends ` — INFRA-021/<TOKEN>`, and a case asserting an exit code says
     `exit <code>` in its name.
   - **Fixture forqsite clone** (`FORQSITE_CLONE`):
     - base;
     - R, with `a.txt` "alpha" and `b.txt` "beta";
     - T1, which edits `a.txt` and keeps alpha;
     - T2, which adds `c.txt`;
     - S, from T2, which removes beta.

     Use fixed dates. The subjects of T1 and S carry a marker string. The tags are
     `cp-PM9-main` on T1, `cp-PM10-main` on T2, and a decoy `cp-PM999-rc-main`.
   - **Fixture forqsite.help seed.**
     - **Scripts.** Copy in `release.sh`, `restamp.py`, `stale-claims.py`,
       `bundle-template.py`, `deploy.sh`, `drift-check.sh`, `make-provenance.sh` and
       `read-deploy-env.sh`, plus the repo's real `.gitignore`. Add a stub
       `scripts/fixture-selftest.sh`: with `FIXTURE_SELFTEST_FAIL=pre` it always fails, and
       with `=post` it fails once the manifest differs from `HEAD`. It is the fixture's only
       selftest, so there is no recursion.
     - **Bundles.** Build both with `bundle-template.py`'s `encode` through `importlib`. Each
       template contains a `/`.
     - **Manifest.** Serialise it exactly as INFRA-020 requires. It holds:
       - `release.repo` `fixture/forqsite` at R;
       - S-01, an ISO stamp on `index.html`;
       - S-02, a long-form stamp on `gap-handoff.html`;
       - C-001, the Known-gaps claim: no `result`, a note naming S-02, and evidence equal to
         C-003's;
       - C-002, `open` on `a.txt`/alpha;
       - C-003, `open` on `b.txt`/beta, stamp S-02.
     - **History.** Commit. Tag `rel-<R8>` annotated, with a past `GIT_COMMITTER_DATE` so
       that a later `rel-` tag sorts newer. Push both to a bare origin.
   - **Per case.**
     - Take a copy of the bare origin, make a fresh clone of it, and empty the deploy target.
     - Put the stub `ssh` first on `PATH`. It runs the command under `dash`, as
       `deploy-selftest.sh` does, and has a refuse mode.
     - Add a logging `git` wrapper.
     - Run a 127.0.0.1 server that serves the target, with an override directory, as
       `drift-check-selftest.sh` does.
     - Export `FORQSITE_HELP_*`.
     - "Nothing touched" means `HEAD`, the local tags, the origin refs and the tracked status
       are all unchanged, and the stub `ssh` was never invoked.
   - **Cases.**
     - **CLEAN.** Run `--yes <T1>`, with an untracked file present. Expect exit 0, and:
       - the exact subject `release: fixture/forqsite@<T1_8>, 3 claims: 2 untouched, 1 holds, 0 unverified`;
       - the body line `holds: C-002`, and no marker;
       - the commit holds exactly the three files;
       - `rel-<T1_8>` is a `tag` object at `HEAD`;
       - origin's `main` and tag equal the local ones;
       - the served `index.html` equals `HEAD`'s, and the served `gap-handoff.html` names
         `<T1_8>`;
       - the untracked file is untouched;
       - no `fetch` or `pull` appears in the git log;
       - no `ahead of origin` line is printed, because the branch is level with origin.
     - **NOOP.** In the same repo, run `--yes <T1>` again. Expect exit 0, `already released`,
       and nothing touched.
     - **LATEST.** In the same repo, run `--yes --latest-checkpoint`. Expect exit 0,
       `target cp-PM10-main (<T2_8>)`, `rel-<T2_8>` on origin, and `holds: none`. This also
       proves that restamp took `rel-<T1_8>` as the previous release.
     - **AHEAD.** In a fresh case, make two unpushed local commits, `local work one` and then
       `local work two`.
       - **Dry run.** Run `<T1>` with no flag. Expect exit 0, nothing touched, and output
         containing exactly this three-line block:
         ```
         release: main is 2 commit(s) ahead of origin; the push will also carry:
         release:   <sha8 of one> local work one
         release:   <sha8 of two> local work two
         ```
       - **With `--yes`.** Run `--yes <T1>`. Expect exit 0, the same block printed before the
         `restamp:` line, and origin's `main^` equal to the second local commit.
       - **The match.** Compare the whole block with a bash `[[ $OUT == *"$want"* ]]`, never
         with `grep -F` on a multi-line pattern. `grep -F` reads each line of the pattern as a
         separate alternative, so the order would go unchecked. The prototype's first version
         of this check passed vacuously for exactly that reason.
     - **DRYRUN.** Run `<T1>`. Expect exit 0, the would-commit subject, nothing touched and
       no report.
     - **STALE.** Run `--yes <S>`, and again with no flag. Expect exit 3, and:
       - `(--no-commits)` and `C-003 stale` on stdout;
       - no `  commit:` line and no marker on stdout;
       - the report holds the marker;
       - `git check-ignore` accepts the report;
       - stdout names `.release-report.txt`;
       - nothing touched.
     - **DRIFT.** Seed the target with a live copy of all three files (fixed "previous"
       bytes). Override the served `index.html`, then run `--yes <T1>`. Expect exit 16, and:
       - origin unchanged, and no `push` in the git log;
       - a local annotated tag;
       - the finish and abandon lines, with `<PRE>`;
       - the exact line `release:   scripts/deploy.sh --rollback <S>`, where S is the deploy's
         own `stamp` line in the same output;
       - no incomplete-set line;
       - the target still holds the release bytes, because `release.sh` did not roll back.

       Then:
       - Re-run with the override removed. Expect exit 10, and nothing touched.
       - Run the printed `scripts/deploy.sh --rollback <S>` in the case repo. Expect exit 0,
         and the live `index.html` holds the seeded previous bytes again.
       - In a fresh case with an empty target, a drift failure still prints the
         `--rollback` command, together with the incomplete-set line.
     - **DEPLOY.** With the stub ssh refusing, expect exit 15, origin unchanged, and the
       `git tag -d` line printed.
     - **PUSH.** With a rejecting `pre-receive` hook in origin, expect exit 17, origin
       unchanged, the served bytes equal to the release's, and the push line printed.
     - **REFUSE.** Each of these expects its code and nothing touched:
       - 64 for each usage form in step 1;
       - 2 for `FORQSITE_CLONE` unset, for `FORQSITE_HELP_DEPLOY_HOST` unset, and for
         `FORQSITE_HELP_SITE_URL` unset;
       - 7 on a branch other than `main`;
       - 6 for a tracked change;
       - 8 when another clone has pushed to origin. The local `origin/main` must also be
         unchanged, which proves there was no fetch.
       - 5 when origin's URL points nowhere;
       - 4 for an unknown sha, and for a clone with no `cp-PM` tags;
       - 9 for `FIXTURE_SELFTEST_FAIL=pre`;
       - 10 for a local `rel-ffffffff` that origin lacks;
       - 11 for a committed bundle with one `\u002F` replaced by a literal `/`, which restamp's verify
         refuses.

       Three more cases check the state by hand:
       - **12** (`=post`): `HEAD`, the tags and the ssh marker are unchanged, and the
         `git restore` line is printed.
       - **13** (a `pre-commit` hook that fails): `HEAD` is unchanged and there was no ssh.
       - **14** (a `refs/tags/rel-<T1_8>.lock` file): `HEAD^` is the old `HEAD`, there was
         no ssh, and the `git reset --keep <old HEAD>` line is printed.
     - **HYGIENE.** No output of `release.sh` contains the work-directory path, the alias,
       `127.0.0.1` or the port.

9. **Ideology** (checked against `docs/ideology.md`, with no conflict found).
   - **Assert the invariant.** Release success means served bytes equal the release
     commit's, judged by `drift-check.sh`, not by `deploy.sh`'s exit alone. Origin's state is
     read from origin, never from a remote-tracking proxy.
   - **Name the class, not the instance.** No host, path, URL or clone path appears in the
     code, the docs or the output. The full report stays in a gitignored file.
   - **Generated artifacts.** The bundles change only through `restamp.py`, inside a
     reviewed release.
   - **Self-containment.** The tooling runs before publication, which is permitted.

**Mutations for the reviewer.** Apply each to `release.sh` and run the selftest. Each must
go red, and each went red on the prototype.
- A lightweight tag.
- `--sort=-refname`.
- Dropping the `cp-PM` regex filter.
- Deleting the unfinished-release check.
- Reading origin's `main` from `refs/remotes/origin/main`.
- Pushing before the drift check.
- Printing the full report on stdout.
- Skipping the selftests after the restamp.
- `git add -A`.
- Exit 0 on checker exit 3.
- Skipping the ahead listing (AHEAD).
- Listing ahead commits newest first, without `--reverse` (AHEAD).
- Omitting the `--rollback <S>` line after exit 16 (DRIFT).

**Length.** This spec runs well past the ~36-line baseline. The job commits, tags, deploys
and pushes, and every stop is a state the operator must be able to read. Each code and each
recovery line is a decision the builder must not guess. Spec-preflight may flag the following
names, all intentional:
- `REF_RE`, a `deploy.sh` constant;
- `RELEASE_BRANCH` and `PRE`, which this story creates;
- `HOME`, `FORQSITE_HELP_*` (including `FORQSITE_HELP_SITE_URL`) and
  `FIXTURE_SELFTEST_FAIL`, which are environment variables;
- `docs/ideology.md`, which is cited, not edited;
- `docs/claims-manifest.json` (a `scope:` finding). `release.sh` commits the copy that
  `restamp.py` writes at run time, and the builder never edits it.

## Tests

Run from the repo root at the story's tip. No forqsite clone is needed, and no real host is
contacted, because every remote in the selftest is local. The block was run against main
`ed83c8e` (re-pinned after INFRA-018 merged). Every new check failed there: there is no
`release-selftest.sh` or `release.sh`, the report is not ignored, and the docs assertion
failed. It was also run against the revised prototype copy, which uses the merged
`deploy.sh`. There it printed `docs ok` and `ALL-OK`.

```bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PRE=ed83c8e8b5b063a0518d2f917b7a32f9b908837d
S=$(mktemp -d); trap 'rm -rf "${S:?}"' EXIT

# 1. the new selftest is green and asserts every exit code; then every selftest
bash scripts/release-selftest.sh > "$S/selftest.out" 2>&1 || true
tail -1 "$S/selftest.out" | grep -qE '^release-selftest: [0-9]+ passed, 0 failed$'
for tok in CLEAN NOOP LATEST AHEAD DRYRUN STALE DRIFT DEPLOY PUSH REFUSE HYGIENE; do
  grep -qE "^PASS: .* — INFRA-021/$tok\$" "$S/selftest.out" || { echo "FAIL: no passing INFRA-021/$tok case"; exit 1; }
done
for code in 0 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 64; do
  grep -qE "^PASS: [^—]*exit $code([^0-9][^—]*)? — INFRA-021/" "$S/selftest.out" || { echo "FAIL: no case asserts exit $code"; exit 1; }
done
grep -qE '^PASS: [^—]*rollback[^—]* — INFRA-021/DRIFT$' "$S/selftest.out" || { echo "FAIL: no passing rollback-command case"; exit 1; }
for t in scripts/*-selftest.sh; do bash "$t" > /dev/null 2>&1 || { echo "FAIL: $t"; exit 1; }; done

# 2. every exit code documented in the header, which --help prints
bash scripts/release.sh --help > "$S/help"
for code in 0 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 64; do
  grep -qE "^ +$code +[^ ]" "$S/help" || { echo "FAIL: exit $code undocumented"; exit 1; }
done

# 3. the full report is gitignored
git check-ignore -q --no-index .release-report.txt

# 4. docs (whitespace-normalised, CER-011)
python3 - <<'PY'
import re
norm = lambda s: re.sub(r'\s+', ' ', s)
def section(path, start, stop):
    s = open(path).read(); i = s.index(start); j = s.find(stop, i + len(start))
    return norm(s[i:j if j != -1 else len(s)])
ms = section('docs/architecture.md', '## Module structure', '\n## ')
assert 'release.sh' in ms and 'release-selftest.sh' in ms, 'module structure'
dep = section('docs/architecture.md', '## Deployment', '\n## Claims manifest schema')
for w in ('**Release job**', 'rel-<forqsite short sha>', 'never pushes a release that has not deployed and passed the drift check', 'never rolls back on its own', 'operator-local and untracked', 'ls-remote'):
    assert w in dep, w
up = section('README.md', '## Updating', '\n## ')
assert 'release.sh --latest-checkpoint' in up and 'release.sh --yes' in up, 'README'
top = norm(open('docs/checkpoints.md').read().split('\n---\n', 1)[0])
assert 'release.sh' in top and 'rel-' in top, 'checkpoints preamble'
print('docs ok')
PY

# 5. no host, local path or URL in the new scripts or in added doc text
if grep -nE '/mnt/|/home/|https?://' scripts/release.sh; then exit 1; fi
if grep -nE '/mnt/|/home/|https?://' scripts/release-selftest.sh | grep -v '127\.0\.0\.1'; then exit 1; fi
if git diff --word-diff=porcelain "$PRE" -- docs/architecture.md README.md docs/checkpoints.md .gitignore | grep -E '^\+[^+]' | grep -nE '/mnt/|/home/|~/|https?://'; then exit 1; fi
echo ALL-OK
```

**Acceptance.** The block prints `docs ok` and `ALL-OK`, and every command exits 0. The
reviewer also applies the mutations listed under Instructions, and each must turn the
selftest red. The reviewer also confirms that the story's own diff leaves these files
unchanged: `deploy.sh`, `drift-check.sh`, `restamp.py`, `stale-claims.py`, the other
selftests, both bundles and the manifest. Sibling stories change some of them after `PRE`, so
this check cannot be pinned to `PRE`.

## Out of scope

- Running a rollback. On a drift failure the job stops unpushed and prints the
  `deploy.sh --rollback <stamp>` command (INFRA-018), but running it stays the operator's
  call.
- Resuming a stopped release (`--resume`). The printed commands are the resume path.
- Fetching, merging or rebasing. A repository that is behind origin is refused.
- A scheduler, timer or cron entry in the tree. Any scheduler is operator-local, untracked,
  and enabled only after one attended release.
- Creating or pushing the bootstrap `rel-1fda3228` tag (INFRA-020, Instruction 7).
- Rewriting stale claims, or any `--allow-stale`. Review stories do that.
- Changing `deploy.sh`, `drift-check.sh`, `restamp.py`, `stale-claims.py` or the manifest
  schema.
- Command-block coverage beyond the stamped sections (Phase 15).
