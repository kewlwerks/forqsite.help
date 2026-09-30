---
id: INFRA-018
rail: INFRA
title: Rollback and a truthful backup report for deploy.sh
status: planned
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/deploy.sh

touches:
  - scripts/deploy-selftest.sh
  - docs/architecture.md
  - docs/checkpoints.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-031, CER-037 and CER-030.
- Add `deploy.sh --rollback <stamp>`. It restores each served file from its `.bak-<stamp>` by
  overwriting in place, through the existing verified copy path (bind mounts pin inodes). It then
  re-verifies sha256 values, restores the provenance sidecar, and prints the usual success block
  (CER-031).
- The success block's backups line lists only backups the remote step confirmed it wrote. A
  first deploy into an empty target lists none (CER-037).
- The prune report is exact per file, not per set (CER-030).

Selftests cover a first deploy into an empty target and a rollback. `docs/architecture.md` and
the manual rollback procedure in `docs/checkpoints.md` stop calling the `.bak` set a rollback
until this mode exists. Builds after INFRA-017, since both edit `deploy.sh`.

Operator ruling 2026-09-30: `release.sh` never rolls back on its own. The operator runs this
mode by hand.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
