---
id: INFRA-022
rail: INFRA
title: Deploy records the commit an annotated tag points to
status: planned
phase: "14-post1"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/make-provenance.sh

touches:
  - scripts/deploy.sh
  - scripts/drift-check.sh
  - scripts/provenance-selftest.sh
  - scripts/deploy-selftest.sh
  - scripts/drift-check-selftest.sh
  - docs/architecture.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-063. The first attended release (`rel-94f5c339`, 2026-10-01) exposed it.
`deploy.sh --ref rel-94f5c339` printed `deployed 60fd0cf…`, and the drift check's `ref` line
and the served provenance sidecar both name `60fd0cf`. That sha is the annotated tag
*object*. The commit it points to is `d4c3991`. The bytes were correct, but the published
provenance claim is not a commit id, and `release.sh` always passes an annotated tag.

Resolve `--ref` to its commit (`<ref>^{commit}`) wherever a sha is recorded or printed, in
`make-provenance.sh`, `deploy.sh` and `drift-check.sh`. Add a selftest case per script that
uses an annotated tag and fails without the fix. Keep the INFRA-017 `REF_RE` check and
validate the ref before resolving it.

The live sidecar still names `60fd0cf` until the next release redeploys it. Do not hand-edit
production; the second release corrects it. Say so in the spec.

The operator chose to run this hardening phase before Phase 15 (2026-10-01), pulling these items forward from the backlog.

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
