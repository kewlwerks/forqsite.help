# forqsite.help Pairmode — Checkpoints

Each checkpoint is tagged after all stories in the phase pass the full checkpoint sequence
(build gate → security audit → intent review).
Before `checkpoint-tag`, run `scripts/drift-check.sh` by hand and record its exit code and result block in that phase's own checkpoint section below (see `docs/architecture.md` § Deployment for why this step is manual); a drift exit blocks the tag until a deploy corrects it and the check is re-run.

**Rollback.** To put back the files that were live before a deploy, find that deploy's stamp (the `stamp` line of its success block, or the `.bak-<stamp>` suffix of its backups), then, by hand:

1. Run `scripts/deploy.sh --rollback <stamp>`. It restores all three files from that stamp's backup set in place and sha256-verifies each, or refuses a missing or incomplete set (exit 6) without writing anything. Its own success block names a fresh stamp under which the files it replaced were backed up, so the rollback can itself be undone the same way.
2. Run `scripts/drift-check.sh` to confirm the bytes a request returns.

Never `mv` a backup over a live file: the bind mount follows the inode, so the container would keep serving the old one. Nothing rolls back automatically; `release.sh` never does.

---

## cp1-bootstrap-complete

**Phase:** 1 — Bootstrap pairmode methodology
**Tag command:** `git tag cp1-bootstrap-complete && git push origin cp1-bootstrap-complete`
**Acceptance:** Pairmode scaffolding is in place alongside the existing, working
`index.html` / `gap-handoff.html` docs bundle without disrupting it. No code stories
were required for this phase. Build gate: static HTML, no test failures possible with
zero code changes. Security audit: no CRITICAL/HIGH findings. Intent review: ALIGNED —
existing site content confirmed untouched.

---

## cp2-docs-refresh-complete

**Phase:** 2 — Refresh docs against forqsite drift
**Tag command:** `git tag cp2-docs-refresh-complete && git push origin cp2-docs-refresh-complete`
**Acceptance:** All 5 stories complete (CONTENT-001..004, INFRA-001) — consistency
fixes, repo-grounded embellishments, UX fixes (hash routing/scroll reset/responsive
layout/deep links/clipboard fallback), prose decluttering, and README's
generated-artifact framing revisited. Build gate: static HTML, both bundles render
clean (no error banners) in headless Chromium. Security audit: 0 CRITICAL/HIGH (2
informational findings, both pre-existing upstream flex infrastructure, out of this
project's diff). Intent review: 4/5 stories ALIGNED, CONTENT-004 PARTIAL (one named
GAP-006/GAP-011 reword line item not applied — logged as CER-001, Do Later, not
blocking). `docs/architecture.md` backfilled with bundle-format/module-structure/
protected-files content per intent-reviewer recommendation.

---

## cp-8

**Phase:** 8 — The promotion path, and what a pack may carry
**Tag command:** `git tag cp-8 && git push origin main --tags`

**Naming note:** the two tags above (`cp1-bootstrap-complete`, `cp2-docs-refresh-complete`)
predate the current `cp-<N>` convention. A `git tag -l 'cp-*'` glob does not match them —
use `git tag -l` unfiltered when asking what has been tagged. This project's Phase 9
audit initially recorded, wrongly, that no phase had ever been tagged for exactly that
reason.

**Phases 3-7 have no entry here and no tag.** From Phase 3 until Phase 8, the build-gate
guard shelled out `test_command`, which held a prose description rather than a runnable
command, and failed red (exit 127) on every checkpoint attempt. Those phases were marked
complete in `docs/phases/index.md` without ever passing a green gate. The operator
ruled, on 2026-09-21 (CONTENT-026), that they stay untagged: a `cp-<N>` tag asserts
the checkpoint sequence passed, and for these phases it did not — back-tagging would
record a gate result that was never obtained, making this file less trustworthy
rather than more. The work itself is not unverified, because later phases re-check it
regardless: the checkpoint gates run against the current tree, not a phase-scoped
diff (cp-8's dark-feature-scan failed on an artifact that predated Phase 8 — recorded
above in this same file), and Phase 10's CONTENT-024 re-read and corrected
`docs/phases/phase-4.md`. The gap from 3 to 7 in the `cp-*` series is therefore a deliberate state recorded here, not an oversight, and not an invitation to
backfill. CER-007 is closed against this record.

**Acceptance:** All 4 stories complete (CONTENT-016..019) — the three-stream promotion
model with a hand-authored inline SVG lane diagram, the ceiling on what a provider pack
may carry, expand-and-contract in the Day-two runbook, and GAP-012 recording the
content-migration gap. Every story passed review on its first attempt.

**Gates:** security PASS (0 CRITICAL/HIGH). intent ALIGNED — with one HIGH finding: the
new #promote page named `rolling-restart.sh` as the non-docker/systemd path's restart
command, contradicting the site's own Process supervision section and GAP-004. Neither
story reviewer could have caught it: CONTENT-018's spec barred that exact claim, and
CONTENT-016's — written first — did not. docs **FAIL on five documentation-currency
findings**, which blocked the tag. dark-feature-scan FAIL (orphaned `gate-worker.md`).

**Remediation:** Phase 9 (CONTENT-020..022) fixed the defect and the docs findings. The
docs gate was re-run against phase 8 and returned PASS; dark-feature-scan re-run PASS.
`cp-8` is the first tag under the `cp-<N>` convention.

---

## cp-9

**Phase:** 9 — Close CP-8: the defect the checklist missed, and the wiring that predates the convention
**Tag command:** `git tag cp-9 && git push origin main --tags`

**Acceptance:** All 3 stories complete (CONTENT-020..022). A remediation phase, parented
to Phase 8, created because CP-8's docs gate refused to tag. CONTENT-020 audited this
repo's pairmode wiring against flex 0.4.7 convention and recorded it in a standalone
wiring audit, since removed from this repository in Phase 10 (CONTENT-025) because its
subject is the build harness; CONTENT-021 corrected the `rolling-restart.sh` claim on
the Promoting a change page; CONTENT-022 brought `docs/architecture.md` and the era
ledger current. Every story passed review on its first attempt.

**Gates:** security PASS (0 CRITICAL/HIGH; three public-hygiene items filed as CER-002,
CER-003, CER-004). intent ALIGNED, with two LOW advisory findings — this file was stale,
and the wiring audit had no staleness trigger; both were fixed as checkpoint remediation
before the docs gate ran. docs **FAIL, then PASS on re-run**. dark-feature-scan PASS.

**The docs FAIL is worth reading.** `architecture.md` named Phase 7 as most recently
complete after `cp-8` had flipped Phase 8 to complete. The cause was structural, not
textual: `flex_build.py`'s checkpoint-tag step maintains a machine-owned `Current phase:`
line anchored to a hand-maintained `Current era:` line, and this project's
`architecture.md` had never carried that anchor — so every tag emitted `warning: ... no
'Current era:' anchor line — skipping phase pointer stamp` and the pointer was never
auto-maintained. Correcting the wording alone would have gone stale again at the next
tag. The anchor was added instead, and the pointer now self-updates.

**Lesson recorded:** documentation findings raised by a checkpoint gate are checkpoint
remediation — fix them, re-run the gate, re-record. Phase 9 itself was shaped as a full
phase, which the intent gate judged proportionate given CONTENT-020's independent audit
scope, but the two blocking docs findings alone did not warrant it.

---

## cp-10

*Written after the fact, on 2026-09-25 (CONTENT-036), from the `cp-10` tag and the
phase-10 record, because this section was missed at tag time (CER-032). It states only
what those two sources record.*

**Phase:** 10 — Name the class, not the instance — and close the backlog by resolving, never deleting
**Tag command:** `git tag cp-10` — a lightweight tag on `f4e4e5c` ("chore(cp-10): mark
phase 10 complete and stamp the phase pointer"), 2026-09-21. The push command is not
recorded.

**Acceptance:** All 5 stories complete (CONTENT-023..027), per the phase-10 Stories
table. CONTENT-023 brought the backlog's resolution-marker convention current;
CONTENT-024 recorded name-the-class-not-the-instance as an accepted constraint and
generalised our infrastructure identifiers out of the four files that carried them;
CONTENT-025 moved the build-tooling audit out of this repository and referred the flex
defect; CONTENT-026 recorded the publication policy and the phases 3-7 ruling;
CONTENT-027 closed CER-001 as superseded and corrected CER-005's evidence.

**Gates:** filled in at CP-10, 2026-09-21. security PASS, intent ALIGNED, docs PASS
after one remediation (`15967e2`, which recorded the mid-row redaction exception so the
checklist could be answered honestly), dark-feature scan 0 findings. No drift check is
recorded for this checkpoint.

**The phase's most important result, as recorded:** the air-gap finding (CER-005) was not
closed. Re-running the reproduction disproved half the phase's own premise: origin
independence held, but "nine rows rendered" was a grep counting an inert template literal.
CER-005 stayed open with corrected evidence. Six findings were filed during the phase
(CER-008..013).

**Carried forward:** CER-009, CER-011 and CER-012 were recorded as three instances of one
pattern, asserting on a cheap proxy instead of the invariant, and left for the next
phase's framing.

---

## cp-11

**Phase:** 11 — Make the deploy repeatable, and make drift visible
**Tag command:** `git tag cp-11 && git push origin main --tags`

**Acceptance:** All 11 stories complete: INFRA-006..014, CONTENT-028 and CONTENT-029. The
phase grew twice. The CP-11 security gate's first run added INFRA-009 and CONTENT-029. The
`cer-do-now` guard then refused the checkpoint, and the operator pulled in all eight
remaining audit findings as round 2 (INFRA-010..014). Three stories needed a second
attempt: CONTENT-029, INFRA-012 and INFRA-013. Each first attempt failed on a real defect,
and each fix went into the spec before the retry.

**Gates:** the first security and docs verdicts were stale once remediation changed both
scripts, so both were re-run against the tree after INFRA-014. security PASS (opus; CER-019
to CER-028 confirmed closed in code; four LOW findings filed as CER-033 to CER-036). docs
PASS. intent ALIGNED. dark-feature-scan PASS.

**Drift check: run after the tag, not before it.** The step this file's header requires was
skipped: `cp-11` was tagged on 2026-09-22 without it, because the build host had no deploy
configuration. That is the same gap this phase exists to close. The check was run on
2026-09-23, once the configuration existed. First run, exit 0:

```
index.html          ok  5890637970f251fbfcf460241a208fdd7d927635aba992e80f6161737f88ed05
gap-handoff.html    ok  d774cb39effc7d5f4d02d39ae4fec621c3d3662fb1fef01c4e8a0f6203faffc6
provenance         absent or unreadable — the bundle result above does not depend on it
result             ok — served bytes match the ref for all 2 bundles
```

The bundles were current, but the provenance sidecar had never been served. `deploy.sh` had
never run against production; the last deploy was the manual one recorded in
`docs/architecture.md`. The container also had no bind mount for the sidecar. Fixed in the
bootstrap order `deploy.sh`'s header requires: `deploy.sh` published `21e6e2a` (all three
files verified on the far side), the sidecar mount was added to the compose file, and the
container was recreated. Re-run, exit 0:

```
ref                21e6e2acbad54dfb2aabe4d49e104e86c8eb75e8  21e6e2a
index.html          ok  5890637970f251fbfcf460241a208fdd7d927635aba992e80f6161737f88ed05
gap-handoff.html    ok  d774cb39effc7d5f4d02d39ae4fec621c3d3662fb1fef01c4e8a0f6203faffc6
provenance         claims 21e6e2a deployed 2026-09-23T02:31:14Z  (claim, not the basis of the result above)
result             ok — served bytes match the ref for all 2 bundles
```

**Lesson recorded:** the drift check is not optional when the checking host lacks the
configuration. A missing configuration is a reason to stop and ask, never a reason to
skip the step. Tagging without the check reproduced, in small, the proxy substitution this
phase names: "the gates are green" stood in for "the site is what we committed."

---

## cp-12

**Phase:** 12 — One stamp per release: re-verify every published claim against one forqsite commit
**Tag command:** `git tag cp-12 && git push origin main --tags`

**Release commit:** `nullvalues/forqsite@1fda3228322d5ad779f44c321c4013ccd247b3fa`,
committed 2026-09-24. Both pages now carry this one commit in every stamp.

**Acceptance:** all 8 stories are complete: CONTENT-030 to CONTENT-037. The phase grew
twice.
- **Planned (CONTENT-030 to 032).** CONTENT-030 built the claims manifest, and CONTENT-031
  and 032 re-verified and restamped every stamped claim. CONTENT-030 failed review twice,
  on evidence the builder described rather than located. A loop-breaker traced both
  failures to the spec. After the spec was amended to require verbatim `git grep -F` hits
  at the release commit, the story passed on its third attempt.
- **First growth (CONTENT-033).** The `cer-do-now` guard refused the checkpoint on
  CER-038, a published restore command missing an argument that forqsite now requires. The
  operator added CONTENT-033, which folded in two more corrections to text no stamp covers
  (CER-039, CER-040).
- **Second growth (CONTENT-034 to 037).** The first security gate's advisories went through
  a cold cross-corpus triage and two independent designs. That gave CONTENT-034 (backup,
  cron and restore blocks now run under forqsite's own `dotenv` loader), CONTENT-035
  (GAP-013 and GAP-014 for upstream defects), and CONTENT-036 (the cp-10 record, CER-005
  closed as a wrong-route artifact, the spec-authoring convention in `docs/ideology.md`,
  and backlog grooming). The security re-run then found operator-local absolute paths in
  tracked docs, which CONTENT-037 scrubbed.

CONTENT-032, 035 and 036 each reached the builder with a defect in their own Tests block,
two of them whole-line scans over pre-existing text. Each defect was fixed in the story's
spec before review.

**Gates:** re-run against the final tree, because CONTENT-034 to 036 changed published
commands after the first verdicts.
- security PASS (opus). Two LOW advisories were filed as CER-051 and as a note on CER-049,
  and the path leak was fixed by CONTENT-037.
- docs PASS.
- intent ALIGNED.
- dark-feature-scan PASS.

**Drift check, before the tag.** Main at `cdce820` was deployed on 2026-09-25.
CONTENT-037 changed docs only; the page bytes at the tag commit are identical to
`cdce820`. The check was run at the tag candidate, exit 0:

```
ref                656c7f4545bd8e2df60c013ca21c9caee95100e6  656c7f4 "chore(merge-status): sync story/phase status after merge"
index.html          ok  6e23ac136b2691b3331e8f849a1ded0fa07643e12beb916ae3202be8fa82f335
gap-handoff.html    ok  f1e7917060c12993138816192da576e75c1a97f7539a9e8307dba7d1849fea4f
nginx.conf          not served — bind-mounted only; no request returns its bytes, so this check cannot cover it
provenance         claims cdce820 deployed 2026-09-25T16:13:41Z  (claim, not the basis of the result above)
result             ok — served bytes match the ref for all 2 bundles
```

**Lesson recorded:** every content finding this phase surfaced late sat in text that no
stamp covers, and each was found incidentally, never by the re-verification. The
manifest's scope defines what the phase can see. CER-046 carries that into Phase 13.

---

## cp-13

**Phase:** 13 — Release-time reconciliation: revise the brief, then check claims against a new forqsite commit
**Tag command:** `git tag cp-13 && git push origin main --tags`

**Acceptance:** all 3 stories are complete.
- **CONTENT-038.** The brief now puts release-time reconciliation in scope and scopes "no
  build step" to the published artifact, and carries a dated ruling note. The same ruling
  is in `docs/ideology.md` and `README.md` § Updating. A load-time check with a negative
  control showed that neither page makes a network request from `file://`.
- **INFRA-015.** `docs/architecture.md` § Claims manifest schema is now the one field
  reference, which closes CER-045's documentation half.
- **INFRA-016.** `scripts/stale-claims.py`, with a 47-case fixture selftest. The
  selftests became the Build standards `test_command`, closing CER-045.

The operator made these decisions on 2026-09-29:
- approved the CONTENT-038 wording;
- deferred CER-046 to Phase 14;
- placed the schema in `architecture.md`;
- accepted INFRA-016's four decisions (restamp semantics, closed-record reopening, no
  `--json`, `unverified` exits 0).

As in Phase 12, a Tests block reached its builder with a whole-line scan over pre-existing
text: INFRA-016's hygiene grep matched a cache path already on the Build standards line it
edits. The spec was corrected to a word diff before review.

**Smoke run.** Target: the newest forqsite checkpoint tag, 66 commits past the release
commit. Exit 3. Results: 38 claims, of which 22 untouched, 14 hold and 2 stale; 0 unverified;
0 closed records. Both stale claims are the GAP-006 evidence line in `scripts/firstrun.sh`,
cited by the GAP-006 claim and the Known-gaps claim. That evidence was rewritten upstream,
so GAP-006 may have closed. Phase 14 reviews it; nothing was restamped here.

**Gates:**
- security PASS (opus), four LOW findings. CER-053 to CER-055 were filed. The fourth is
  the test command also living in the untracked pairmode context file, which is tooling
  state and is recorded in the CP-13 checklist.
- intent ALIGNED.
- docs FAIL, then PASS after remediation `bfbf219`. That commit made CLAUDE.md's test block
  run the selftests and updated the phase doc's resume state. A LOW overclaim about exit
  codes was then narrowed in `1560daf`.
- dark-feature-scan PASS.

**Drift check, before the tag.** The pages are byte-identical to cp-12. The check was run
at the tag candidate, exit 0:

```
ref                1560dafe9db983470e0fc4157caa3342b9706196  1560daf "docs(architecture): selftest covers every exit code except 5 (CER-052) — docs-gate LOW"
index.html          ok  6e23ac136b2691b3331e8f849a1ded0fa07643e12beb916ae3202be8fa82f335
gap-handoff.html    ok  f1e7917060c12993138816192da576e75c1a97f7539a9e8307dba7d1849fea4f
nginx.conf          not served — bind-mounted only; no request returns its bytes, so this check cannot cover it
provenance         claims cdce820 deployed 2026-09-25T16:13:41Z  (claim, not the basis of the result above)
result             ok — served bytes match the ref for all 2 bundles
```

---

_(Add a checkpoint section for each phase. Tag only after full checkpoint sequence passes.)_
