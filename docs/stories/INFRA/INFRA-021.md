---
id: INFRA-021
rail: INFRA
title: release.sh: the attended release job
status: planned
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/release.sh

touches:
  - scripts/release-selftest.sh
  - .gitignore
  - README.md
  - docs/architecture.md
  - docs/checkpoints.md

narrative_roles: []
---

## Context

A bash script following the `deploy.sh` precedent, run by hand on the operator's host. It
never fetches, and the clone comes from `FORQSITE_CLONE`.

**Invocation:** `release.sh <target>` or `release.sh --latest-checkpoint`. The latter picks the
newest `cp-PM*-main` tag in the clone by version sort.

**Preconditions:** a clean tree on the default branch, not behind origin, and green selftests.
When `release.commit` already equals the target, it does nothing and exits 0.

**What it does, by checker exit:**
- **Exit 0.** `restamp.py`, then the selftests, then a commit whose fixed message names only
  the forqsite sha and claim counts, with the IDs of claims that hold in the body. Then it tags
  `rel-<sha>`, runs `deploy.sh`, runs `drift-check.sh --ref HEAD`, and pushes the commit and
  tag only after both pass.
- **Exit 3.** It writes the full report to a gitignored local file and prints the
  `--no-commits` summary (INFRA-019). It tells the operator to review these as a story, and
  exits with a distinct "review needed" code, touching nothing.
- **Any other exit.** It aborts with that code.

**Operator rulings 2026-09-30:**
- `--dry-run` is the default and `--yes` commits, deploys and pushes.
- Any scheduler is operator-local and untracked, and is enabled only after one attended release.
- If the post-deploy drift check fails, the job stops, does not push, and exits nonzero. It
  never rolls back on its own; `deploy.sh --rollback` (INFRA-018) stays the operator's call.

The selftest uses a fixture forqsite repo and the stub ssh and local server of the existing
selftests. It must be written for the stale path, not only the clean one. At forqsite
`origin/main` the checker already finds 5 stale claims, because `docker-compose.yml` was
deleted and a `Dockerfile` added. Name the host and schedule only by class.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
