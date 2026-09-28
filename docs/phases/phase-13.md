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

## Stories

| ID | Title | Status |
|----|-------|--------|
| CONTENT-038 | Revise the brief: release-time reconciliation in scope, no-build-step scoped to the published artifact | draft |

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
