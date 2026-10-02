---
era: "001"
phase_class: production
---

# forqsite.help — Phase 14-post1: Release hardening before the second release

<!-- Phase doc = planning surface only. Story-level detail (acceptance criteria,
     file paths, implementation guidance, test instructions, codebase recon)
     belongs in docs/stories/<RAIL>/<ID>.md — not here. -->
## Goal

<!-- State this phase's single purpose in one or two sentences (docs/architecture.md
     § Phase-authoring convention, INFRA-243). If the work naturally splits into more
     than one purpose, that's a signal to open a sibling phase, not to widen this one. -->
Make the release path's published provenance and its failure handling exactly true before the second release: deploy records commits, not tag objects; release.sh's partial-restamp recovery is tested; and its environment and push-target assumptions are stated or enforced.

**Parent phase:** Phase 14 (release job), complete at cp-14. This phase hardens what its first
release exposed. It does not change Phase 14's scope.

## Why this phase exists

The first attended release on 2026-10-01 published a provenance claim that names an
annotated tag object instead of a commit (CER-063). The Phase 14 reviews and audits also left
three small release-path gaps:
- the exit-11 partial-restamp recovery has no selftest case (CER-062);
- the header does not state which environment variables are inherited (CER-064);
- a split push URL makes every later run refuse (CER-061, item 4).

The next forqsite checkpoint already makes 5 claims stale, so the second release goes
through the review path. These gaps are cheapest to close before it. On 2026-10-01 the
operator chose to pull them forward as their own phase, ahead of Phase 15, rather than fold
them into Phase 15's coverage work. The phase is numbered `14-post1` so that every existing
"Phase 15" reference stays true.

## What this phase is not

- Not a release. The live sidecar keeps naming `60fd0cf` until the second release
  redeploys it, and nobody hand-edits production.
- Not Phase 15's claim-coverage work.
- Not CER-061 items (1) to (3) or CER-060. Both stay in Do Later.

## Story ordering

INFRA-022 and INFRA-023 touch different scripts and can run in parallel. Each spec is
reviewed by the operator before it is built.

## Stories

| ID | Title | Status |
|----|-------|--------|
| INFRA-022 | Deploy records the commit an annotated tag points to | complete |
| INFRA-023 | release.sh: test the partial-restamp recovery, state the environment, refuse a split push URL | complete |

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| none | — | This phase adds no persistent object. |

---

### CP-14-post1 Cold-eyes checklist

- [ ] written-never-read — does anything this phase persists have no reader?
- [ ] required-never-written — does any read path depend on a value no writer produces?
- [ ] duplicate state — is any fact now stored twice with independent writers?
- [ ] half-implementation — is any branch unreachable, or any producer without its consumer?

— developer fills in after phase completion —
