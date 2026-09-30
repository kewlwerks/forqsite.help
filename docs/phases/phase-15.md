---
era: "001"
phase_class: production
---

# forqsite.help — Phase 15: Bring the unstamped command blocks under the claims manifest

← [Phase 14: Release from a forqsite checkpoint tag: harden, restamp, release](phase-14.md)

<!-- Phase doc = planning surface only. Story-level detail (acceptance criteria,
     file paths, implementation guidance, test instructions, codebase recon)
     belongs in docs/stories/<RAIL>/<ID>.md — not here. -->
## Goal

<!-- State this phase's single purpose in one or two sentences (docs/architecture.md
     § Phase-authoring convention, INFRA-243). If the work naturally splits into more
     than one purpose, that's a signal to open a sibling phase, not to widen this one. -->
Extend the claims manifest to the command blocks and gap-status claims no stamp covers, with forqsite evidence, and fix what that coverage finds, so the release job checks them.

**Sequenced after Phase 14** (operator decision 2026-09-30), so this phase's content ships through the release job. Its new stamps and claims are also the restamp tool's first stamps it has not seen before.

## Stories

| ID | Title | Status |
|----|-------|--------|
| — | Stories to be stubbed after Phase 14 checkpoints. Inputs: CER-046 (the unstamped command blocks outside the stamped sections), CER-048, CER-049, CER-051, CER-056 (gap-status claims outside the manifest). | — |

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| | | |

---

### CP-15 Cold-eyes checklist

- [ ] written-never-read — does anything this phase persists have no reader?
- [ ] required-never-written — does any read path depend on a value no writer produces?
- [ ] duplicate state — is any fact now stored twice with independent writers?
- [ ] half-implementation — is any branch unreachable, or any producer without its consumer?

— developer fills in after phase completion —
