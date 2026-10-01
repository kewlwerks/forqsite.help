---
era: "001"
phase_class: production
---

# forqsite.help — Phase 12: One stamp per release: re-verify every published claim against one forqsite commit

← [Phase 11: Make the deploy repeatable, and make drift visible](phase-11.md)

<!-- Phase doc = planning surface only. Story-level detail (acceptance criteria,
     file paths, implementation guidance, test instructions, codebase recon)
     belongs in docs/stories/<RAIL>/<ID>.md — not here. -->
## Goal

<!-- State this phase's single purpose in one or two sentences (docs/architecture.md
     § Phase-authoring convention, INFRA-243). If the work naturally splits into more
     than one purpose, that's a signal to open a sibling phase, not to widen this one. -->
Re-verify every stamped claim in both published pages against a single pinned forqsite commit, restamp them uniformly, and leave behind a claims manifest that a later phase can check automatically.

## Why this phase exists

Both published pages make claims about forqsite's behaviour. Each claim carries a
date-and-commit stamp saying which forqsite commit it was last verified against. On
2026-09-23 the operator found the Known gaps callout still stamped `17b78645` from
2026-09-16, while other claims on the same page carry `7089b9dc` from 2026-09-18 to 21.
CER-029 had already found the same pattern on one `gap-handoff.html` claim. The stamps
drifted because each story re-verified only the claims it touched. The stamp therefore
dates individual claims, not the page. A reader cannot tell which forqsite the page
describes as a whole.

forqsite has moved 137 commits past `17b78645`. Some gaps may have closed. Some claims may
now be wrong.

The operator's intent (2026-09-23): the content is verified and stamped once per docs
release, against one forqsite commit, and eventually forqsite.help ships automatically to
match the current forqsite build. This phase does the first half by hand, once. It also
builds the piece that automation needs and that does not exist today: a machine-readable
list of what each claim asserts and where in forqsite the evidence lives.

**Takes over CER-029.** That finding is resolved by this phase, not separately.

## What this phase is not

- **Not automation.** No trigger, CI job or scheduled check. The claims manifest is built
  so that a later phase can check it mechanically; building the checker is that phase's
  job.
- **Not a revision of `docs/brief.md`.** The brief lists "real-time sync of
  `gap-handoff.html` with the actual state of forqsite" as out of scope, and requires "no
  build step". Automatic releases would change both. That is an operator decision to take
  before the automation phase, not a side effect of this one.
- **Not a content rewrite.** Claims are corrected only where re-verification finds them
  wrong. Gaps are closed only when forqsite has closed them. Wording changes for their own
  sake are out.

## Release commit

This phase verifies against one forqsite commit:
`nullvalues/forqsite@1fda3228322d5ad779f44c321c4013ccd247b3fa`, committed 2026-09-24 and
pinned 2026-09-24 (the tip of `main` in the forqsite repository when CONTENT-030 was built).
That is a dated record of this phase, not the current release commit. Since INFRA-020 the
current release commit lives only in the `release` object of `docs/claims-manifest.json`,
which `scripts/restamp.py` writes.

## Stories

| ID | Title | Status |
|----|-------|--------|
| CONTENT-030 | Inventory every stamped claim into a committed claims manifest | complete |
| CONTENT-031 | Re-verify and restamp the Known gaps list in both pages | complete |
| CONTENT-032 | Re-verify and restamp every remaining claim, and pin the pages to one release commit | complete |
| CONTENT-033 | Correct the restore example, its row-count comment and the prestart-drift sentence in index.html | complete |
| CONTENT-034 | Replace env parsing in the backup, cron and restore blocks with forqsite's own loader | complete |
| CONTENT-035 | New GAP entries for the upstream backup/restore defects found during Phase 12 | complete |
| CONTENT-036 | Checkpoint bookkeeping and backlog grooming pulled into cp-12 | complete |
| CONTENT-037 | Scrub operator-local absolute paths from tracked docs, and record the cp-12 security findings | complete |

### CONTENT-030 — The claims manifest

**Done when** a committed manifest lists every stamped claim in both pages. For each claim
it gives: an id, the page and location, the claim in one sentence, where in forqsite the
evidence lives (path and symbol or behaviour, never a host or an operator path), and the
stamp the claim currently carries. The manifest is derived from the pages through
`scripts/bundle-template.py extract`, not by grepping the bundle. It counts every stamp
occurrence, and each count matches the extracted templates.

**Done when** the release commit this phase verifies against is pinned in the manifest and
in the phase doc: one forqsite commit, chosen at build time and recorded with its date.

**Not done if** a stamp in either page has no manifest entry, or the manifest invents a
claim the page does not make.

### CONTENT-031 — The Known gaps list

**Done when** every Known gaps entry in both pages has been re-verified against the pinned
commit. Each is still open, changed or closed, and a closed gap is removed from the list
with the forqsite commit or file that closed it recorded in the manifest. Any gap the
re-verification finds that the list lacks is added. The Known gaps callout and its
`gap-handoff.html` counterpart carry the pinned commit and verification date.

**Not done if** a stamp changes without its entries being re-checked. A restamp is a claim
of verification. It is never a find-and-replace.

### CONTENT-032 — Every remaining claim, one release stamp

**Done when** every other stamped claim in the manifest has been re-verified against the
pinned commit, corrected where wrong, and restamped. This includes CER-029's ordering
assumption and the claims currently stamped `7089b9dc`. Both pages then carry exactly one
forqsite commit in their stamps. A reviewer can check that with one extract and grep per
page.

**Done when** both pages pass `bundle-template.py verify`, render (CER-005 and CER-012
apply: strip `<script>` before asserting a render), and are deployed. The drift check's
provenance line then names the release commit's deploy.

**Not done if** a claim that could not be verified keeps a fresh stamp. It is marked as
unverified, with the reason, instead.

### CONTENT-033 — Three unstamped corrections before checkpoint

The cp-12 gate refused because CER-038 is in Do Now. The operator decided on 2026-09-25 to fix
it inside this phase as a correction story, together with a second stale sentence that
CONTENT-032's builder found. The operator then widened it (2026-09-25) to a third stale line
in the same restore block, found while the story was being specced.

**Done when** the Backup & recovery restore example calls `scripts/restore.sh` the way its
usage line reads at the release commit, including the mandatory expected-database-name
argument. The block's row-count comment names the tables `restore.sh` actually counts at
that commit (`tenants`, not `sub_tenants`). The Incidents entry no longer says the prestart
check refuses to boot on drift: at the release commit both prestart migration checks are
advisory and exit 0. CER-038 is resolved. The prestart sentence is recorded as CER-039 and
the row-count comment as CER-040, and both are resolved with it.

**Not done if** anything else on either page changes, a stamp or the manifest changes (all three
passages are unstamped, and the manifest lists stamped claims only), or the argument names
or table names are written from memory rather than taken from the script.

### CONTENT-034 — Run the backup, cron and restore blocks under forqsite's own loader

cp-12's gates passed. A cold cross-corpus triage by two independent readers, followed by two
independent designs, then found three Backup & recovery blocks that fail at the release
commit. The backup and restore blocks grep `.env.local`, and against the shipped example that
returns four lines. The restore block targets a database that its `DATABASE_URL` does not
name. The cron line sources a file that forqsite never defines. The operator chose the fix
on 2026-09-25: run each script under dotenv-cli, which forqsite ships and uses for its own
`start` and `db:migrate`.

**Done when** the three blocks, run in a scratch checkout built from the release's own
`.env.local.example` with a stale `DATABASE_URL` already exported, hand the scripts exactly
the file's values. The restore block also says how the target is chosen, and the cron block
says what it assumes about `PATH`. The three findings are recorded as CER-041 to CER-043
and resolved.

**Not done if** the blocks are checked by reading them instead of running them, or anything
outside the backup and restore sections, a stamp or the manifest changes.

### CONTENT-035 — The same defects upstream, as Known gaps

forqsite's runbook uses the same grep line, and `backup.sh` passes the database URL, password
included, in `pg_dump`'s argv, while its own header says it does not. The tracing half of
the `backup.sh` finding is already GAP-009, so it is not repeated.

**Done when** two new GAP entries, in both pages, describe the class of each defect, and
each defect has been shown by running forqsite's own files at the release commit. Each entry
has an `added` manifest claim, and the Known-gaps union is recomputed. The Backup & recovery
caption no longer repeats the script's "never on the command line" promise (CER-044).

**Not done if** a stamp changes, GAP-009 is duplicated, or an entry claims an effect nobody
ran.

### CONTENT-036 — Bookkeeping and grooming before the tag

**Done when**:
- `docs/checkpoints.md` has a cp-10 section written from the tag and the phase-10 record,
  labelled as written after the fact (CER-032).
- CER-005 is settled by rendering `index.html#pipeline` over `http://` and `file://`.
- CER-011, CER-012 and CER-017 are recorded once as a spec-authoring convention in
  `docs/ideology.md`.
- The backlog gains five Do Later rows and the Phase 13 and Phase 14 dependency
  annotations, and loses its stale Do Now placeholder.

**Not done if** the cp-12 section is written here (the orchestrator writes it at tag time),
or either page changes.

### CONTENT-037 — Name the class, not the host, before the tag

The CP-12 security re-audit found operator-local absolute paths in tracked docs: the local
forqsite clone's path, this repository's own path, and a path on the original build machine.
They appear in four planning docs and 22 completed story specs. The operator decided on
2026-09-25 to scrub them before tagging cp-12.

**Done when** no tracked file names any of those paths or their parent directory. Each is
replaced by its class: `$FORQSITE_CLONE` or "the local forqsite clone", the repository root,
`file://$PWD/…`, or a description of the build machine. Each edited line keeps its meaning.
The leak is recorded as a resolved CER described by class only. The copy-paste U+200B wart
gets a Do Later row, and CER-049 gets the backup caption's `DATABASE_URL` note.

**Not done if** the flex tooling path changes, a line changes beyond its identifier, a page or
the manifest changes, or this story's own text names what it scrubs.

## Story ordering

CONTENT-030 runs first, because both later stories work from its manifest and the pinned
commit it records. CONTENT-031 and CONTENT-032 both edit both pages, so they run one after
the other, CONTENT-031 first. Each merges before the next branches. CONTENT-033 runs after
CONTENT-032 and before the cp-12 checkpoint. It edits `index.html`, which CONTENT-032 edited
last, and it clears the Do Now finding that blocked the gate.

CONTENT-034, CONTENT-035 and CONTENT-036 run after CONTENT-033 and before the cp-12
checkpoint, in the order 034 → 035 → 036. Each merges before the next branches. CONTENT-035
edits the caption and the `index.html` ledger after CONTENT-034 has rewritten that route.
CONTENT-036 counts on the backlog IDs the two before it assigned. The post-merge deploy step
from CONTENT-032 runs once, after CONTENT-036 merges.

CONTENT-037 runs after CONTENT-036 and before the cp-12 checkpoint. It takes the backlog IDs after
the ones CONTENT-036 assigned, and it changes no page, so the deploy step is unaffected.

## After this phase: the path to automatic releases

Recorded 2026-09-23 so that it survives between sessions. This is not in this phase's scope.
The operator's goal is for forqsite.help to ship automatically, matching the current forqsite
build. Measured against that goal:

- **Deploy is close.** `deploy.sh` and `drift-check.sh` are verified end to end against
  production. They are run by hand from a host with `scripts/deploy.env`. Neither repo has CI.
- **The claims manifest is missing.** This phase builds it.
- **A stale-claim check is missing.** Given the manifest, a checker can re-examine each
  claim's evidence at a new forqsite commit and list the claims whose evidence changed.
- **Rewriting a claim needs judgment.** Automation can detect the need and draft the change;
  a person still reviews the fix.
- **forqsite has no release event.** `package.json` is at `0.0.0` and there were about 138
  commits in the week to 2026-09-23. The `cp-PM*-main` checkpoint tags are the natural
  trigger.
- **`docs/brief.md` conflicts with the goal.** It rules out real-time sync with forqsite and
  requires no build step. Revise it before any automation is built.

Proposed sequence:
- **Phase 13:** revise the brief, then build a stale-claim checker keyed on forqsite
  checkpoint tags.
- **Phase 14:** a release job. When nothing is stale it restamps and deploys; when something
  is, it opens the stale claims for review.

Fully hands-off releases are realistic only when no claim has gone stale.

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| _(none)_ | — | No database. The claims manifest is a committed text file; its management surface is the repository itself, edited by the stories that re-verify claims. |

---

### CP-12 Cold-eyes checklist

- [x] written-never-read — no. `docs/claims-manifest.json` is read by the Tests blocks of
  CONTENT-031 to 036 and is the declared input of the Phase 13 checker. Every CER row this
  phase added is read by the checkpoint guard or sits in a triaged backlog section.
- [x] required-never-written — no. The `unverified`/marker path and the top-level `closed`
  array are optional branches that no reader requires. Neither was exercised this phase;
  CER-045 asks Phase 13 to fixture-test both before relying on them.
- [x] duplicate state — one instance, deliberate. The release commit is recorded both in
  the manifest's `release` object and in § Release commit above, and the manifest wins if
  they disagree. The two agree at checkpoint.
- [x] half-implementation — no unreachable branch or orphan producer. The manifest covers
  stamped claims only, so copyable command blocks sit outside it. That is a scope boundary,
  recorded as CER-046, not a half-built path.

Filled in at CP-12, 2026-09-25, from the CP-12 intent review's answers, re-checked against
the tree after CONTENT-037.
