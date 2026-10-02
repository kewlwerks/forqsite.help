---
id: INFRA-024
rail: INFRA
title: release.sh pushes exactly the commit and tag it deployed
status: planned
phase: "14-post1"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/release.sh
touches:
  - scripts/release-selftest.sh
  - docs/architecture.md
  - docs/cer/backlog.md
narrative_roles: []
---

## Context

This closes the CP-14-post1 security audit's MEDIUM finding and its LOW companion. The
operator added this story to Phase 14-post1 on 2026-10-01, before the checkpoint, because the
project fixes MEDIUM findings before a phase ends.

**The MEDIUM finding.** INFRA-023 made `release.sh` push with explicit `src:dst` refspecs. That
fixed *where* the push goes, but not *what* it pushes. `refs/heads/main:refs/heads/main`
sends whatever `main` points to at push time. A commit that lands on `main` while the deploy
and drift check run would be pushed without appearing in the "the push will also carry"
listing, which is built before any write. The provenance and the tag would still name the
release commit.

**The LOW finding.** `rel-<t8>` is resolved separately by `deploy.sh`, by `drift-check.sh` and
by the push. Nothing compares any of those resolutions with `RELEASE_COMMIT`. If the tag were
moved while the job ran, origin could end up with a `rel-<t8>` that differs from the commit in
the live sidecar.

**Intended shape** (operator-approved 2026-10-01; the spec-writer settles the details):
- Capture `RELEASE_COMMIT` and the tag object's sha right after `git tag`.
- Push `${RELEASE_COMMIT}:refs/heads/<branch>` and `<tag object sha>:refs/tags/<tag>`, keeping
  `--atomic`. This applies to the job's own push and to every printed recovery push.
- Before pushing, check that `deploy.sh`'s `deployed <sha>` and `drift-check.sh`'s `ref <sha>`
  both equal `RELEASE_COMMIT`. On a mismatch, stop with a distinct, documented exit, push
  nothing, and print recovery steps.
- Add selftest cases for both:
  - a commit added to `main` during the deploy window is NOT pushed;
  - a tag moved mid-run is caught before the push.
- Update the header invariants and `docs/architecture.md`.

Out of scope: the `pushInsteadOf` gap. It is stated and ruled (INFRA-023).

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
