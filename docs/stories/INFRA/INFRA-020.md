---
id: INFRA-020
rail: INFRA
title: restamp.py: pin a new release commit in the manifest and both bundles
status: complete
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/restamp.py

touches:
  - scripts/restamp-selftest.sh
  - docs/architecture.md
  - README.md
  - docs/phases/phase-12.md

narrative_roles: []
---

## Context

**Operator rulings (2026-10-01)**
- **Defaults accepted.** All five design defaults are accepted as written:
  - `unverified` claims keep their result;
  - "clean tree" means tracked files only;
  - the `--dry-run` and `--date` options are added;
  - `rel-` tags are annotated, which is INFRA-021's job;
  - `release.committed` is the committer date.
- **The bootstrap tag.** After INFRA-020 merges, the orchestrator creates the annotated
  `rel-1fda3228` tag on cp-13's commit, locally, and shows it to the operator. It is pushed only
  after the operator approves. The builder never creates it.
- **Notes naming "the release commit".** Unprefixed notes that say "the release commit" are
  rewritten by CONTENT-040 to name the sha. `restamp.py` never rewrites prose.

`scripts/restamp.py <target>`, python3 stdlib only, following the precedent of
`bundle-template.py` and `stale-claims.py`. Clone from `FORQSITE_CLONE`.

It refuses unless all of these hold:
- the tree is clean;
- the target descends from `release.commit`;
- `stale-claims.py` exits 0 at the target. Review stories fix stale claims first, so there is no
  `--allow-stale`.

When they hold, it:
- sets `release.{commit,committed,pinned}`;
- for each stamp, rewrites the commit hex and the date in `text` in that stamp's own date
  format, asserting that the old text occurs exactly once in the page's extracted template
  before the edit and the new text exactly once after;
- round-trips `bundle-template.py` extract, inject and verify on both bundles;
- updates `stamps[].{commit,date,text}`.

**Results** follow § Restamps and closed records.
- A claim whose quote occurs in the previous release's pages becomes `open`, and any prefixed
  note is dropped.
- For any other claim, the story that changed it must already have set
  `changed`/`added`/`unverified` with the matching note prefix, or the tool fails.
- `closed_by`, `closed[]` and the Known-gaps claim are left alone. The tool asserts that the
  Known-gaps claim's evidence equals the union of the S-07 evidence.

**The previous release** is the newest `rel-<forqsite short sha>` tag in this repo (operator
ruling 2026-09-30), bootstrapped as `rel-1fda3228` at cp-13's commit. Retire the
`docs/phases/phase-12.md` § Release commit mirror so the manifest is the only copy.

**Operator ruling 2026-09-30 on what a stamp means after a mechanical restamp:** every recorded
evidence check passed at this commit. `docs/architecture.md` records that meaning, weaker than
Phase 12's hand verification. Each release commit's body lists the IDs of claims that hold, and
the meaning is revisited after two releases.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

**Spec-time findings (2026-10-01).** These were measured against main `4878bb2` and a forqsite
clone.
- **"Exactly once" cannot hold as written.** S-02, S-03 and S-04 carry the identical text
  `verified 2026-09-24 against nullvalues/forqsite@1fda3228`, and it occurs 3 times in the
  `index.html` template. The rule below is the general form: a stamp text occurs exactly as
  many times as the stamp records on that page that carry it, and exactly once for a unique
  text. Every other stamp text occurs once. `nullvalues/forqsite@1fda3228` occurs 4 times in
  the `index.html` template (S-01 to S-04) and 3 times in the `gap-handoff.html` template
  (S-05 to S-07), and nowhere else.
- **Date formats.** S-01 to S-06 carry the ISO date. S-07 carries `24 september 2026`: the day
  without zero padding, the month as a lowercase English name, then the year. This is the
  form CONTENT-031's Tests computed.
- **Manifest serialisation.** The file is exactly `json.dumps(m, indent=2,
  ensure_ascii=False) + '\n'`. Twenty-seven claims have no `note` key at all.
- **Known-gaps claim.** C-001 is the only claim without `result`. Its note names S-07, and
  its 50 evidence pairs equal the deduplicated union of the S-07 claims' evidence today.
- **What a real restamp to `cp-PM105-main` does.** That tag is commit `94f5c339`, committed
  2026-09-25, 66 commits past the release.
  - **Today.** The checker finds C-001 and C-026 stale, both on the GAP-006 evidence line in
    `scripts/firstrun.sh`, so restamp exits 3 and writes nothing. Without `rel-1fda3228` it
    exits 7 first.
  - **Once CONTENT-040 has closed GAP-006.** A prototype run on a scratch copy simulated this
    by removing only that evidence line. It exited 0 with
    `restamp: nullvalues/forqsite 1fda3228 -> 94f5c339 on 2026-10-01: 43 claims: 41 open,
    1 changed, 0 added, 0 unverified`.
    - It rewrote all 7 stamps. S-07 became `… · 1 october 2026`.
    - It set `release` to the full sha, committed 2026-09-25, pinned on the run date.
    - It dropped the `CHANGED:`/`ADDED:` notes of C-002, C-004, C-023, C-025 and C-035 to
      C-038, whose quotes are unchanged since cp-13, so they became `open`.
    - It kept C-042 `changed`, because CONTENT-039 rewrote its quote after cp-13.
    - Both bundles still verified, and the diff touched only the three files.
  - **CONTENT-040's own edits change these counts.** It moves C-026 to `closed[]` and rewrites
    the GAP-006 mentions as `changed` claims.

**Amended 2026-10-01 after the proving pass.** A proving pass on the build (story commit
`4881c24`) found two MEDIUM defects. Instructions 2, 3, 6 and 9 and the mutation list now
cover both.
- **A write failure escaped the exit-5 handler.** `tempfile.mkstemp` for the sibling-temp
  write sat outside the `try`. With a read-only `docs/`, a clean run wrote both bundles, then
  died with an uncaught `PermissionError`: it exited 1 instead of 5, and the traceback printed
  the repository's absolute path.
- **The stamp-date check counted substrings.** For a stamp dated 2026-01-01 whose text says
  `… · 11 january 2026`, `text.count('1 january 2026')` is 1. The exit-8 check passed, and
  `--date 2026-02-03` then wrote `13 february 2026` while the manifest said 2026-02-03.

## Requires

- INFRA-019 is merged. `stale-claims.py --no-commits` exists, and restamp relies on its exit
  codes 0 and 3.
- CONTENT-039 is merged: C-039 to C-043 are in the manifest. Building does not need it, but the
  first real run does.
- The previous-release tag does not need to exist to build or test this story. The fixture
  selftest makes its own tags.

## Ensures

`FORQSITE_CLONE=<clone> python3 scripts/restamp.py [--dry-run] [--date YYYY-MM-DD] <target>`
behaves as the Instructions below specify:
- each refusal exits with its own code and leaves the manifest and both bundles byte-identical;
- a clean run rewrites exactly the manifest and the two bundles, and both bundles pass
  `bundle-template.py verify`.

`scripts/restamp-selftest.sh` proves each refusal, a clean restamp, a carried `changed` claim,
an `open` re-derivation and the corrupted-bundle guard against fixture repos. It also
proves the two amended cases: a stamp date that is not a whole token exits 8, and a write
failure exits 5 with no traceback and no path. The Tests block
below passes, the docs name restamp and the bootstrap, and § Release commit in `phase-12.md`
no longer mirrors the manifest.

## Instructions

1. **CLI.** Parse arguments by hand, as `stale-claims.py` does (argparse would exit 2).
   - **Arguments.** Exactly one `<target>`, any commit-ish the clone resolves. `--dry-run`
     does every check and computation and prints the summary with ` (dry run; nothing
     written)` appended, but writes nothing. `--date YYYY-MM-DD` is the verification date,
     default `datetime.date.today()`. `-h`/`--help` prints the header docstring and exits 0.
     `--` ends options.
   - **Usage errors exit 64.** That covers a missing or extra target, a target that begins
     with `-`, an unknown option and a malformed `--date`.
   - **Repository and clone.** This repository is the git top level that contains the script
     itself, never the current directory. The clone is named only by `FORQSITE_CLONE`.
   - **Header docstring.** It carries the usage and an exit-code table, one line per code in
     the form `    <code>   <meaning>`. It also carries the bootstrap command from
     Instruction 7.

2. **Exit codes, and the order of checks.** Checks run in this order, and the first failure
   decides the code. Nothing is written until every check has passed.

   | Code | Condition |
   | --- | --- |
   | 64 | usage |
   | 2 | configuration. `FORQSITE_CLONE` is unset, or is not a directory or the top of a git repository. The script is not inside a work tree. The manifest is unreadable, does not re-serialise byte for byte (as `json.dumps(m, indent=2, ensure_ascii=False) + '\n'`), or lacks `release.{repo,commit,committed,pinned}`, `stamps` or `claims`. |
   | 6 | the tree has tracked changes, staged or unstaged (`git status --porcelain --untracked-files=no` is non-empty). Untracked files do not block. |
   | 4 | resolution. The target or the release commit is not in the clone, or the target equals the release commit. The target does not descend from the release commit (restamp checks `merge-base --is-ancestor` itself rather than relying on the checker). `--date` precedes the target's committer date or `release.pinned`. |
   | 9 | either bundle fails `bundle-template.py verify` before any edit (the corrupted-bundle guard) |
   | 7 | previous release. There is no tag matching `^rel-[0-9a-f]{8}$`. The two newest such tags share a creation time. The newest is not `rel-<release.commit[:8]>`. That tag's commit lacks either page. |
   | 3 | `stale-claims.py --no-commits --manifest <manifest> <target sha>` exits 3. Print its stdout. |
   | 5 | a git call, the checker (any exit other than 0 or 3), or `bundle-template.py` fails unexpectedly; any filesystem operation of the write phase fails (Instruction 6); or any other unexpected exception (the top-level guard, Instruction 6) |
   | 8 | the manifest is inconsistent. This covers stamp records (Instruction 3), results derivation (Instruction 4) and the Known-gaps assertion (Instruction 5). |
   | 9 | a stamp-occurrence assertion (Instruction 3), or a post-inject verify or re-extract mismatch (Instruction 6) |
   | 0 | restamped. With `--dry-run`, it would restamp. |

   "Newest" means `git for-each-ref --sort=-creatordate refs/tags/rel-*`, never name order.

3. **Stamps.** Let `old8 = release.commit[:8]`, let `new8` be the target's sha `[:8]`, and let
   `slug = release.repo`.
   - **Each stamp record must:**
     - be on one of the two pages;
     - have `commit == old8`;
     - contain `<slug>@<old8>` exactly once in `text`;
     - contain its `date` exactly once in `text`, in exactly one of two forms: ISO, or the
       long form `f'{d.day} {MONTHS[d.month-1]} {d.year}'`. `MONTHS` is a fixed tuple of
       lowercase English month names; never use `strftime`, which follows the locale.
     - **Count the date as a token, never as a substring** (amended 2026-10-01). A match
       must have no digit immediately before or after it:
       `re.compile(r'(?<![0-9])' + re.escape(form) + r'(?![0-9])')`, for both the ISO and
       the long form. So `1 january 2026` does not match inside `11 january 2026`, and
       `2026-01-10` does not match inside `12026-01-10`.

     If any of these fails, exit 8.
   - **The new text** replaces `<slug>@<old8>` with `<slug>@<new8>`, and replaces the old date
     with `--date` in the same form. The date replacement uses the same bounded pattern:
     after the commit is replaced, the old date must still match exactly once as a token
     (otherwise exit 8), and only that match is replaced. A plain `str.replace` of the date
     is not allowed.
   - **Per page, on the extracted template.**
     - **Before the edit:**
       - `<slug>@<old8>` occurs exactly as many times as that page has stamp records;
       - each distinct old text occurs exactly k times, where k is the number of that page's
         records that carry it;
       - its new text occurs 0 times.
     - **After the edit:**
       - each old text occurs 0 times, and its new text occurs k times;
       - `<slug>@<old8>` occurs 0 times;
       - `<slug>@<new8>` occurs once per stamp record.

     If any of these fails, exit 9.
   - **Quotes.** Every claim's quote occurs as many times in the new template as in the
     current one. Otherwise exit 9.

4. **Results.** Extract both pages at the previous-release tag
   (`git show <tag>:<page>`, then `bundle-template.py extract`) and apply these rules.
   - Every claim's quote must occur in its page's current template. Otherwise exit 8.
   - A claim other than the Known-gaps claim that records no evidence, `absent` or `counts`
     must be `unverified`. Otherwise exit 8, because a stamp must not vouch for a claim that
     has nothing to check.
   - The rest are taken in this order:
     1. **`unverified`** keeps its `result`, `note` and `marker`, and its note must start with
        `UNVERIFIED:`. Otherwise exit 8. A mechanical restamp cannot verify such a claim.
     2. **A quote that occurs in the previous pages** sets `result` to `open`. If the note
        starts with `CHANGED:`, `ADDED:` or `UNVERIFIED:`, delete the `note` key. Keep a
        note with no prefix.
     3. **Any other claim** must already be `changed` with a note starting `CHANGED:`, or
        `added` with a note starting `ADDED:`. It is carried through unchanged. Otherwise
        exit 8.

   Do not touch `closed_by`, `closed[]`, `marker`, `evidence` or any other field.

5. **Known-gaps claim.**
   - It is the one claim without `result`. Exit 8 unless exactly one exists, it is on
     `index.html`, and its note names exactly one stamp id (`S-\d+`) whose page is
     `gap-handoff.html`.
   - Assert that its evidence `(path, symbol)` pairs have no duplicate, and that as a set
     they equal the union of the evidence pairs of every `claims[]` entry whose `stamp` is
     that id. Otherwise exit 8.
   - Never modify the claim.

6. **Write.**
   - **Update the manifest in memory.**
     - `release.commit` is the full target sha.
     - `release.committed` is the target's committer date, from
       `git show -s --no-ext-diff --no-textconv --format=%cs`.
     - `release.pinned` is `--date`.
     - Each stamp's `commit`, `date` and `text` take the new values.
   - **Stage the bundles first.** For each page:
     - copy the bundle into a `tempfile.mkdtemp()` directory outside the repo;
     - `inject` the new template;
     - `verify` it, then re-`extract` it and compare with the intended template. Otherwise
       exit 9.
   - **Then write in place,** only when not `--dry-run`: both bundles first, then the
     manifest in its exact serialisation. Remove the temp directory on every path.
   - **Every filesystem operation of the write phase is inside the exit-5 handler**
     (amended 2026-10-01). That covers creating the sibling temp file (`mkstemp`), writing
     it, `fsync`, `copymode` and the `replace` over the original.
     - A failure removes the sibling temp file if it was created.
     - It exits 5 with a message that names the file by basename and gives the recovery:
       the tree had no tracked changes before the run, so `git checkout -- .` restores it.
   - **No traceback, and no absolute path, ever reaches stdout or stderr** (amended
     2026-10-01). `main()` calls a module-level `run()` inside a top-level guard. The guard
     maps any exception other than the tool's own failure type (and `SystemExit`) to exit 5,
     with a fixed message: `unexpected internal failure (<exception class name>)` plus the
     same recovery. The message never includes `str()` of the exception, which can carry a
     path. A write failure must be reported by the write-phase handler, never by this
     guard.
   - **Call `bundle-template.py` and `stale-claims.py` as subprocesses** with
     `sys.executable`, resolved from the script's own directory.
   - **Git hardening, as in `stale-claims.py`.**
     - Strip every inherited `GIT_*` variable, and set `GIT_NO_LAZY_FETCH=1`,
       `GIT_OPTIONAL_LOCKS=0`, `GIT_TERMINAL_PROMPT=0` and `GIT_LITERAL_PATHSPECS=1`.
     - Use read-only subcommands only: `rev-parse`, `cat-file`, `merge-base`, `show`,
       `status` and `for-each-ref`.
     - Capture stderr.
     - Never print the clone path, this repo's absolute path or any forqsite commit subject.
   - **Never** commit, tag, push, fetch or deploy.
   - **Success prints one line, exactly:**
     `restamp: <slug> <old8> -> <new8> on <date>: <N> claims: <a> open, <b> changed, <c> added, <d> unverified`.
     N counts every claim, and the Known-gaps claim is in no result bucket.

7. **Bootstrap `rel-1fda3228`.** The builder must not create it: tags are shared across
   worktrees, and pushing is the operator's. After INFRA-020 merges, and before the first
   real run (CONTENT-040's post-merge release), the operator runs this on main:
   `git tag -a -m "release nullvalues/forqsite@1fda3228 (bootstrap: the pages at cp-13)" rel-1fda3228 'cp-13^{commit}'`
   then `git push origin rel-1fda3228`.
   - **Why cp-13's commit.** Its pages are byte-identical to the deployed cp-12 pages, which
     pin 1fda3228.
   - **Why annotated.** Its creation time is then the tagging time, so it sorts newest.
     INFRA-021 should create `rel-<sha>` tags annotated too.
   - **Where it is recorded.** Put the command in the header docstring and in
     architecture.md.

8. **Docs.**
   - **architecture.md, § Module structure.** List `restamp.py` and `restamp-selftest.sh`.
   - **architecture.md, § Deployment.** Add a `**Restamp** (INFRA-020, Phase 14)` paragraph
     after the Stale-claim checker paragraph. Cover:
     - the refusals;
     - that it writes only the manifest and the two bundles, and never commits, tags or
       deploys;
     - the previous release as the newest `rel-<forqsite short sha>` tag;
     - the bootstrap;
     - the ruled meaning: "every recorded evidence check passed" at this commit, weaker than
       Phase 12's hand verification, and revisited after two releases;
     - that its codes live in its header.
   - **architecture.md, § Claims manifest schema.**
     - The `release` row must say the object is the only copy, with no mention of a mirror.
     - The `release.commit` row: it was CONTENT-030's `origin/main` tip, and since INFRA-020
       it is the target given to `restamp.py`.
     - The `release.committed` row: the target's committer date.
   - **architecture.md, § Restamps and closed records.** Add a bullet: "the pages as they
     stood at the previous release" are the pages at that tag, and `unverified` is kept as
     in Instruction 4.
   - **README.md, § Updating.** Two or three sentences with the usage line.
   - **phase-12.md, § Release commit.** Keep Phase 12's commit as history. Replace "The
     authoritative copy … the manifest wins." with a statement that the current release
     commit lives only in the manifest's `release` object, which `restamp.py` writes. Leave
     the CP-12 checklist untouched; it is a dated record.

9. **`scripts/restamp-selftest.sh`.** Follow `stale-claims-selftest.sh`'s style: `set -euo
   pipefail`, `mktemp -d` with a trap, `GIT_CONFIG_GLOBAL=/dev/null`, `HOME` empty, a logging
   git wrapper first on `PATH`, and a PASS/FAIL tally ending
   `restamp-selftest: N passed, 0 failed`.
   - **Fixture forqsite clone.** Commits with fixed dates:
     - a base;
     - R, the release;
     - T, which descends from R, is committed on a known date, and changes no evidence;
     - S, which descends from T and breaks one claim's evidence;
     - X, on a side branch from the base.
   - **Fixture forqsite.help repo.**
     - Copy in `restamp.py`, `stale-claims.py` and `bundle-template.py`.
     - Build both bundles from templates with `bundle-template.py`'s own `encode`, loaded
       through `importlib`. Each bundle is a `<script type="__bundler/template">` element
       around the encoded template, and each template contains a `/`.
     - The stamps must include:
       - two `index.html` stamps with identical text;
       - one ISO stamp containing `<br>`;
       - one `gap-handoff.html` long-form stamp whose new date has a one-digit day;
     - The claims must include:
       - the Known-gaps claim, with its union;
       - a `changed` claim whose quote is unchanged since the previous release;
       - an `added` claim whose quote is unchanged;
       - a `changed` claim whose quote changed after the release tag, with `CHANGED:`;
       - an `open` claim with an unprefixed note and a `closed_by`;
       - an `unverified` claim with `UNVERIFIED:` and a `marker`;
       - one `closed[]` record.
     - **History.** Commit the pages as released and tag them `rel-<R8>` (annotated).
       Before that, add an older annotated decoy tag `rel-ffffffff`, which sorts first by
       name. Then add a story commit that rewrites the changed quote.
   - **Cases**, each on a fresh `git clone` of the fixture repo:
     - **Clean restamp** (`--date` fixed, target T):
       - exit 0 and the exact summary line;
       - `git status --porcelain` lists exactly the three files;
       - both bundles verify;
       - each new template equals the old one with only `<slug>@<R8>` and the date replaced,
         in the right form;
       - the `release` object and stamp fields hold the new values;
       - the open re-derivations show `result: open` with no `note` key, and nothing else
         changed;
       - the post-tag `changed` claim is carried through byte-equal;
       - the Known-gaps claim, the `unverified` claim, the unprefixed note, `closed_by` and
         `closed[]` are unchanged.
     - **Dry run**, with an untracked file present: exit 0, the dry-run summary, and nothing
       written.
     - **Refusals**, each asserting its exit code and an unchanged `git status` plus sha256
       of the three files:
       - an unstaged tracked change (6) and a staged one (6);
       - target X (4), target R (4), an unknown target (4), and a date before T's commit
         date (4);
       - target S (3; the output carries the checker's `(--no-commits)` header and the
         stale line);
       - no `rel-` tag (7), and a newer `rel-00000000` (7);
       - a new quote with `open` (8), and a `changed` note without `CHANGED:` (8);
       - Known-gaps evidence missing a pair (8), and with a duplicate pair (8);
       - a stamp text occurring once too often (9), and `<slug>@<R8>` outside any stamp
         (9);
       - a bundle with one `\u002F` replaced by `/`, so it parses but fails verify (9);
       - `FORQSITE_CLONE` unset (2);
       - no target, an unknown option, and `--date 2026-2-3` (all 64).
     - **Amended cases (2026-10-01).**
       - A long-form stamp whose `date` is 2026-01-01 but whose text, on the page and in
         the manifest, says `11 january 2026` (exit 8, nothing written). Also an ISO stamp
         whose text has `12026-01-10` where the date is 2026-01-10 (exit 8, nothing
         written).
       - A read-only `docs/` directory (`chmod a-w`), restored after the run. A clean
         restamp must:
         - exit 5;
         - print no `Traceback` and no fixture or work-directory path;
         - print a message that names `claims-manifest.json`, contains `git checkout -- .`,
           and is not the top-level guard's message;
         - leave the manifest byte-identical and no `.restamp-*` file in `docs/`.

         Probe first that the directory really refuses a write for this user. If it does
         not (for example, under root), report the case as FAIL with that reason, never as
         a pass.
       - The top-level guard. Load `restamp.py` with `importlib`, replace its `run` with a
         function that raises `RuntimeError` carrying a work-directory path, and call
         `main()`. It must exit 5 with no `Traceback` and without that path.
     - **Hygiene.**
       - No fixture or work-directory path appears in any output.
       - Every logged git subcommand is in the read-only set of restamp plus the checker:
         `rev-parse`, `cat-file`, `merge-base`, `show`, `status`, `for-each-ref`, `diff`,
         `log`, `ls-tree` and `rev-list`.

10. **Ideology.** These were checked against `docs/ideology.md`, and no conflict was found.
    - Bundles change only through `bundle-template.py`, inside the reviewed release loop
      (Generated-artifact discipline).
    - The stamp counts, the union assertion and the post-inject verify assert the invariant
      itself.
    - No host, path or URL appears in code, docs or output (Name the class, not the
      instance).
    - The tooling runs before publication, which the Self-containment value permits.

**Mutations for the reviewer.** Apply each to `restamp.py`, run the selftest, and confirm it
goes red. The spec-time prototype went red on every one. The amended mutations were
checked on a prototype built from `4881c24` with the amendments applied. The unamended
`4881c24` fails 5 cases of the amended selftest.
- Read previous pages from `HEAD`, not the tag.
- Zero-pad the long-form day, or use `strftime('%B')`.
- Delete the pre-edit `verify`.
- Sort tags by name.
- Skip the union assertion.
- Do a plain `str.replace` with no occurrence counts.
- Keep a prefixed note on re-derivation.
- Drop unprefixed notes too.
- Set every claim `open`.
- Ignore checker exit 3.
- Delete restamp's own ancestry check. The checker would then exit 4, and restamp would
  report 5, not 4.
- Write any file before the last check.
- Count untracked files as dirty.
- Ignore `--dry-run`.
- Amended 2026-10-01:
  - Move `mkstemp` back outside the write-phase `try`. The read-only case must then go red,
    because the top-level guard's message replaces the write failure's.
  - Remove the top-level guard. The guard case and the path-hygiene case must go red.
  - Count and replace stamp dates as substrings (`str.count`/`str.replace`). Both amended
    date cases must go red.
  - Drop the leading `(?<![0-9])` bound. Both amended date cases must go red.

**Length.** This spec runs well past the ~36-line baseline. The tool writes the published
pages and the manifest at once, and every refusal and every assertion is a decision the
builder must not have to guess. The prototype that validated them is not committed. The
spec-preflight warnings are intentional, and there are three:
- `MONTHS` is created by this story.
- `HOME` is an environment variable.
- `docs/ideology.md` is cited, not edited.

## Tests

Run from the repo root at the story's tip. `FORQSITE_CLONE` names a local forqsite clone that
has `cp-PM105-main`. Step 3 expects exit 3 only while GAP-006 is open at that tag, which holds
until CONTENT-040 merges. The block must FAIL on main `4878bb2` (there is no
`restamp-selftest.sh`) and PASS on the finished story, as it did on the spec-time prototype.

```bash
set -euo pipefail
: "${FORQSITE_CLONE:?set FORQSITE_CLONE to a local forqsite clone that has cp-PM105-main}"
cd "$(git rev-parse --show-toplevel)"
PRE=4878bb2cd47cd7eb6edbe62f45e9adca245522db
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
TAGS_BEFORE=$(git for-each-ref refs/tags)

# 1. the new selftest is green, then every selftest
bash scripts/restamp-selftest.sh > "$S/selftest.out"
tail -1 "$S/selftest.out" | grep -qE '^restamp-selftest: [0-9]+ passed, 0 failed$'
for t in scripts/*-selftest.sh; do bash "$t" > /dev/null || { echo "FAIL: $t"; exit 1; }; done

# 2. stdlib only; every exit code documented in the header
python3 - <<'EOF'
import ast, sys
tree = ast.parse(open('scripts/restamp.py').read())
mods = {a.name.split('.')[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
mods |= {n.module.split('.')[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module}
assert mods <= set(sys.stdlib_module_names), mods - set(sys.stdlib_module_names)
EOF
python3 scripts/restamp.py --help > "$S/help"
for code in 0 2 3 4 5 6 7 8 9 64; do grep -qE "^ +$code +[^ ]" "$S/help" || { echo "FAIL: exit $code undocumented"; exit 1; }; done

# 3. the real clone, in a scratch clone of this repo: no tag -> 7; tag at cp-13 -> 3 (GAP-006)
git clone -q . "$S/fh"
cp scripts/restamp.py "$S/fh/scripts/"
git -C "$S/fh" add scripts/restamp.py
git -C "$S/fh" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m 'restamp under test'
git -C "$S/fh" tag -d rel-1fda3228 > /dev/null 2>&1 || true
set +e
python3 "$S/fh/scripts/restamp.py" --dry-run cp-PM105-main > "$S/r7" 2>&1; rc=$?
set -e
test "$rc" -eq 7 && grep -qF 'rel-1fda3228' "$S/r7"
git -C "$S/fh" -c user.name=t -c user.email=t@example.invalid tag -a -m bootstrap rel-1fda3228 'cp-13^{commit}'
set +e
python3 "$S/fh/scripts/restamp.py" --dry-run cp-PM105-main > "$S/r3" 2>&1; rc=$?
set -e
test "$rc" -eq 3
grep -qE '^C-001 stale ' "$S/r3"; grep -qE '^C-026 stale ' "$S/r3"
test "$(grep -cE '^C-[0-9]+ stale ' "$S/r3")" -eq 2
grep -qF '(--no-commits)' "$S/r3"
if grep -qF -- "$FORQSITE_CLONE" "$S/r7" "$S/r3"; then echo "FAIL: clone path printed"; exit 1; fi
test -z "$(git -C "$S/fh" status --porcelain --untracked-files=no)"
test "$(git for-each-ref refs/tags)" = "$TAGS_BEFORE"

# 4. docs (whitespace-normalised, CER-011)
python3 - <<'EOF'
import re
norm = lambda s: re.sub(r'\s+', ' ', s)
def section(path, start, stop):
    s = open(path).read(); i = s.index(start); j = s.find(stop, i + len(start))
    return norm(s[i:j if j != -1 else len(s)])
a = open('docs/architecture.md').read()
assert 'restamp.py' in section('docs/architecture.md', '## Module structure', '\n## ')
assert 'restamp-selftest.sh' in section('docs/architecture.md', '## Module structure', '\n## ')
row = [l for l in a.splitlines() if l.startswith('| `release` | object |')]
assert len(row) == 1 and 'mirror' not in row[0] and 'only copy' in row[0], row
dep = section('docs/architecture.md', '## Deployment', '\n## Claims manifest schema')
assert '**Restamp**' in dep and 'every recorded evidence check passed' in dep and 'two releases' in dep and 'rel-<forqsite short sha>' in dep
rr = section('docs/architecture.md', '### Restamps and closed records', '\n### ')
assert 'rel-<forqsite short sha>' in rr and 'unverified' in rr
assert 'restamp.py' in section('README.md', '## Updating', '\n## ')
p12 = section('docs/phases/phase-12.md', '## Release commit', '\n## Stories')
assert 'If the two ever disagree' not in p12 and 'only' in p12 and 'claims-manifest.json' in p12
print('docs ok')
EOF

# 5. untouched files, and no host or local path in added text
git diff --quiet "$PRE" -- scripts/stale-claims.py scripts/bundle-template.py scripts/stale-claims-selftest.sh index.html gap-handoff.html docs/claims-manifest.json
if git diff --word-diff=porcelain "$PRE" -- docs/architecture.md README.md docs/phases/phase-12.md | grep -E '^\+[^+]' | grep -nE '/mnt/|/home/|~/|https?://'; then exit 1; fi
if grep -nE '/mnt/|/home/|https?://' scripts/restamp.py scripts/restamp-selftest.sh; then exit 1; fi
echo ALL-OK
```

**Acceptance.** The block prints `docs ok` and `ALL-OK`, and every command exits 0. The
reviewer also applies the mutations listed under Instructions, and each must turn the
selftest red.

## Out of scope

- Creating or pushing `rel-1fda3228`, or any `rel-` tag. The operator does that by hand after
  merge (Instruction 7), and `release.sh` (INFRA-021) tags later releases.
- Committing, pushing, deploying or drift-checking. Listing the IDs of claims that hold in the
  release commit body is INFRA-021's job.
- Rewriting stale claims, closing GAP-006, moving claims to `closed[]` or recomputing the
  Known-gaps union. Review stories (CONTENT-040) do that, and restamp only asserts the union.
- An `--allow-stale` flag, or any choice of target. The caller names the target, and
  `--latest-checkpoint` belongs to INFRA-021.
- Changing `stale-claims.py`, `bundle-template.py`, the manifest's schema or the published
  pages in this story.
- Rewording unprefixed notes that name "the release commit" (C-039 to C-041 and C-043).
  Restamp keeps them, as Instruction 4 says.
- Command-block coverage beyond the stamped sections (Phase 15).
