---
id: CONTENT-042
rail: CONTENT
title: Review the stale claims at the newest forqsite checkpoint, then release
status: planned
phase: "15"
story_class: content
auth_gated: false
schema_introduces: false
primary_files:
  - docs/claims-manifest.json

touches:
  - index.html
  - gap-handoff.html
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

The site is pinned to forqsite `94f5c339` (`cp-PM105-main`). Forqsite has moved on since. At
its `origin/main` on 2026-10-01, measured against the old `1fda3228` pin, the checker found
the docker-related claims C-022, C-024 and C-025 stale, after forqsite dropped
`docker-compose.yml` and added a `Dockerfile`. Re-measure against the current pin. Those
numbers are stale themselves.
1. Pick the target: the newest `cp-PM*-main` tag in the operator's forqsite clone. The
   operator fetches; the job never does.
2. Run `stale-claims.py` against that target.
3. For each stale claim, verify what forqsite now does and rewrite the claim, and its page
   text, so it is true. The docker change may alter the gap-handoff sequencing advice, which
   is a judgment call. Mark each result `changed` with a `CHANGED:` note, and use `closed[]`
   if a gap closed.
4. The checker must exit 0 at the target.

**Post-merge step.** Run an attended release, exactly as CONTENT-040 did:
`release.sh <target>` as a dry run, shown to the operator. Then `--yes` on the operator's go.
Its drift check should now show the provenance sidecar naming a commit, which closes the
loop on CER-063.

Depends on CONTENT-041, whose edits ship in this release. Keep the spec short (operator ruling
2026-10-05). There is no proving pass.

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
