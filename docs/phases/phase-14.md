---
era: "001"
phase_class: production
---

# forqsite.help — Phase 14: Release from a forqsite checkpoint tag: harden, restamp, release

← [Phase 13: Release-time reconciliation: revise the brief, then check claims against a new forqsite commit](phase-13.md)

<!-- Phase doc = planning surface only. Story-level detail (acceptance criteria,
     file paths, implementation guidance, test instructions, codebase recon)
     belongs in docs/stories/<RAIL>/<ID>.md — not here. -->
## Goal

<!-- State this phase's single purpose in one or two sentences (docs/architecture.md
     § Phase-authoring convention, INFRA-243). If the work naturally splits into more
     than one purpose, that's a signal to open a sibling phase, not to widen this one. -->
Build a hand-run release job that restamps and deploys forqsite.help when no claim is stale and hands off a paste-safe review when one is, together with the hardening it needs to run truthfully, and prove it with one real release at cp-PM105-main that closes GAP-006.

## Why this phase exists

Phase 13 built `scripts/stale-claims.py`. What it lacks is a release that uses the checker:
one that restamps and deploys when nothing is stale, and hands off a review when something is.
The site is currently behind a closed gap. forqsite fixed GAP-006 on 2026-09-24, after the
pinned release commit.

The plan was synthesized on 2026-09-30 from two independent planner drafts (fable and opus),
and the orchestrator verified their claims against the repo and a forqsite clone. The operator
approved it on 2026-09-30.

## What this phase is not

- **Not CI and not a scheduler in the tree.** The job is hand-run. Any timer stays local to the
  operator's host and untracked, and is enabled only after one attended release.
- **Not automatic rewriting of stale claims.** Stale claims are reviewed as stories, as
  CONTENT-040 does.
- **Not command-block coverage beyond the stamped sections.** That is Phase 15.
- **Not a change to what the published artifact is,** and not flex or pairmode tooling.

## Operator decisions (2026-09-30)

1. **Shape:** Phase 14, then Phase 15 (coverage). The backlog dispositions are recorded in
   `docs/cer/backlog.md`.
2. **Stamp meaning:** after a mechanical restamp, a stamp means that every recorded evidence
   check passed. The IDs of claims that hold are listed in each release commit, and the
   meaning is revisited after two releases.
3. **Autonomy:** attended first. `--dry-run` is the default and `--yes` acts.
4. **Drift failure after a deploy:** stop and report. There is no automatic rollback.
5. **Defaults:**
   - the environment wins over `deploy.env` (CER-035);
   - release tags are named `rel-<forqsite short sha>`;
   - GAP-006 closes in full;
   - CER-036 and CER-047 stay in Do Later.

## Story ordering

1. INFRA-017, then INFRA-018. Both edit `deploy.sh`.
2. INFRA-019 and CONTENT-039. They are independent of the first two.
3. INFRA-020. It needs CONTENT-039 merged before its first real run.
4. INFRA-021.
5. CONTENT-040. Its post-merge step is the first attended release at `cp-PM105-main`.

Each story is specced, and the spec reviewed by the operator, before it is built.

## First release (2026-10-01)

CONTENT-040's post-merge step ran as planned, in this order:
1. The bootstrap tag `rel-1fda3228`, an annotated tag on cp-13's commit, was created and then
   pushed with the operator's approval.
2. The story's Tests block was re-run with restamp present: `ALL-OK`, no `SKIP`.
3. `scripts/release.sh cp-PM105-main` ran as a dry run. Its output matched the spec line for
   line.
4. On the operator's go, `scripts/release.sh --yes cp-PM105-main` exited 0.
   - The restamp moved the pin from `1fda3228` to `94f5c339`. Of 42 claims, 40 are `open` and
     1 is `changed`.
   - It made release commit `d4c3991` and annotated tag `rel-94f5c339`.
   - The deploy and drift check passed: the served bytes match the ref for both bundles.
   - It then pushed main, carrying the phase's 39 reviewed commits, and the tag.

After the release, the checker at the target reports 42 untouched claims and 1 closed record,
0 reopened. GAP-006 is closed, and its fix `8112020e` is now an ancestor of `release.commit`.

One defect surfaced: `deploy.sh --ref` records an annotated tag's object sha (`60fd0cf`), not
the commit it peels to. The bytes are correct, but the provenance sidecar names the tag
object. That is filed as CER-063.

Additional rulings made during the build (2026-10-01) are recorded in each story's spec:
- the `--ref` class (INFRA-017);
- the rollback design (INFRA-018);
- strict `--no-commits` and `GIT_NO_LAZY_FETCH` (INFRA-019);
- the restamp defaults and the bootstrap tag (INFRA-020);
- the ahead listing and the printed rollback command (INFRA-021);
- the explicit release target and the note sweep (CONTENT-040).

At the operator's direction, INFRA-018, INFRA-020 and INFRA-021 each got an adversarial fable
proving pass between build and review. The passes on INFRA-018 and INFRA-020 found MEDIUM
defects, which were fixed under spec amendments before review. The pass on INFRA-021 found
none.

## Stories

| ID | Title | Status |
|----|-------|--------|
| INFRA-017 | Deploy configuration safe for unattended runs | complete |
| INFRA-018 | Rollback and a truthful backup report for deploy.sh | complete |
| INFRA-019 | Checker hardening and a paste-safe report | complete |
| CONTENT-039 | Claims for the command blocks inside stamped sections | complete |
| INFRA-020 | restamp.py: pin a new release commit in the manifest and both bundles | complete |
| CONTENT-040 | Close GAP-006 at cp-PM105-main | complete |
| INFRA-021 | release.sh: the attended release job | complete |

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| none | — | This phase adds no database object. The `closed[]` manifest array and `rel-<sha>` tags are managed by review stories, `restamp.py` and `release.sh`, and documented in `docs/architecture.md`. `.release-report.txt` is a gitignored, regenerated report with no editable fields. |

---

### CP-14 Cold-eyes checklist

- [ ] written-never-read — does anything this phase persists have no reader?
- [ ] required-never-written — does any read path depend on a value no writer produces?
- [ ] duplicate state — is any fact now stored twice with independent writers?
- [ ] half-implementation — is any branch unreachable, or any producer without its consumer?

— developer fills in after phase completion —
