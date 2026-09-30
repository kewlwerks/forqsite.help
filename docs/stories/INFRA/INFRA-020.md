---
id: INFRA-020
rail: INFRA
title: restamp.py: pin a new release commit in the manifest and both bundles
status: planned
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

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
