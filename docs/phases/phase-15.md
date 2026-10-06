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
| CONTENT-041 | Fix the reader-facing command errors (zero-width spaces, systemd EnvironmentFile, GAP-013's dotenv `-o`, the HTTPS pack pin) and record the admin-page install as a gap | complete |
| CONTENT-042 | Review the stale claims at the newest forqsite checkpoint, then release | complete |
| CONTENT-043 | Restore block clears inherited DATABASE_URL and key before running | complete |

## Story ordering

CONTENT-041 runs first. Its edits ship in CONTENT-042's release, so the site is released once.

## What happened (2026-10-05 to 2026-10-06)

- **CONTENT-041.** Before the build, an independent fable and opus back-check reviewed the
  spec. It found the `chmod 600` advice wrong, the pack upload missing its second object, and
  GAP-003 contradicting the fixed units. The operator reversed CER-049: the site now drops
  `-o` to match forqsite, which never uses it.
  - The first build failed review: an unqualified "packs need no backup" sentence would have
    told readers who installed packs from a `file:` path to skip a needed backup. That build
    was discarded, the spec was amended, and the story was rebuilt.
  - GAP-015 was added at P2 correctness.
- **CONTENT-042.** Forqsite now ships an opt-in Docker production path. The operator chose
  option A: the site keeps documenting forqsite's default single-instance install and corrects
  every fact about forqsite. GAP-004 is closed as superseded. Review found two spec-mandated
  phrases inaccurate (one MEDIUM, one LOW), and they were fixed under a spec amendment
  before merge.
- **Release.** `release.sh --yes cp-PM107-main` moved the pin from `94f5c339` to
  `afed86a7`. Of 42 claims, 38 are open, 2 changed and 1 added. The 42nd, the Known-gaps claim, carries no result. It made release commit
  `18c5fd2` and tag `rel-afed86a7`, which were deployed, drift-checked and pushed. The live
  provenance sidecar now names the release commit `18c5fd2`, not a tag object, so the
  CER-063 fix is live. Measured from the old pin, the release saw 21 claims untouched and 21 holding. Measured
  from the new pin, the checker reports 42 untouched claims and 2 closed records (GAP-006,
  GAP-004).

**CONTENT-043 was added at checkpoint (2026-10-06).** The CP-15 security audit passed with
one MEDIUM finding: the restore block let a shell-exported `DATABASE_URL` override the
checkout's choice of target. The operator ruled to fix it before tagging. Because the
forqsite pin does not move, it ships by a hand deploy and drift check, not `release.sh`.

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| none | — | This phase adds no persistent object. |

---

### CP-15 Cold-eyes checklist

- [x] written-never-read — one deliberate instance. `closed[].note` is for people only: no code
  reads it, and its schema row says so. Only GAP-004's record carries one, and nothing beyond
  CONTENT-042's own check enforces its "no claim ids" rule. Accepted, because the phase scoped
  machinery out.
- [x] required-never-written — none. `restamp.py` writes every stamp and the pin.
- [x] duplicate state — low risk. Gap status lives in the manifest and on the gap page, which
  the checker guards, and in the backlog. The README's "10 items, GAP-003 to GAP-015" is
  counted by hand, so it will drift when a gap closes. That is the deferred CER-056 class.
- [x] half-implementation — none. Every producer has a consumer, and the release is deployed,
  drift-checked and pushed.

Filled 2026-10-06 at checkpoint, from the intent and docs gates.
