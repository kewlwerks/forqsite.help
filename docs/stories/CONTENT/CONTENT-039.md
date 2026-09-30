---
id: CONTENT-039
rail: CONTENT
title: Claims for the command blocks inside stamped sections
status: planned
phase: "14"
story_class: content
auth_gated: false
schema_introduces: false
primary_files:
  - docs/claims-manifest.json

touches:
  - index.html
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes the stamped-scope part of CER-046; the row stays open for Phase 15. Stamps S-02
(Upgrade) and S-03 (Provider packs) cover whole sections back to their h2 headings. Both
sections contain `<pre>` command blocks that no claim checks, so a mechanical restamp
(INFRA-020) would re-assert commands nothing verified. Add a claim for each such block, with
forqsite evidence at the current `release.commit`, following § Claims manifest schema. The
Phase 13 planner counted 2 such blocks among index.html's 21 `<pre>` blocks. The spec must
confirm that count from the extracted template and the stamps' `scope` text.

Change page text only if a block turns out to be wrong at the pin, recording that as `changed`.
Must merge before INFRA-020's first real run.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
