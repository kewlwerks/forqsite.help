# Reconstruction Brief — forqsite.help

> This document is the sole input for an independent reconstruction agent.
> The agent must not have access to the original source code.
> It should produce an implementation that satisfies the ideology and constraints
> recorded here — free to diverge in all other respects.

---

## What you are building

Administrator documentation site for forqsite (self-hosted multi-tenant website builder), plus a dev-to-prod gap analysis doc

---

## Why it exists

forqsite.com is dogfooded as a tenant on a forqsite install; this docs site deliberately is NOT, so docs stay available when a forqsite instance is down

---

---

## Non-negotiable ideology

> These convictions and constraints must be expressed in any correct implementation.
> An implementation that contradicts them is not this project.

### Convictions



- We prefer zero-dependency static HTML over any framework, server, or build step, because when a forqsite instance is down its own dogfooded docs would be down too — and the docs exist precisely to help during that failure.

- We prefer fully self-contained, inlined HTML (fonts, styles, scripts embedded) over externally-linked assets, because "works offline, from `file://`, or behind any static file server" is a hard requirement, not a nice-to-have.

- We prefer treating `index.html` and `gap-handoff.html` as generated artifacts over hand-maintained source, because the source of truth is an external design session — hand edits made directly to the bundles get silently lost on the next re-export.

- --



### Constraints



#### Zero runtime dependencies

**Rule:** No server, no database, no build step, no external asset requests (fonts/CSS/JS must be inlined) in `index.html` or `gap-handoff.html`.

**Why this constraint exists:** This site exists specifically because every other forqsite property is dogfooded on a forqsite tenant. If this one had a runtime dependency of its own, it could fail at the exact moment it's needed.


#### Generated-artifact discipline

**Rule:** `index.html` and `gap-handoff.html` are not hand-edited. Changes are made in the source design session and re-exported.

**Why this constraint exists:** These are compiled, single-file bundles — treating them as editable source invites edits that vanish on the next sync.




---

## What must survive any implementation



- Zero runtime dependencies: no server, database, build step, or external asset fetch.

- Self-hosted independently of any forqsite tenant — this repo must not become a forqsite tenant itself, or it loses the reason it exists.

- Fully offline-capable: openable from `file://` with no network access.



---

## What you are free to change

> These are fingerprints of the original implementation, not constraints.
> You are encouraged to find better approaches.



- Specific HTML/CSS structure, visual theme, and inline JS implementation of `index.html`.

- Hosting mechanism (Caddy, GitHub Pages, nginx, `python3 -m http.server` are all explicitly interchangeable per the README).

- The exact format of the gap-handoff backlog, as long as it stays a single self-contained file with no runtime dependencies.

- --



---

## Comparison rubric

> After building, your implementation will be evaluated against the original on
> these dimensions. Optimise for them explicitly.


_(not yet specified — populate docs/ideology.md Comparison basis)_


---

## What you should question

> The original implementation made these choices under time or knowledge constraints.
> You are encouraged to find better solutions and justify them against the convictions above.



- `gap-handoff.html` mixes a live backlog of open GAP entries (a closed gap is removed from the page and its number is never reused) into the same generated-bundle format as the reference docs. As gap items get resolved upstream in `nullvalues/forqsite`, this file needs pruning — a static generated bundle is an awkward fit for something that should track live status; a future iteration might want a lighter-weight status marker instead of a full re-export per prune.



---

## Instructions for the reconstruction agent

1. Read this document in full before writing any code.
2. Build a working implementation that satisfies the ideology above.
3. For every non-negotiable constraint: explicitly state how your implementation satisfies it.
4. For every "should question" item: either improve on it or justify why you kept the
   original approach, citing the relevant conviction.
5. For every comparison dimension: document your approach and how it scores against the rubric.
6. Do not look at the original source code. If you have seen it, declare that before starting.
7. When done, produce a `RECONSTRUCTION.md` at your project root scoring your implementation
   against each comparison dimension.

*Generated from `docs/ideology.md` and `docs/brief.md` by `/flex:pairmode reconstruct`.*
*Original project: forqsite.help*
*Generated: 2026-07-13*
