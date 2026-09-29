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
| CONTENT-038 | Revise the brief: release-time reconciliation in scope, no-build-step scoped to the published artifact | draft |

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
it revises is what permits the rest. The stale-claim checker stories follow after it merges.
They are not specced yet and will be added to this table when they are.

## Resume state (2026-09-29)

**Wording approved; build under way.** The operator approved the four
`docs/brief.md` changes in CONTENT-038 (core belief, constraint, out-of-scope line, dated
note) on 2026-09-28. The operator then widened the story to `docs/ideology.md` lines 73-74
and `README.md` lines 45-46. The exact text for those two passages is in CONTENT-038
§ Instructions items 5 and 6. The operator approved that text as written on 2026-09-29,
and the build started.

**After CONTENT-038 merges,** spec the stale-claim checker stories. Their inputs:
- CER-045: the manifest schema, plus fixture tests for the `unverified` and `closed` paths.
- CER-046: command blocks that sit outside the manifest.
- CER-011 and CER-012: design constraints on quote matching.
- The Phase 12 plan in `docs/phases/phase-12.md` § "After this phase".

Phase 14 prerequisites: CER-031, 034, 035 and 037.

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| | | |

---

### CP-13 Cold-eyes checklist

- [ ] written-never-read — does anything this phase persists have no reader?
- [ ] required-never-written — does any read path depend on a value no writer produces?
- [ ] duplicate state — is any fact now stored twice with independent writers?
- [ ] half-implementation — is any branch unreachable, or any producer without its consumer?

— developer fills in after phase completion —
