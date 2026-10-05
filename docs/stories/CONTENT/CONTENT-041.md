---
id: CONTENT-041
rail: CONTENT
title: Fix the reader-facing command errors and record the admin-page install as a gap
status: planned
phase: "15"
story_class: content
auth_gated: false
schema_introduces: false
primary_files:
  - index.html

touches:
  - gap-handoff.html
  - docs/claims-manifest.json
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Plain page fixes for errors a reader can hit today. Each one is verified against forqsite at
the current pin `94f5c339` before it is changed.
- **CER-051.** Copy-paste blocks that open with a comment begin with U+200B, a zero-width
  space, so pasted commands can break. Remove every one in both bundles.
- **CER-048.** The `EnvironmentFile=` line in both systemd units on the Process supervision
  route. Confirm what forqsite actually needs, and correct both units.
- **CER-049.** GAP-013's proposed fix runs `pnpm exec dotenv -e .env.local -- scripts/backup.sh`
  without `-o`. Reconcile it with how `index.html`'s own backup block loads its environment.
- **CER-059.** The Provider lifecycle route's "Publishing a reviewed pack" step 4 pins an
  HTTPS tarball specifier. Forqsite's runbook says to pin by scoped package name. Rewrite the
  step as CONTENT-039 did for the `file:` install.
- **CER-058.** forqsite's own admin install page prints the withdrawn `file:` command. Add one
  gap-handoff entry for it, with evidence, at the next free GAP number. Closed gap numbers are
  never reused.

Edit the bundles only through `scripts/bundle-template.py`. Where an edit changes the text of
an existing claim's quote, update that claim and mark it `changed`. Keep the spec short: this
is a content story (operator ruling 2026-10-05). There is no proving pass.

## Ensures

<!-- spec-writer elaborates -->

## Out of scope

<!-- spec-writer elaborates -->
