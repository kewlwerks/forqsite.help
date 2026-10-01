# Ideology — forqsite.help

> This document captures the **intent layer** beneath the implementation.
> It records convictions, tradeoffs, and constraints in a form that survives across
> implementations, agents, and sessions.
>
> A reconstruction agent given only this document and `docs/brief.md` should be able to
> produce an implementation that is recognizably this project — different in form, identical
> in values.
>
> Fill this in before the first story if starting fresh. Fill it in by extracting from the
> existing implementation if a prototype already exists.

---

## Core convictions

> What does this project believe? State each conviction as a positive claim: "we prefer X over Y
> because Z." These are not rules — they are the values from which rules derive.
> A conviction should be strong enough to resolve a tradeoff when two good options conflict.

<!--
Examples:
- "We prefer explicit configuration over inferred defaults, because configuration that can be
  read is configuration that can be understood by the next agent."
- "We prefer correctness over performance at this stage, because an incorrect fast system
  cannot be trusted to optimize."
- "We prefer small composable functions over large orchestrators, because the unit of
  replaceability matters more than the unit of convenience."

Add one conviction per bullet. State the preference and the reason. Three to seven convictions
is the right range — fewer suggests the ideology is underdeveloped; more suggests it is not
actually a set of convictions but a list of preferences.
-->


- We prefer zero-dependency static HTML over any framework, server, or build step,
  because when a forqsite instance is down its own dogfooded docs would be down too —
  and the docs exist precisely to help during that failure.
- We prefer fully self-contained, inlined HTML (fonts, styles, scripts embedded) over
  externally-linked assets, because "works offline, from `file://`, or behind any static
  file server" is a hard requirement, not a nice-to-have.
- We prefer treating `index.html` and `gap-handoff.html` as generated artifacts over
  hand-maintained source, because the source of truth is an external design session —
  hand edits made directly to the bundles get silently lost on the next re-export.


---

## Value hierarchy

> When values conflict, which wins? Record the priority order and the reasoning.
> This section is most useful when populated from real conflict — a moment when two
> good values pointed in opposite directions and a decision was made.

<!--
Format each entry as:
  [Higher value] over [lower value] — [the situation where this matters] — [why]

Examples:
- "Auditability over convenience — when logging a decision requires extra code, write
  the extra code. A system that cannot explain itself cannot be trusted."
- "Backward compatibility over refactoring clarity — at this stage, existing integrations
  must not break. Clean-up is for a future phase when the API surface is stable."
- "Reversibility over speed — prefer designs where bad decisions can be undone. Move fast
  in a direction that can be walked back."
-->


- "Availability over freshness — the docs staying reachable during a forqsite outage
  matters more than being up-to-the-minute. A stale doc you can read beats a fresh one
  you can't."
- "Self-containment over convenience — the published pages need no build step to read and
  fetch nothing when opened, even though that makes hand-editing harder, because the whole
  point is that this site depends on nothing external to run. Tooling that checks, restamps
  or deploys the pages may run before publication; reading them never needs it."


---

## Accepted constraints

> Non-negotiables with their rationale. Not just the rule — the reason the rule exists
> and what it protects. A constraint without a rationale will be violated by the first
> agent that encounters a situation the rule author did not anticipate.

<!--
Format each entry as:

### [Constraint name]

**Rule:** [What must never happen, or what must always be true]

**Protects:** [What breaks, degrades, or becomes untrustworthy if this constraint is violated]

**Rationale:** [Why this protection is worth the cost it imposes]

**Override path:** [Under what conditions, if any, can this constraint be deliberately overridden?
  If never: say "no override permitted." If conditional: describe the gate.]
-->


### Zero runtime dependencies

**Rule:** No server, no database, no build step, no external asset requests
(fonts/CSS/JS must be inlined) in `index.html` or `gap-handoff.html`.

**Protects:** The ability to open the docs from `file://`, offline, or from any dumb
static file server — including while the forqsite instance the docs describe is down.

**Rationale:** This site exists specifically because every other forqsite property is
dogfooded on a forqsite tenant. If this one had a runtime dependency of its own, it
could fail at the exact moment it's needed.

**Override path:** No override permitted — this is the reason the repo exists.

### Generated-artifact discipline

**Rule:** `index.html` and `gap-handoff.html` are not hand-edited. Changes are made in
the source design session and re-exported.

**Protects:** Consistency between the source of truth and the published bundles;
prevents silent drift where a hand-edit is overwritten by the next re-export.

**Rationale:** These are compiled, single-file bundles — treating them as editable
source invites edits that vanish on the next sync.

**Override path:** A trivial, urgent fix (typo, broken link) may be hand-patched
directly if re-export isn't immediately available, but should be re-applied at the
source and reconciled on the next export.

**Phase 2 exception (recorded 2026-07-14):** Phase 2's CONTENT-001..004 and INFRA-001
stories hand-edit both bundles beyond the trivial-fix override — correcting drift
against the local forqsite clone, adding repo-grounded detail, UX fixes, and a prose pass.
This is accepted as satisfying the constraint's intent, not a bypass of it: every
edit is made through the reviewed pairmode build loop (builder implements against a
spec citing exact source evidence, reviewer independently re-verifies each claim,
the commit is traceable to the story spec), so the loop's audit trail substitutes for
a source-session re-export — the risk this rule protects against (silent,
unreviewed, untraceable hand-drift) does not apply here. No auto-sync tool exists
yet (see `docs/phases/phase-2.md` goal); when one is built, these edits should be
reconciled back into the source design session so the next re-export doesn't
regress them. Reviewers evaluating Phase 2 stories against this constraint should
treat loop-mediated, spec-cited, reviewed edits as compliant.

### Name the class, not the instance

**Rule:** Documentation must describe the architecture by its class — the constraint,
the topology, the reason — not by our particular deployment instance. No host name,
absolute path, or other deployment-specific identifier may appear in a live description
of the architecture. These identifiers belong only in findings that make them the subject
of an audit (e.g., a security finding quoting the instance as evidence), or in
verification records (e.g., a test noting "command run from the deployment host"),
never in the architecture itself.

**Protects:** A public repository becomes a permanent leak of internal infrastructure
once an instance name is committed. The same deployment identifier will appear in every
file carrying it, multiplying the exposure. Generalizing the language protects against
this while preserving the explanation (why the design is this way).

**Rationale:** This project's own documentation is public. An identifier that appears
once appears in git history forever, and a pickaxe search will find it in every commit.
Naming the instance is worse than not documenting it at all — it trades the chance that
a reader might infer the detail locally for the certainty that it will be searchable online.

**Override path:** A specific identifier may appear only where it is the subject of a
finding (e.g., "the host `[name]` leaks in three files") or a verification record (e.g.,
"verified from the deployment host"). Even then, this story's ruling narrowed the practice:
a finding can cite its subject by class ("the Docker host that runs the edge proxy") and a
verification record can do the same ("from the deployment host"), so naming the instance is
not required — only permitted. Prefer the class form when both are possible.

**Ruling — the public site's address:** The public site's address is a deployment-specific
identifier this rule covers, on the same footing as a host name or an absolute path. This
repository and its product ship as public sibling repos, and a downstream adopter rebrands
both — so the address names our instance, not the product, and a live description of the
architecture states it by class (e.g. "the public site," "the site's public address") rather
than in the identifier's own form.

### Cite the source that makes a claim checkable

**Rule:** A published claim about forqsite's behaviour carries its evidence — the
forqsite source `path:line` it was read from and the `repo@commit` it was checked at —
and that evidence is published as written. Citations are not stripped as internal
detail.

**Protects:** The reader's ability to verify a claim against their own installation
instead of trusting the page, and the site's own defence against silent drift (a
citation that no longer matches is a detectable failure; an uncited assertion is not).

**Rationale:** The audience self-hosts forqsite, so the cited tree is the reader's own
source tree, not a third party's internals. Recording the ruling is the point: the
question was raised at the Phase 8 security gate (CER-002) and will be raised again at
every gate unless the answer is written where a reviewer reads it.

**Override path:** A citation is dropped only when the claim it supports is removed.

This constraint governs the product's source tree, which the reader also has; "Name
the class, not the instance" governs our own deployment, and nothing here grants a
host name, an absolute path or a machine name of ours any publication right.

### Assert the invariant, not a proxy for it

**Rule:** A check must assert the invariant it claims, not a correlate that is
merely cheaper to compute; where the two diverge, a green check is wrong.

**Protects:** The meaning of a green gate — that "passing" reflects the claimed
condition itself, not a proxy a reader mistook for it.

**Rationale:** On 2026-09-21 the live site was found five days stale after
`cp-8` and `cp-9` both went green, because every gate compared the repository
to itself. CER-009, CER-011 and CER-012 record the same substitution elsewhere.

**Override path:** Only where the invariant is unobservable, and the check says so, as `drift-check.sh` does for `nginx.conf`.

### Spec-authoring convention for mechanical checks

This applies "Assert the invariant, not a proxy for it" to the checks a story spec writes
into its Ensures and Tests. Each entry names a proxy that has already produced a wrong
verdict here, and the invariant the check should assert instead.

**Soft-wrapped phrases (CER-011).** Defect: a line-oriented grep for a multi-word phrase in
prose fails when the phrase wraps across two source lines, so a cosmetic reflow reads as a
content regression. Assert instead: normalise whitespace before matching prose, or assert on
a structural anchor (a heading, a field label) rather than the wrapped sentence.

**Inert source counted as rendered (CER-012).** Defect: grepping a `--dump-dom` output
counts matches inside `<script>` template source as rendered nodes, which once reported
ledger rows as rendered when none were. Assert instead: strip `<script>` and `<style>`
blocks before asserting a render, or assert on a marker only the renderer emits. Hold every
other variable constant, so a comparison measures the one variable it names.

**Self-closing ranges (CER-017).** Defect: an `awk` range anchored on the same heading
pattern at both ends closes on its own start line, so a length assertion built on it can
never fail, and scanning to the next heading overshoots a last-in-section block. Assert
instead: bound the range on the block's own fields, or count those fields directly, and
state the method next to the number.


---

## Prototype fingerprints

> If this ideology document was written after a prototype already exists, record the patterns,
> habits, and choices in the prototype that reflect the developer's style rather than the
> project's values. A reconstruction agent should understand which patterns are free to change.
>
> If this document was written before any prototype: leave this section blank and fill it
> in during or after the first implementation.

<!--
The goal is to distinguish "this is how we believe the system should work" from "this is
how I happen to build things." A reconstruction agent that inherits only the fingerprints
without knowing they are fingerprints will treat them as constraints. Name them explicitly
so they can be questioned.

Format:

### [Pattern name]

**Observed in prototype:** [Where in the codebase this pattern appears]

**Why it exists:** [Developer preference? Convenience? Legacy? Genuine conviction?]

**Free to change?** Yes / Conditional / No — [reason]
-->


_(No prototype fingerprints recorded. If a prototype exists, review it for patterns that
reflect developer habit rather than project values and record them here.)_


---

## Reconstruction guidance

> Instructions for an agent reconstructing this system from ideology alone — without access
> to the original source code.

### Must preserve

> These elements are non-negotiable. An implementation that omits or contradicts them is
> not this project.


- Zero runtime dependencies: no server, database, build step, or external asset fetch.
- Self-hosted independently of any forqsite tenant — this repo must not become a
  forqsite tenant itself, or it loses the reason it exists.
- Fully offline-capable: openable from `file://` with no network access.


### Should question

> These elements are present in the current implementation but may not be the best approach.
> A reconstruction agent is encouraged to find a better solution — and should justify the
> change against the core convictions above.


- `gap-handoff.html` mixes a live backlog of open GAP entries (a closed gap is removed
  from the page and its number is never reused) into the same generated-bundle
  format as the reference docs. As gap items get resolved upstream in
  `nullvalues/forqsite`, this file needs pruning — a static generated bundle is an
  awkward fit for something that should track live status; a future iteration might
  want a lighter-weight status marker instead of a full re-export per prune.


### Free to change

> Implementation details the reconstruction agent should feel no obligation to preserve.
> These were choices, not values.


- Specific HTML/CSS structure, visual theme, and inline JS implementation of `index.html`.
- Hosting mechanism (Caddy, GitHub Pages, nginx, `python3 -m http.server` are all
  explicitly interchangeable per the README).
- The exact format of the gap-handoff backlog, as long as it stays a single
  self-contained file with no runtime dependencies.


---

## Comparison basis

> When two implementations are compared against this ideology, these are the dimensions that
> matter. Used by the comparison rubric to evaluate which implementation is better aligned
> with intent.

<!--
List three to five dimensions. Each should be a quality that can be assessed from reading
the code — not a feature checklist. Examples:
- "Constraint traceability: can a reader determine why a given protection exists?"
- "Intent legibility: does the code explain what it is protecting and why?"
- "Lesson integration: does the system make it easy to learn from failures?"
-->


- Zero-dependency compliance: does it still open from `file://` with no network calls?
- Self-containment: are fonts/styles/scripts fully inlined, with no external requests?
- Generated-artifact hygiene: is there a clear source-of-truth workflow, with no
  hand-drifted content diverging from it?
- Gap-backlog currency: are resolved GAP items pruned, and unresolved ones still accurate
  against `nullvalues/forqsite@main`?


---

*This document is a companion to `docs/brief.md` (what and why) and `docs/architecture.md`
(how). Together they form the complete ideology record for forqsite.help.*

*Last reviewed: _(not yet reviewed)_*
