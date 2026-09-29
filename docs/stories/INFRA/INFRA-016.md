---
id: INFRA-016
rail: INFRA
title: Stale-claim checker against a newer forqsite commit
status: planned
phase: "13"
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/stale-claims.py
touches:
  - scripts/stale-claims-selftest.sh
  - CLAUDE.build.md
  - README.md
  - docs/architecture.md
narrative_roles: []
---

## Context

This is the Phase 13 goal. The revised brief (CONTENT-038) allows release-time
reconciliation. At release time, list the manifest claims whose evidence changed between
the pinned release commit (`release.commit` in `docs/claims-manifest.json`) and a newer
forqsite commit, such as a `cp-PM*-main` checkpoint tag. The checker reports and never
edits: it does not change the manifest or the pages. Rewriting a stale claim takes judgment
(phase-12.md § After this phase).

Intended shape (operator-approved 2026-09-29; the spec-writer settles the details):
- `scripts/stale-claims.py`, python3 stdlib only, following the precedent of
  `scripts/bundle-template.py`. It takes a local forqsite clone path and a target
  commit-ish. The clone path is never written into the repo (the `FORQSITE_CLONE`
  convention).
- It walks forqsite's history from the release commit to the target, over the paths each
  claim's `evidence`, `absent` and `counts` name. It then re-applies the Phase 12
  verification semantics at the target: an evidence `symbol` is present in its path, an
  `absent` symbol or path is still absent, and a `counts` value still holds. The existing
  source of those semantics is the inline Tests code in CONTENT-031 and CONTENT-032.
- Per claim it reports: untouched (no named path changed), holds (paths changed and every
  check still passes), or stale (a check fails). For each stale claim it names the failing
  check and the commits that touched its paths. `unverified` claims are always surfaced.
  `closed` records (CER-045) are checked for reopening. The exit code is nonzero when
  anything is stale.
- Design constraints: symbol and quote matching tolerate whitespace and soft-wrap
  differences (CER-011). Inert `<script>` source never counts as rendered (CER-012), so any
  page-side check must respect that or state that it is out of scope.
- Tests: `scripts/stale-claims-selftest.sh`, following the `*-selftest.sh` precedent. It
  builds a throwaway fixture git repo and fixture manifest covering each verdict, including
  the `unverified` marker path and a `closed` array (the fixture half of CER-045). Build
  standards `test_command` in `CLAUDE.build.md` changes from `true` to run the selftests.
- Document usage in `README.md` § Updating. This replaces "does not exist yet", which
  CONTENT-038 wrote for this story to retire. Also document it in `docs/architecture.md`.

Builds after INFRA-015 and reads the schema reference it adds. CER-046 (command blocks) is
deferred, so the checker covers the stamped claims only.

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
