---
id: INFRA-019
rail: INFRA
title: Checker hardening and a paste-safe report
status: planned
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/stale-claims.py

touches:
  - scripts/stale-claims-selftest.sh
  - README.md
  - docs/architecture.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-052 to CER-055 before the checker becomes a job's dependency.
- Pass `--` before `ls-tree` paths (CER-053).
- Scrub `GIT_*` from the child environment, except the variables the script itself sets, and
  pass `--no-ext-diff --no-textconv` wherever git can produce a patch (CER-054).
- Add selftest cases for exit 5 (CER-052) and for targets starting with `-`, such as `--output=…`
  and `-- -x` (CER-055).
- Add a `--no-commits` flag that omits `commit:` lines. The report then contains only text
  sourced from the manifest (IDs, verdicts, paths, symbols) and is safe to quote in a tracked
  story. Forqsite commit subjects can name deployment instances, so the full report never goes
  into a tracked file.

Remove "except 5" from `docs/architecture.md`'s selftest sentence.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
