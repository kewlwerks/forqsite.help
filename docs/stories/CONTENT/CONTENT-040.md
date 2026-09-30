---
id: CONTENT-040
rail: CONTENT
title: Close GAP-006 at cp-PM105-main
status: planned
phase: "14"
story_class: content
auth_gated: false
schema_introduces: false
primary_files:
  - docs/claims-manifest.json

touches:
  - gap-handoff.html
  - index.html
  - README.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

forqsite `8112020ec1d92e1bdd84cd86ffe3a90fd967c125` (2026-09-24, in `cp-PM105-main`)
replaced firstrun.sh step 7.5's inline grep with `scripts/lib/check-required-env.sh`. That
helper treats an empty or whitespace-only value as missing, and
`tests/repo/firstrun-required-vars.test.ts` covers it. Both Phase 14 planners verified this.

**Operator ruling 2026-09-30: close the gap in full.** GAP-006's third acceptance test asked
for "a tests/ or CI shellcheck step"; the tests/ half is met, and the closed record says so.

The fix is not an ancestor of the current pin, so this story's content targets `cp-PM105-main`
and ships only through the release job:
- move the GAP-006 claim to `closed[]` with `closed_by` and evidence literals at the target
  that show the fix;
- remove the GAP-006 entry from `gap-handoff.html`;
- fix all **three** GAP-006 mentions in `index.html` (a setup-route note, a pipeline step drawn
  as bad, and a ledger row);
- recompute the Known-gaps claim's evidence union;
- update the README item count.

Its post-merge step is the first real attended release, through `release.sh` (INFRA-021).
Depends on INFRA-020, INFRA-021 and CONTENT-039. The other gap-status mentions outside the
manifest are CER-056 (Phase 15).

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
