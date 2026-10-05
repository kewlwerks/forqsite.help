---
era: "001"
phase_class: production
---

# forqsite.help — Phase 15: Keep the published docs correct: fix reader-facing errors, then release against current forqsite

← [Phase 14: Release from a forqsite checkpoint tag: harden, restamp, release](phase-14.md)

<!-- Phase doc = planning surface only. Story-level detail (acceptance criteria,
     file paths, implementation guidance, test instructions, codebase recon)
     belongs in docs/stories/<RAIL>/<ID>.md — not here. -->
## Goal

Fix the commands and claims a reader can get wrong today. Then reconcile the site with the
current forqsite checkpoint and release it through the existing release job.

## Scope decision (operator, 2026-10-05)

forqsite.help is a simple docs site, and Phases 13 to 14-post1 already built the release
machinery it needs. The operator narrowed this phase from "extend the claims manifest to every
command block" to two content stories and one release:
- **In scope:**
  - the reader-facing errors CER-048, CER-049, CER-051 and CER-059;
  - CER-058 as a single gap-handoff entry;
  - reviewing the claims that went stale since the `94f5c339` pin. At forqsite `origin/main`
    on 2026-10-01 that was 5 claims, after forqsite dropped `docker-compose.yml` and added a
    `Dockerfile`.
- **Out of scope:** the coverage work in CER-046 and CER-056. Both move to Do Much Later. The
  checker already guards every stamped claim, and that is enough for a site this size.
- **Process:** content stories use one spec, a build and a review. They get no two-planner
  drafts and no proving passes. Those stay for scripts that write to production or push.

**Sequenced after Phase 14-post1.** This phase's content ships through the release job.

## Stories

| ID | Title | Status |
|----|-------|--------|
| CONTENT-041 | Fix the reader-facing command errors (zero-width spaces, systemd EnvironmentFile, GAP-013's dotenv `-o`, the HTTPS pack pin) and record the admin-page install as a gap | planned |
| CONTENT-042 | Review the stale claims at the newest forqsite checkpoint, then release | planned |

## Story ordering

CONTENT-041 runs first. Its edits ship in CONTENT-042's release, so the site is released once.

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| none | — | This phase adds no persistent object. |

---

### CP-15 Cold-eyes checklist

- [ ] written-never-read — does anything this phase persists have no reader?
- [ ] required-never-written — does any read path depend on a value no writer produces?
- [ ] duplicate state — is any fact now stored twice with independent writers?
- [ ] half-implementation — is any branch unreachable, or any producer without its consumer?

— developer fills in after phase completion —
