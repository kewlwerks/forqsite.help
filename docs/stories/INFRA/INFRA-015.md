---
id: INFRA-015
rail: INFRA
title: Claims manifest schema reference
status: planned
phase: "13"
story_class: doc
auth_gated: false
schema_introduces: false
primary_files:
  - docs/architecture.md
touches: []
narrative_roles: []
---

## Context

Closes the documentation half of CER-045. The field vocabulary of
`docs/claims-manifest.json` is defined only across the CONTENT-030 to CONTENT-032 and
CONTENT-035 to CONTENT-037 specs, and no reference states it. These fields are `release`,
`stamps`, `claims`, `quote`, `evidence`, `absent`, `counts`, `result`
(`open`/`changed`/`added`/`unverified`), `marker`, `closed_by`, `note` prefixes
(`CHANGED:`, `UNVERIFIED:`, `MISMATCH:`), and the top-level `closed` array that no manifest
has used yet. The stale-claim checker (INFRA-016) reads this manifest and needs one
authoritative definition to build against. Write that definition once, where a reader of
the architecture finds it, and derive every field's meaning from the specs that introduced
it and from the live manifest. Do not invent semantics. Where a spec and the manifest
disagree, or a field was specced but never exercised (`closed`, `marker`), say so.

Operator decision 2026-09-29: this story and INFRA-016 are Phase 13's checker work. CER-046
(command blocks into the manifest) is deferred.

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
