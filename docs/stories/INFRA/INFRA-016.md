---
id: INFRA-016
rail: INFRA
title: Stale-claim checker against a newer forqsite commit
status: planned
phase: "13"
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/stale-claims.py
touches:
  - scripts/stale-claims-selftest.sh
  - CLAUDE.build.md
  - README.md
  - docs/architecture.md
  - docs/cer/backlog.md
narrative_roles: []
---

## Operator decisions (ruled 2026-09-29)

The operator ruled on 2026-09-29 that this spec decides the two questions INFRA-015 left
open. The spec proposed an answer to each, plus two smaller choices. **The operator accepted
all four recommendations as written on 2026-09-29**, and the Instructions implement them.
They are decisions now, not proposals; the rejected alternatives are kept as the record.

1. **What `result` means after a restamp.** Ruled (operator, 2026-09-29): `result` always describes the
   most recent restamp. When a later forqsite commit is pinned as `release.commit`, every
   claim's `result` is derived again, against the pages as they stood at the previous
   release. A claim whose quote is unchanged is `open`. A claim whose quote was rewritten is
   `changed`, a new claim is `added`, and a claim that could not be verified is
   `unverified`. A prefixed note from an earlier release (`CHANGED:`, `ADDED:`) is removed
   along with the result it explained, and the manifest's git history keeps it. A live
   claim's `closed_by` is not derived again. This matches the existing meaning in
   § Claims manifest schema ("the re-verification at `release.commit` that produced the
   claim's current stamp"). Since CONTENT-032 every stamp names the release commit, so
   every claim is restamped at every release.
   Two alternatives were rejected:
   - A sticky `result`, or a per-release `results[]` history. It would store the git
     history a second time, and a claim left untouched for five releases would still read
     `changed`.
   - Updating `result` only when a quote changes. Different claims' results would then refer
     to different release commits, while `release.commit` names one.
   The checker does not read `result`, except to surface `unverified`.
2. **How a `closed[]` record is checked for reopening.** Ruled (operator, 2026-09-29): CONTENT-031
   defines a closed record's `evidence` as "literals at the release commit that show the
   fix". The checker re-checks those literals at the target, by the same rules as a live
   claim's evidence (and `absent`/`counts`, if a record carries them). If every check
   passes, the verdict is `closed`. If any check fails, the verdict is `reopened`, and it
   counts toward the nonzero exit the same way `stale` does. A record with no checks at all
   is also `reopened`, because nothing shows the fix still holds.
   Two alternatives were rejected:
   - Detecting a `git revert` of `closed_by.commit`. A fix can be undone without a revert,
     and a revert message is a convention, not an invariant.
   - Checking whether the gap reappears on a page. The pages cannot change when forqsite
     does, and the checker reads no page.
3. **No `--json` in this story.** Ruled (operator, 2026-09-29): defer it to Phase 14. The release job
   there is its only consumer, and a machine format with no reader is the
   producer-without-consumer that the CP-13 checklist asks about. Each report line begins
   with `<id> <verdict>`, which is stable enough for the selftest and for a human.
4. **`unverified` does not fail the run.** Ruled (operator, 2026-09-29): exit 0. An `unverified` claim is
   already published as unverified, with an on-page marker. If a known, marked state failed
   every run, the exit code would stay red and people would learn to ignore it. It is still
   printed on every run.

## Context

This is the Phase 13 goal. The revised brief (CONTENT-038) allows release-time
reconciliation. At release time, list the manifest claims whose evidence changed between
the pinned release commit (`release.commit` in `docs/claims-manifest.json`) and a newer
forqsite commit, such as a `cp-PM*-main` checkpoint tag. The checker reports and never
edits: it does not change the manifest or the pages. Rewriting a stale claim takes judgment
(phase-12.md § After this phase).

Intended shape (operator-approved 2026-09-29; the spec-writer settles the details):
- `scripts/stale-claims.py`, python3 stdlib only, following the precedent of
  `scripts/bundle-template.py`. It takes a local forqsite clone path and a target
  commit-ish. The clone path is never written into the repo (the `FORQSITE_CLONE`
  convention).
- It walks forqsite's history from the release commit to the target, over the paths each
  claim's `evidence`, `absent` and `counts` name. It then re-applies the Phase 12
  verification semantics at the target: an evidence `symbol` is present in its path, an
  `absent` symbol or path is still absent, and a `counts` value still holds. The existing
  source of those semantics is the inline Tests code in CONTENT-031 and CONTENT-032.
- Per claim it reports: untouched (no named path changed), holds (paths changed and every
  check still passes), or stale (a check fails). For each stale claim it names the failing
  check and the commits that touched its paths. `unverified` claims are always surfaced.
  `closed` records (CER-045) are checked for reopening. The exit code is nonzero when
  anything is stale.
- Design constraints: symbol and quote matching tolerate whitespace and soft-wrap
  differences (CER-011). Inert `<script>` source never counts as rendered (CER-012), so any
  page-side check must respect that or state that it is out of scope.
- Tests: `scripts/stale-claims-selftest.sh`, following the `*-selftest.sh` precedent. It
  builds a throwaway fixture git repo and fixture manifest covering each verdict, including
  the `unverified` marker path and a `closed` array (the fixture half of CER-045). Build
  standards `test_command` in `CLAUDE.build.md` changes from `true` to run the selftests.
- Document usage in `README.md` § Updating. This replaces "does not exist yet", which
  CONTENT-038 wrote for this story to retire. Also document it in `docs/architecture.md`.

Builds after INFRA-015 and reads the schema reference it adds. CER-046 (command blocks) is
deferred, so the checker covers the stamped claims only.

**Recon (spec-writer, 2026-09-29, prototype against a real clone, nothing written).** There
are 66 commits from the release commit `1fda3228` to `cp-PM105-main` (`94f5c339`), and none
of them is a merge. At that target, 22 claims are untouched, 14 hold and 2 are stale. The
stale ones are C-026 (GAP-006) and C-001, the Known-gaps claim, which carries C-026's
evidence. Their `scripts/firstrun.sh` literal `val=$(grep "^${var}=" .env.local 2>/dev/null
|| true | cut -d= -f2-)` was rewritten by forqsite `8112020e` (INFRA-059), which may have
closed GAP-006. At `origin/main` (99 commits past), C-022, C-024 and C-025 are also stale,
because `docker-compose.yml` was deleted and a `Dockerfile` added. No rename touches a named
path, and no evidence literal matched only after whitespace normalisation. With the release
commit itself as the target, all 38 claims are untouched and pass, so the manifest is
consistent with the semantics below. The run took about 1 second.

## Requires

- INFRA-015 is merged: `docs/architecture.md` § Claims manifest schema is the field
  reference.
- Operator rulings on the four decisions above are recorded in this spec.

## Ensures

`scripts/stale-claims.py <target>` gives every claim and closed record the verdict
Instructions 2 defines, prints the report Instructions 4 defines, and exits with the codes in
Instructions 5, without writing to the manifest, the pages or the clone.
`scripts/stale-claims-selftest.sh` exercises each verdict and exit code against a fixture
repo and passes. The Build standards `test_command` runs every `scripts/*-selftest.sh`.
`README.md` § Updating, `docs/architecture.md` and CER-045 carry the text in
Instructions 7 to 9.

## Instructions

1. **CLI.** `python3 scripts/stale-claims.py [--manifest FILE] <target>`.
   - `<target>` is any commit-ish the clone resolves. It has no default.
   - `--manifest` defaults to `docs/claims-manifest.json`, resolved from the script's own
     location rather than the current directory.
   - The clone is read from `FORQSITE_CLONE` only. There is no flag, so the path never lands
     in shell-quoted documentation.
   - Parse arguments by hand, as `bundle-template.py` does, or override argparse's `error()`.
     argparse exits 2 on a usage error, and 2 is the configuration code here.
   - Invoke git as `git -C <clone> <subcommand>` via `PATH`. Use only read-only subcommands:
     `rev-parse`, `cat-file`, `merge-base`, `diff`, `log`, `show`, `ls-tree`, `rev-list`.
     Never fetch. Tell the user to fetch a missing target themselves.
   - Open the manifest read-only.
2. **Checks and verdicts.** Run every check for every record, whatever its touched state.
   The verdict comes from the checks, and touched only splits `holds` from `untouched`.
   - Normalise text with `re.sub(r'\s+', ' ', s).strip()`, applied to both the symbol and
     the blob. A symbol matches when the normalised symbol is a substring of the normalised
     blob, read with `git show <target>:<path>` and decoded as UTF-8 with
     `errors='replace'`.
   - **Why this departs from Phase 12.** Phase 12 used a literal, line-oriented
     `git grep -F`. The departure is deliberate (CER-011). A reindent or reflow at the target
     should not send a human to rewrite a claim whose meaning did not change. For `absent`,
     normalisation makes the check stricter, so a gap cannot hide behind a line break. When
     the literal fails but the normalised form matches, the check passes, and the report
     notes it as `whitespace-only match: <path>`.
   - **evidence** `{path, symbol}` passes when `path` is a blob at the target and the
     symbol matches.
   - **absent** `{path, symbol}` passes when `path` is a blob at the target and the symbol
     does not match. A missing path fails. `{path}` alone passes when
     `git cat-file -e <target>:<path>` fails.
   - **counts** `{path, suffix, n}` passes when exactly `n` names in
     `git ls-tree --name-only <target> <path>/` end in `suffix`. This counts one level only,
     as CONTENT-032 did.
   - **Touched.** A named path is touched when `git diff --quiet <release> <target> -- <path>`
     exits 1. This is the net difference between the two commits. A change that was later
     reverted is not a touch, because the evidence at the two ends is identical. A `counts`
     path is compared as the directory `<path>/`.
   - **Renames.** Take them from one `git diff -M --name-status --diff-filter=R <release>
     <target>` over the whole tree. A check whose path was renamed fails as usual, because
     the page cites the old path, and its failure line adds `renamed to <new path>`. The
     checker never follows a rename to make a check pass.
   - **`claims[]` verdicts,** in this precedence: `stale` if any check fails. Otherwise
     `unverified` if `result` is `unverified`, or if the claim has no evidence, `absent` or
     `counts` at all (reason `no checks recorded`). Otherwise `holds` if any named path is
     touched. Otherwise `untouched`. The Known-gaps claim gets no special handling.
   - **`closed[]` verdicts** (decision 2): `reopened` if any check fails or the record has no
     checks. Otherwise `closed`.
3. **Commits.** For a `stale` or `reopened` record, list
   `git log --format='%h %s' <release>..<target> -- <every path the record names>`, newest
   first. List only the commits that touched that record's own paths.
4. **Report** (stdout, human-readable, with a stable first line per record):
   ```text
   stale-claims: <release.repo> <release[:8]> -> <target as given> (<target[:8]>), <N> commits
   C-002 holds  touched: holds.txt
   C-004 stale  touched: stale.txt
     fail: evidence stale.txt: "old api()" not found
     commit: 1a2b3c4 change the api
   C-009 unverified  untouched
     reason: result is unverified
     note: UNVERIFIED: …
     marker: …
   C-013 reopened  gap GAP-902
   summary: 11 claims: 2 untouched, 2 holds, 5 stale, 2 unverified; 3 closed records: 1 closed, 2 reopened
   ```
   - Records appear in manifest order, claims first and then closed records. Every
     `unverified` claim prints its `note` and `marker`.
   - Failure lines take these forms:
     - `evidence <path>: "<symbol>" not found`
     - `evidence <path>: path missing at target[, renamed to <new>]`
     - `absent <path>: "<symbol>" now present`
     - `absent <path>: path missing at target`
     - `absent <path>: path now exists`
     - `counts <path>/*<suffix>: expected <n>, found <m>`
   - Never print the clone path, including in error messages. Say "the clone named by
     FORQSITE_CLONE".
5. **Exit codes.** The table lives in the script's header docstring, which also carries the
   usage and the verdict definitions (architecture.md § Exit-code contract).
   - `0`: nothing is stale or reopened.
   - `2`: configuration. `FORQSITE_CLONE` is unset or not a git repository, or the manifest
     is unreadable or lacks `release.commit` or `claims`.
   - `3`: at least one record is `stale` or `reopened`.
   - `4`: resolution. The target or the release commit is not in the clone, or the release
     commit is not an ancestor of the target (`git merge-base --is-ancestor`). The range
     would otherwise be empty or backwards, and every claim would read as untouched.
   - `64`: usage.
6. **Selftest** `scripts/stale-claims-selftest.sh`. Follow the header, `report` and
   PASS/FAIL-count style of `provenance-selftest.sh`, and exit nonzero on any failure. It
   must need no forqsite clone and finish in a few seconds.
   - **Fixture repo, built in `mktemp -d`.** An initial commit `P`, then the release commit
     `R`, then eight commits ending at `T`, in this order:
     1. Edit `holds.txt` and reflow `wrap.md`, splitting `two three four` across a line
        break.
     2. Change `old api()` to `new api()` in `stale.txt`.
     3. Append `no such` + newline + `thing` to `absent.txt`, and create `nope.txt`.
     4. Add `dir/3.sql`. `R` already has `dir/1.sql`, `dir/2.sql` and `dir/sub/x.sql`.
     5. `git mv src/moved.txt src/renamed.txt`.
     6. Change `revert.txt`.
     7. Revert that change.
     8. Remove `guard()` from `fix2.txt`.
   - **Fixture manifest,** written by the selftest with `R`'s sha substituted. Expected
     verdicts at `T`:
     - `untouched`: C-001 (evidence `keep.txt`) and C-010 (evidence `revert.txt`).
     - `holds`: C-002, which has evidence and `absent {holds.txt, FORBIDDEN}` in `holds.txt`
       plus a `counts` on an unchanged directory. Also C-003, evidence `two three four` in
       `wrap.md`, whose line carries `whitespace-only match`.
     - `stale`:
       - C-004: evidence in `stale.txt`.
       - C-005: `absent {absent.txt, "no such thing"}`.
       - C-006: `absent {nope.txt}`.
       - C-007: `counts {dir, .sql, 2}`. A recursive count would already be 3 at `R`.
       - C-008: evidence in `src/moved.txt`, whose failure line contains
         `renamed to src/renamed.txt`.
     - `unverified`: C-009, which has `result: unverified`, an `UNVERIFIED:` note, a marker
       containing "not verified", and passing evidence. The report prints its marker. Also
       C-011, with `evidence: []`, which reports `no checks recorded`.
     - `closed[]`: C-012 is `closed` (`fix.txt`), C-013 is `reopened` (`fix2.txt`), and
       C-014 is `reopened` (`evidence: []`).
   - **Cases:**
     - **(a) Main manifest at `T`.** Exit 3, and every record's verdict line matches the
       table above. C-004's block names the short sha of commit 2 and not commit 1's. C-008's
       block names commit 5's, and C-013's names commit 8's. The summary line matches
       exactly.
     - **(b) Clean subset at `T`.** A manifest without C-004 to C-008, C-013 and C-014
       exits 0, and C-009 is still printed as `unverified`.
     - **(c) Target `R`.** The main manifest minus C-014 exits 0, and every claim is
       `untouched` or `unverified`.
     - **(d) Untouched but failing.** A one-claim manifest whose symbol never existed in
       `keep.txt` exits 3, and the claim is `stale`.
     - **(e) Error codes:**
       - `FORQSITE_CLONE` unset: exit 2.
       - `FORQSITE_CLONE` set to a plain directory: exit 2.
       - A missing manifest: exit 2.
       - An unknown target: exit 4.
       - Target `P`: exit 4.
       - A manifest whose release sha is absent from the repo: exit 4.
       - No arguments, or an unknown option: exit 64.
     - **(f) Hygiene, across every run above:**
       - The fixture repo's path and the work directory's path appear in no captured
         output.
       - The fixture repo's `rev-parse HEAD`, `for-each-ref` and `status --porcelain` output
         is identical before and after.
       - The fixture manifests' sha256 values are unchanged.
       - A `git` wrapper placed first on `PATH` for the checker runs only logs its
         arguments and `exec`s the real git. Every logged subcommand is in the Instructions 1
         allowlist.
7. **`CLAUDE.build.md`** Build standards line. Replace exactly this text:

   "test_command=`true` — this project has no test suite (static HTML, no build step);
   `true` is a real command that exits 0, because next_action.py's build-gate guard
   *executes* this value via a shell. A prose description here shells out to
   `command not found` (exit 127) and fails the checkpoint gate red"

   with this text (one line in the file):

   "test_command=`for t in scripts/*-selftest.sh; do bash "$t" && continue; exit 1; done` —
   the project's tests are the fixture selftests in `scripts/` (INFRA-016); next_action.py's
   build-gate guard *executes* this value via a shell from the project root, and any failing
   selftest turns the gate red. The copy the guard executes is `test_command` in the
   untracked `.companion/pairmode_context.json`, which must hold the same string"

   The command contains no `|`, so it cannot break the line's ` | ` separators. It fails
   closed if the glob matches nothing. The spec-writer ran it under `sh` on `main`, where it
   exited 0 in about 6 seconds across the three existing selftests. The guard reads
   `.companion/pairmode_context.json`, not this file (`next_action.py`
   `_run_build_gate_subprocess`), so editing CLAUDE.build.md alone would leave the gate
   running `true`. Setting the context file's copy is Post-merge step 1.
8. **`README.md` § Updating.**
   - Replace the sentence "The checker that walks the history is being built in Phase 13
     and does not exist yet." with this text:

     > `scripts/stale-claims.py` walks that history and lists every claim whose evidence no
     > longer holds at the new commit, and every closed gap that has reopened. It reads a
     > local forqsite clone named by `FORQSITE_CLONE`, which must already contain the target
     > commit, and it never edits the manifest, the pages or the clone. Rewriting a stale
     > claim is still a reviewed story.

     Follow it with an `sh` block containing
     `FORQSITE_CLONE=<path to your forqsite clone> python3 scripts/stale-claims.py <commit-ish>`,
     then this sentence: "It exits 0 when nothing is stale, and 3 when a claim is stale or a
     closed gap has reopened. Its header lists every exit code."
   - In the paragraph beginning "Until that exists, periodic refresh passes", replace that
     opening with "Refresh passes (like Phase 2 of this project), including the rewrite of
     any claim the checker reports stale, happen through …", and keep the rest of the
     sentence. Its antecedent no longer exists.
9. **`docs/architecture.md`.**
   - Add `stale-claims.py` and `stale-claims-selftest.sh` to the Module structure tree under
     `scripts/`.
   - After the **Claims manifest.** paragraph, add a **Stale-claim checker** (INFRA-016)
     paragraph. It says, by class, that the script:
     - compares the manifest's claims and closed records at a target forqsite commit against
       the release commit;
     - reads a local clone named by `FORQSITE_CLONE` and fetches nothing;
     - writes nothing;
     - normalises whitespace on purpose (CER-011);
     - reads no page, so CER-012 does not arise;
     - keeps its usage, verdicts and exit codes in its own header.
   - In § Claims manifest schema, add `### Restamps and closed records` before
     `### Disagreements and unspecified behaviour`. State decisions 1 and 2 as ruled, citing
     INFRA-016.
   - Replace the last Disagreements bullet ("It is not specified what `result` means …")
     with "What `result` means after a restamp, and how a `closed[]` record is checked for
     reopening, were unspecified until INFRA-016; § Restamps and closed records states
     both."
   - In § Build commands, replace the `# Run all tests` command line with the Instructions 7
     loop.
10. **CER-045.** Append ` **RESOLVED Phase 13 — INFRA-016.** The fixture tests for the
    `unverified` marker path and the `closed` array ship in
    `scripts/stale-claims-selftest.sh`.` to the end of its Finding cell, after the INFRA-015
    progress note. Change nothing else in the file.

Ideology check:
- The published pages are untouched, so "Zero runtime dependencies" holds. The checker is
  release-time tooling, which the brief permits.
- The clone path never enters the repo, and case (f) asserts it never enters output ("Name
  the class, not the instance").
- The check asserts evidence at the target rather than a proxy such as "the file changed",
  and it re-checks untouched claims ("Assert the invariant, not a proxy for it").
- It follows the CER-011 convention, and it avoids CER-012 by reading no rendered output.

Preflight note: `cp-PM105-main`, `GAP-9xx` and the fixture paths are clone or fixture
names, not paths in this repo. `FORQSITE_CLONE` and `PATH` are environment variables, and
`GAP` and `UNVERIFIED` are manifest tokens, not constants in the source tree. The checker
reads `docs/claims-manifest.json` but never writes it, so the manifest is deliberately
absent from `touches`.

Length: this runs well past the ~100-line guideline. It carries two schema decisions for
operator review, a new script's exact semantics, a fixture table in which each verdict needs
its own case, and three verbatim doc edits, as INFRA-015 did.

## Post-merge (orchestrator)

1. In the main project directory, set `test_command` in `.companion/pairmode_context.json`
   to the exact string from Instructions 7, then run it once with `sh -c` and confirm it
   exits 0. The file is untracked, so this is not a commit.
2. Optional smoke run, when a clone is available and contains `cp-PM105-main`:
   `FORQSITE_CLONE=<clone> python3 scripts/stale-claims.py cp-PM105-main`. Expected:
   - exit 3;
   - the first line reads `66 commits`;
   - C-001 and C-026 are `stale`, both failing on the `scripts/firstrun.sh` literal and
     both listing `8112020e`;
   - `summary: 38 claims: 22 untouched, 14 holds, 2 stale, 0 unverified; 0 closed records`.

   Do not paste its output into any repo file, because forqsite commit subjects can name
   deployment instances. A checkpoint record states the counts only.

## Tests

```bash
bash scripts/stale-claims-selftest.sh
sh -c 'for t in scripts/*-selftest.sh; do bash "$t" && continue; exit 1; done'
python3 scripts/stale-claims.py </dev/null; test $? -eq 64
git diff --quiet main -- docs/claims-manifest.json index.html gap-handoff.html
if git diff --word-diff=porcelain main -- README.md docs/architecture.md docs/cer/backlog.md CLAUDE.build.md scripts/ \
   | grep '^+' | grep -v '^+++ ' | grep -nE '/mnt/|/home/|~/'; then exit 1; fi
```

The last check diffs by word, not by line (`--word-diff=porcelain`). `CLAUDE.build.md`'s
Build standards line already contains a `~/flex-marketplace-cache/...` path on `main`, and
Instructions 7 edits that same line, so a line diff would report the unchanged path as an
added line. Found during the first build on 2026-09-29, and corrected in the spec before
review.

Acceptance: the selftest prints only PASS lines and exits 0, the loop exits 0, and the last
three lines exit 0. The reviewer then confirms that the selftest is not vacuous. The
reviewer applies each mutation below, one at a time, to the worktree's
`scripts/stale-claims.py`, confirms that the named case FAILs, and restores the file with
`git checkout`:
- Literal matching instead of normalised: C-003 and C-005 in case (a).
- `git log` non-empty instead of net diff for touched: C-010 in case (a).
- Skipping `closed[]`: C-013 in case (a).
- Recursive counts: C-007 in case (c).
- Skipping checks on untouched paths: case (d).
- Exit 0 on stale: cases (a) and (d).

## Out of scope

- Editing the manifest, the pages or the clone, restamping, or moving a record between
  `claims` and `closed`. The checker reports, and the rewrite is a reviewed story.
- Any page-side check: that a quote or marker is still on the page, that a stamp renders, or
  the `path:line` citations on `gap-handoff.html`. The checker reads no page, so CER-012
  does not arise. A page-to-manifest consistency check, or a line-citation check, is a
  follow-up for Phase 14 to consider.
- Command blocks and other unstamped content (CER-046, deferred to Phase 14).
- `--json` output, a release job, CI, or any trigger (decision 3, Phase 14).
- Updating `CLAUDE.md` § Story test verification, whose command still reads "none — static
  HTML". That file is harness-rendered, and it is left to the operator.
- Validating the manifest against the full schema. The checker refuses only a missing
  `release.commit` or `claims`.
