---
era: "001"
phase_class: production
---

# forqsite.help — Phase 14-post1: Release hardening before the second release

<!-- Phase doc = planning surface only. Story-level detail (acceptance criteria,
     file paths, implementation guidance, test instructions, codebase recon)
     belongs in docs/stories/<RAIL>/<ID>.md — not here. -->
## Goal

<!-- State this phase's single purpose in one or two sentences (docs/architecture.md
     § Phase-authoring convention, INFRA-243). If the work naturally splits into more
     than one purpose, that's a signal to open a sibling phase, not to widen this one. -->
Make the release path's published provenance and its failure handling exactly true before the second release: deploy records commits, not tag objects; release.sh's partial-restamp recovery is tested; and its environment and push-target assumptions are stated or enforced.

**Parent phase:** Phase 14 (release job), complete at cp-14. This phase hardens what its first
release exposed. It does not change Phase 14's scope.

## Why this phase exists

The first attended release on 2026-10-01 published a provenance claim that names an
annotated tag object instead of a commit (CER-063). The Phase 14 reviews and audits also left
three small release-path gaps:
- the exit-11 partial-restamp recovery has no selftest case (CER-062);
- the header does not state which environment variables are inherited (CER-064);
- a split push URL makes every later run refuse (CER-061, item 4).

The next forqsite checkpoint already makes 5 claims stale, so the second release goes
through the review path. These gaps are cheapest to close before it. On 2026-10-01 the
operator chose to pull them forward as their own phase, ahead of Phase 15, rather than fold
them into Phase 15's coverage work. The phase is numbered `14-post1` so that every existing
"Phase 15" reference stays true.

## What this phase is not

- Not a release. The live sidecar keeps naming `60fd0cf` until the second release
  redeploys it, and nobody hand-edits production.
- Not Phase 15's claim-coverage work.
- Not CER-061 items (1) to (3) or CER-060. Both stay in Do Later.

## Story ordering

INFRA-022 and INFRA-023 touch different scripts. Their specs and first builds ran in
parallel, and the operator reviewed each spec before it was built.

**What happened (2026-10-01).** Both stories had a fable proving pass before review.
- **INFRA-022.** The proving pass returned PROVEN. Before the build, the operator widened the
  story so that each script resolves the ref once and reads everything through that sha. A
  ref that names no commit is refused. `make-provenance.sh --commit` was added so that the
  sidecar step does not resolve the ref a second time.
- **INFRA-023.** The proving pass found a HIGH (a configured `remote.origin.push` refspec
  redirected the release) and a MEDIUM (`GIT_CONFIG` hid a split pushurl). The spec was
  amended to use explicit `src:dst` refspecs and to unset `GIT_CONFIG`. That turned CER-064's
  "header sentence, no code change" into a code change. The operator then widened the story so
  that every printed recovery push is two-sided as well.
- **The INFRA-023 rebuild.** By then the first INFRA-023 build (`ce85268`) conflicted with
  main in the backlog, so it was discarded unmerged. The story was rebuilt fresh as `ce946fa`
  on main after INFRA-022 merged.

Both specs record their rulings and amendments.

**INFRA-024 was added at checkpoint (2026-10-01).** The CP-14-post1 security audit passed, but
it found a MEDIUM gap in this phase's own guarantee. The push named *where* the release goes
but not *what* it carries, because `refs/heads/main:refs/heads/main` pushes whatever `main`
points to at push time. The operator added INFRA-024 so the gap is fixed before the
checkpoint, and the checkpoint gates re-run after it merges.

## Stories

| ID | Title | Status |
|----|-------|--------|
| INFRA-022 | Deploy records the commit an annotated tag points to | complete |
| INFRA-023 | release.sh: test the partial-restamp recovery, state the environment, refuse a split push URL | complete |
| INFRA-024 | release.sh pushes exactly the commit and tag it deployed | planned |

## Schema delivery

For each new persistent schema object (table, collection, migration) introduced in
this phase, record the management surface before the phase is checkpointed.

| Object | Management surface | Exception |
|---|---|---|
| none | — | This phase adds no persistent object. |

---

### CP-14-post1 Cold-eyes checklist

- [x] written-never-read — none new. The sidecar's `repo_ref` is published for people, as
  before. The printed recovery pushes are read by the operator, and a selftest runs them
  verbatim.
- [x] required-never-written — none. Each script resolves its ref once, before that value is
  read. `deploy.sh` supplies `make-provenance.sh --commit`.
- [x] duplicate state — one instance, accepted. A direct caller of `make-provenance.sh` can
  supply `repo_ref` and `repo_commit` independently, with no cross-check (CER-065, by
  ruling). `deploy.sh` derives both from one resolution.
- [x] half-implementation — none unstated. The pushurl check deliberately does not cover
  `pushInsteadOf`, and the partial-write selftest SKIPs under root. Both are stated in the
  header and ruled. The live sidecar keeps naming the tag object `60fd0cf` until the second
  release redeploys it. That release's drift check should show the sidecar naming a commit.

Filled 2026-10-01 at checkpoint, from the intent and docs gates.
