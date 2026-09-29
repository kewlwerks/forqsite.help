---
era: "001"
phase_class: production
---

# forqsite.help — Phase 13: Release-time reconciliation: revise the brief, then check claims against a new forqsite commit

← [Phase 12: One stamp per release: re-verify every published claim against one forqsite commit](phase-12.md)

<!-- Phase doc = planning surface only. Story-level detail (acceptance criteria,
     file paths, implementation guidance, test instructions, codebase recon)
     belongs in docs/stories/<RAIL>/<ID>.md — not here. -->
## Goal

<!-- State this phase's single purpose in one or two sentences (docs/architecture.md
     § Phase-authoring convention, INFRA-243). If the work naturally splits into more
     than one purpose, that's a signal to open a sibling phase, not to widen this one. -->
Make the brief permit release-time reconciliation and pre-publication tooling while keeping the published artifact plain, self-contained HTML; then build a stale-claim checker that lists the manifest claims whose evidence changed between the pinned release commit and a newer forqsite commit.

## Why this phase exists

Phase 12 left forqsite.help with one release stamp and a claims manifest. The next step
toward automatic releases is a checker that reads forqsite. `docs/brief.md` rules out
"real-time sync" and requires "no build step" without saying whose, so as written it forbids
that step (phase-12.md § After this phase). On 2026-09-28 the operator ruled on both. The
docs are reconciled with forqsite at release time and are never live-coupled to it. "No
build step" governs the published pages and their reader, not the tooling that prepares a
release. This phase records that ruling, then builds the checker it permits. CER-045 (a
manifest schema reference, plus fixture tests) and CER-046 (bringing the command blocks into
the manifest) are its inputs.

## What this phase is not

- **Not a release job.** No trigger, CI, or unattended restamp and deploy. That is Phase 14,
  and CER-031, 034, 035 and 037 are its prerequisites.
- **Not a change to the published artifact.** The pages stay plain, self-contained HTML that
  fetches nothing at runtime. No page is edited to make the checker possible.
- **Not live sync.** The checker runs at release time against a chosen forqsite commit.
  Nothing published reads forqsite.

## Stories

| ID | Title | Status |
|----|-------|--------|
| CONTENT-038 | Revise the brief: release-time reconciliation in scope, no-build-step scoped to the published artifact | complete |
| INFRA-015 | Claims manifest schema reference | complete |
| INFRA-016 | Stale-claim checker against a newer forqsite commit | complete |

### CONTENT-038 — Revise the brief

**Done when** `docs/brief.md` puts release-time reconciliation in scope, scopes "no build
step" to the published artifact, and records the ruling in a dated note. The same ruling is
carried into `docs/ideology.md`'s self-containment value and `README.md` § Updating's sync
sentence, and only those passages change. Both pages are also shown to make no network
request when opened from `file://`.

**Not done if** any other passage, document or page changes, or the self-contained claim is
only asserted rather than checked at load time.

## Story ordering

CONTENT-038 runs first and merges before any other story in this phase branches. The brief
it revises is what permits the rest. INFRA-015 (the manifest schema reference) comes next,
then INFRA-016 (the checker), which builds against that reference.

CER-046 (bringing the unstamped command blocks into the manifest) was deferred by the
operator on 2026-09-29. It stays in Do Later as a Phase 14 prerequisite, so the checker
covers stamped claims only.

## Resume state (2026-09-29)

**All three stories are complete and merged; the phase is at checkpoint.** CONTENT-038
revised the brief, with the operator approving all wording, items 5 and 6 included, on
2026-09-29. INFRA-015 added § Claims manifest schema to `docs/architecture.md`. INFRA-016
added `scripts/stale-claims.py` and its selftest, and the selftests became the Build
standards `test_command`. The operator accepted the four decisions in INFRA-016's spec
before it was built. CER-045 is resolved, CER-046 is deferred to Phase 14, and the
reviewer's accepted exit-5 deviation is CER-052.

Phase 14 prerequisites: CER-031, 034, 035, 037 and 046.

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| none | — | This phase introduces no persistent schema object. `docs/claims-manifest.json` is Phase 12's, and the stale-claim checker writes nothing. |

---

### CP-13 Cold-eyes checklist

- [x] written-never-read — no. The checker persists nothing. `closed[]` and `marker` are
  read by the checker; no manifest has used them yet, and § Claims manifest schema records
  that.
- [x] required-never-written — one accepted case. No manifest yet carries `closed[]` or a
  `marker`, so the `reopened` and `unverified` paths run only against the selftest's
  fixtures. That is by design (CER-045). `FORQSITE_CLONE` is supplied by the operator and
  documented.
- [x] duplicate state — one instance, accepted. The test command lives in `CLAUDE.build.md`
  § Build standards, in `CLAUDE.md` § Story test verification (whose line adds a `FAIL:`
  marker that survives the `tail`), and in the untracked `.companion/pairmode_context.json`
  that the build gate actually executes. The first two are tracked and were aligned at
  cp-13. The third is pairmode tooling state, set by hand in INFRA-016's post-merge step.
  A fresh checkout must set it again.
- [x] half-implementation — one item, tracked. The checker's exit 5 is implemented but
  untested (CER-052). The CP-13 security audit's LOW findings are CER-053 to CER-055.

Filled 2026-09-29 at checkpoint, from the intent review and the security audit.
