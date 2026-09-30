---
id: INFRA-017
rail: INFRA
title: Deploy configuration safe for unattended runs
status: planned
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/deploy.sh

touches:
  - scripts/drift-check.sh
  - scripts/read-deploy-env.sh
  - scripts/make-provenance.sh
  - scripts/deploy-selftest.sh
  - scripts/drift-check-selftest.sh
  - scripts/provenance-selftest.sh
  - docs/architecture.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-015, CER-033, CER-034 and CER-035: the four input-hygiene defects that matter once
`release.sh` (INFRA-021) branches on these scripts' exit codes, rather than a person reading
their output.
- `deploy.sh` gets a usage-error exit code of its own (64, as `stale-claims.py` uses), distinct
  from "configuration missing" (CER-015).
- `make-provenance.sh --ref` is restricted to a safe character class (CER-033).
- `drift-check.sh`'s curl calls pass `-q` first, plus `--globoff` (CER-034).
- **Operator ruling 2026-09-30 for CER-035: the environment wins.** `deploy.env` fills only keys
  the environment leaves unset, and never overrides one that is set.

Update the exit-code tables in `docs/architecture.md` and each script's header. Each fix gets a
selftest case that fails without it.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
