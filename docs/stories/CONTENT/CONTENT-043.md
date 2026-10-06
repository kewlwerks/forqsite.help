---
id: CONTENT-043
rail: CONTENT
title: Restore block clears inherited DATABASE_URL and key before running
status: complete
phase: "15"
story_class: content
auth_gated: false
schema_introduces: false
primary_files:
  - index.html
touches:
  - docs/cer/backlog.md
narrative_roles: []
---

## Context

This story fixes a MEDIUM finding from the CP-15 security audit. CONTENT-041 removed `-o`
from the restore block so the page matches forqsite, which never uses it. Without `-o`, a
`DATABASE_URL` or `FORQSITE_CREDENTIALS_ENCRYPTION_KEY` already exported in the shell
overrides the checkout's `.env.local`. The block's first comment says the checkout picks the
target, and only a note below the block warns otherwise.

`restore.sh` refuses unless `current_database()` equals the typed name. That check does not
catch two databases with the same name on different hosts, such as a rehearsal database
named like production, or a shell still holding production's URL.

The operator ruled on 2026-10-06 to fix this before tagging cp-15. Content-story process
applies: one spec, a build and a review.

**Shipping.** The forqsite pin does not move (it stays `afed86a7`), so `release.sh` has
nothing to do here: it exits 0 when the target equals the pin. The story ships by a hand
deploy at the merged commit, `scripts/deploy.sh --ref <merge commit>`, followed by
`scripts/drift-check.sh`, on the operator's go. The stamps stay valid because forqsite has
not moved.

## Ensures

The restore block clears both variables inside the block, before anything reads them. With
that in place, the checkout's `.env.local` alone decides the restore target and the key.
Nothing else on either page changes. No claim quotes the restore block, so the manifest is
unchanged.

## Instructions

1. In `index.html`, edit only through `python3 scripts/bundle-template.py`: extract, edit,
   inject, verify. In the restore block, insert two lines directly before the line
   `# key first — the script refuses to run without it (legacy var name, see GAP-008)`:
   ```
   # clear anything this shell exported, so .env.local alone decides the target and the key
   unset DATABASE_URL FORQSITE_CREDENTIALS_ENCRYPTION_KEY AI_CREDENTIAL_ENCRYPTION_KEY
   ```
   The next line re-exports `AI_CREDENTIAL_ENCRYPTION_KEY` from `.env.local`, so unsetting it
   first is correct.
2. In the note under the block, which begins "You choose the target by choosing the
   checkout", make the parenthetical about a shell-exported `DATABASE_URL` point to the
   `unset` line. Keep the change to one clause.
3. In `docs/cer/backlog.md`, add a CER-070 row recording this finding, marked
   `**RESOLVED Phase 15 — CONTENT-043.**`.

## Tests

```bash
set -e; cd "$(git rev-parse --show-toplevel)"; T=$(mktemp -d)
python3 scripts/bundle-template.py verify index.html >/dev/null
python3 scripts/bundle-template.py verify gap-handoff.html >/dev/null
python3 scripts/bundle-template.py extract index.html $T/i.html >/dev/null
python3 - $T/i.html <<'EOF'
import sys
t=open(sys.argv[1]).read()
u="unset DATABASE_URL FORQSITE_CREDENTIALS_ENCRYPTION_KEY AI_CREDENTIAL_ENCRYPTION_KEY"
assert t.count(u)==1, "unset line missing or duplicated"
a=t.index(u); b=t.index("# key first"); c=t.index("export AI_CREDENTIAL_ENCRYPTION_KEY")
assert a<b<c, "unset must precede the key export"
EOF
git diff --quiet main -- gap-handoff.html docs/claims-manifest.json
grep -q "^| CER-070 .*RESOLVED Phase 15 — CONTENT-043" docs/cer/backlog.md
FORQSITE_CLONE="${FORQSITE_CLONE:?}" python3 scripts/stale-claims.py --no-commits cp-PM107-main >/dev/null
rm -rf $T; echo OK
```

## Out of scope

- The two other CP-15 security LOW findings. The `--save-exact` finding is not a defect:
  forqsite's runbook pins without it. The file-mode advice was ruled out on 2026-10-05.
- Any other page text.
