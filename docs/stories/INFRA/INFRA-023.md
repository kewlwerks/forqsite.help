---
id: INFRA-023
rail: INFRA
title: release.sh: test the partial-restamp recovery, state the environment, refuse a split push URL
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

Closes CER-062, CER-064 and item (4) of CER-061. Items (1) to (3) stay open in CER-061.
- **CER-062.** Add a selftest case for the exit-11 partial-write path, the recovery
  amended into INFRA-021's spec in commit ebff15c. Make restamp fail mid-write, for example
  with a read-only `docs/`. Assert exit 11, the `git restore --staged --worktree -- .` line,
  and a clean tree after running that line.
- **CER-064.** Add one header sentence: `release.sh` unsets only the `GIT_*` variables that
  redirect the repository. Inherited `GIT_CONFIG_*`, `GIT_SSH_COMMAND` and similar variables
  apply on purpose, because the push needs the operator's ssh setup. The read-only and
  never-fetches claims therefore hold only for a benign environment.
- **CER-061 (4).** Add a precondition that refuses, with an existing configuration exit code
  or a justified new one, when `remote.origin.pushurl` is set and differs from the fetch
  URL. Otherwise the push lands somewhere `ls-remote` never reads, and every later run
  refuses with exit 10. Add a selftest case for it. The refusal must not print either URL.

The operator chose to run this hardening phase before Phase 15 (2026-10-01), pulling these items forward from the backlog.

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
