# forqsite.help — Architecture

## What forqsite.help is

Two static HTML bundles — `index.html` (the main docs site) and `gap-handoff.html`
(the gap/handoff tracker) — plus `README.md`. Content authoring has no build step (the
bundles are hand/session-generated, not compiled); the files can still be opened
directly (`file://`) for local editing/preview. The deployed artifact, however, runs
behind a minimal `nginx:alpine` container (see Deployment below) — per FORQSITEHELP-001
in the sibling `caddy` repo, edge Caddy only ever does `reverse_proxy`, never a direct
file-system mount into the shared ingress container, so this project containerizes
rather than relying on Caddy's `file_server`. No database, regardless.

This document is the source of truth for the forqsite.help codebase. Read it before any task.

---

## Stack

static HTML content (no build step for the content itself); deployed behind
`nginx:alpine` (bind-mounted static files + config, no Dockerfile, no build step for
the deployment either); no database

---

## Domain model



---

## Era and phase currency

Current era: `001` — `docs/eras/001-initial.md`
Current phase: 13 — Release-time reconciliation: revise the brief, then check claims against a new forqsite commit

`docs/phases/index.md` is the source of truth for phase status. The two lines above
and below are pointers into that record, not a second copy of it.

**The `Current era:` line above is a hand-maintained anchor, and the `Current phase:`
line below it is machine-owned.** `flex_build.py`'s checkpoint-tag step rewrites the
`Current phase:` line in place on every tag, keyed off that anchor. Do not reformat
either line or the pointer silently stops updating: this section previously carried
the phase in prose, the anchor did not match, `record-checkpoint-step` emitted
`warning: docs/architecture.md has no 'Current era:' anchor line — skipping phase
pointer stamp`, and the pointer went stale the moment cp-8 was tagged.

This repo's build-harness wiring was audited against convention in Phase 9. The audit
itself is not kept here — its subject is the build harness rather than forqsite — and
was removed in Phase 10 (CONTENT-025). The one outcome that is about this repository:
`.claude/agents/gate-worker.md` was removed as a dark feature — the dispatch that would
reach it was retired upstream — and must not be restored by a future scaffold sync.

---

## Module structure

```
forqsite.help/
├── index.html          # main docs site (self-unpacking bundle)
├── gap-handoff.html    # gap/handoff tracker (self-unpacking bundle)
├── docker-compose.yml  # nginx:alpine container, bind-mounts the two files above
├── nginx.conf          # listens on :6000 (matches caddy's port-registry.md assignment)
├── scripts/
│   ├── bundle-template.py  # canonical bundle-edit tool (extract|inject|verify) — see Editing procedure below
│   ├── stale-claims.py     # release-time stale-claim checker (reports, never edits) — see Stale-claim checker below
│   └── stale-claims-selftest.sh  # fixture selftest for stale-claims.py
├── docs/
│   └── claims-manifest.json  # every stamped claim both pages make about forqsite, and where its evidence lives
└── README.md
```

## Deployment

INFRA-002 (phase 4) containerized this project: `docker-compose.yml` runs
`nginx:alpine` as container `forqsite-help`, joined to the external `edge` Docker
network, with `nginx.conf`, `index.html`, and `gap-handoff.html` bind-mounted
read-only — no Dockerfile, no image build. No host ports are published; the sibling
`caddy` repo's `sites/forqsite-help.caddy` reverse-proxies the public site's address to
`forqsite-help:6000` over that shared network. Deployed alongside caddy on the Docker
host that runs the edge proxy at a per-site directory under that host's service root,
mirroring the proxy's own deploy convention — required since Docker's embedded DNS
resolution for the `edge` network only works within a single Docker host.

Both HTML files are self-unpacking bundles: a `<script type="__bundler/template">`
tag contains a JSON-encoded HTML string. The unpacked HTML embeds a `DCLogic` class
holding app state, `nav()`/hash-routing logic, and render helpers (`scrollToAnchor`,
`copyCmd`, etc.).

**Editing procedure**: edit through `scripts/bundle-template.py`, never by hand-splicing
the `__bundler/template` JSON string. The script defines three subcommands, invoked as
`python3 scripts/bundle-template.py <subcommand> …`:

- `bundle-template.py extract <bundle.html> <out.template.html>` — pulls the decoded
  template out of the bundle into a plain HTML/JS file.
- `bundle-template.py inject <bundle.html> <in.template.html>` — re-encodes that file
  and splices it back into the bundle's `<script type="__bundler/template">` element.
- `bundle-template.py verify <bundle.html>` — re-encodes the template already in the
  bundle and asserts the result is byte-identical to what's there.

Workflow, as all four Phase 8 stories used it: run `verify` before editing, to confirm
the script's encoder still matches the bundler's; `extract` once to a scratch file;
make every edit in the unpacked template as plain markup/`DCLogic` script; `inject`
once; `verify` again.

Hand-splicing is wrong, not merely discouraged, because the encoder escapes every `/`
as `\u002F`, and the template contains its own `</script>` sequences that would
terminate the carrying script element if left unescaped — a manual re-encode that gets
either detail wrong corrupts the bundle with no useful error at load. (The historical
pre-script example in `docs/stories/CONTENT/CONTENT-001.md`'s Requires section predates
this tooling; it is not current guidance.)

The requirements the script doesn't cover are unchanged: `node --check` on any edited
script, and — where the change is interactive/CSS behavior — a headless-browser render
(e.g. Chromium `--dump-dom`), because a text diff can't confirm runtime behavior like
scroll reset or hash routing. The JSON round-trip check is now performed by `verify`
itself.

**Claims manifest.** `docs/claims-manifest.json` lists every forqsite stamp in both pages,
every claim each stamp covers, and where in the forqsite repository each claim's evidence
lives, against one pinned release commit. The stories that re-verify or restamp a claim
update it in the same change. Its field vocabulary is defined in § Claims manifest schema.

**Stale-claim checker** (INFRA-016, Phase 13). `scripts/stale-claims.py` compares the
manifest's claims and closed records at a target forqsite commit against the release
commit: it re-applies every recorded check (evidence present, absent literal or path still
absent, directory count unchanged) at the target, and lists the claims that went stale and
the closed gaps that reopened. It reads a local forqsite clone named by the
`FORQSITE_CLONE` environment variable, using read-only git subcommands only, and fetches
nothing. It writes nothing: not the manifest, not the pages, not the clone; rewriting a
stale claim is a reviewed story. Its symbol matching normalises whitespace on purpose
(CER-011), so a reindent or reflow does not fail a claim whose meaning is unchanged and an
absent literal cannot hide behind a line break. It reads no page, so the inert-script
rendering concern of CER-012 does not arise. It runs git with every inherited `GIT_*`
variable removed and with external diff and textconv disabled (CER-054). It sets
`GIT_NO_LAZY_FETCH=1`, so on git 2.44 and later a partial clone cannot fetch a missing
object on demand; older git ignores the variable. `--no-commits` omits everything the
report takes from forqsite's history rather than from the manifest, so that report can be
quoted in a tracked file; the full report is never committed. Its usage, verdicts and exit
codes live in its own header docstring, per the exit-code contract below;
`scripts/stale-claims-selftest.sh` exercises each verdict and every exit code against a
fixture repository.

**Deploy, drift-check and provenance scripts** (INFRA-006, INFRA-007, INFRA-008, Phase 11).
Three scripts, each documented in full in its own header comment — this section points at
those tables rather than restating them:

- `scripts/deploy.sh` — copies the two published bundles to the configured per-site
  directory over the configured ssh alias, backing up each live file on the remote side to
  `<name>.bak-<UTC stamp>` (both bundles sharing one stamp) before overwriting it in place.
  "In place" is required, not stylistic: the remote bind mount follows the file's inode, so
  a rename-over would leave the container serving an old, unlinked inode while the deploy
  reported success. After both bundles are copied and hash-verified, `deploy.sh` generates
  the provenance sidecar (below) and deploys it the same way. Retention is bounded: once
  every file of a deploy has verified, that deploy's backup set is marked verified and
  verified sets beyond a stated count (a constant in the script's header) are pruned, while
  the set just made and any set without a verified marker — such as the backup set a
  failed deploy leaves, or one a rollback makes — are always kept. The script assumes the remote directory is writable only
  by the deploy account: its unpredictable staging names and noclobber backups narrow a
  co-tenant's symlink race there, but do not make a shared directory safe. On any ssh or
  remote-command failure it prints a fixed reason class (e.g. "the connection was
  refused"), never ssh's own diagnostic text or the remote shell's, because that text
  names the configured target (CER-028, INFRA-014). `deploy.sh --rollback <stamp>`
  restores the three files that were live just before the deploy that made `<stamp>` (both
  bundles, then the sidecar) from that deploy's `.bak-<stamp>` set, overwriting each in
  place through the same copy path and re-verifying each by sha256 on the far side, and
  refuses (exit `6`, nothing written) a set that is missing or incomplete (CER-031,
  INFRA-018); the operator runs it by hand, never `release.sh`.
- `scripts/drift-check.sh` — the served-bytes half of the same invariant. It fetches each
  bundle over HTTP from the configured site and hashes the response bytes, then hashes
  `git show <ref>:<bundle>`, and compares the two sha256 values — never the file sitting in
  the remote directory, which is exactly the proxy a stale bind-mounted inode would pass.
  `nginx.conf` is also bind-mounted but is never served over HTTP (it only configures
  `listen`/`server_name`/`root`), so this check is undefined for it and says so in its
  report rather than silently skipping it.
- `scripts/make-provenance.sh` — a pure function of `(repo, ref)` that prints the
  provenance sidecar's JSON to stdout; it reads no configuration and contacts no host.

**Configuration surface.** All three scripts read their settings from the environment,
falling back to a gitignored `scripts/deploy.env`. That file is never committed; a
committed `scripts/deploy.env.example` template (all lines commented) is the starting
point for creating it. The variable names: `FORQSITE_HELP_DEPLOY_HOST` (deploy.sh, ssh
alias), `FORQSITE_HELP_DEPLOY_DIR` (deploy.sh, remote per-site directory) and
`FORQSITE_HELP_SITE_URL` (drift-check.sh, base URL to fetch served bytes from). The file
is parsed as `KEY=value` data for those known keys by one shared reader loaded from the
scripts' own directory, never executed, so its values stay literal text, and any other
line is refused by line number without printing its content (CER-024). The environment
wins: the file fills only keys the environment leaves unset, and never overrides a key the
environment sets (CER-035).

**The provenance sidecar** (`site-provenance.json`, INFRA-008). `make-provenance.sh`
generates it and `deploy.sh` writes it last, deliberately: it is deployed only after both
bundles have landed and hash-verified, because it asserts "this commit is deployed" and
writing it earlier would publish that claim before it was true. `docker-compose.yml`
bind-mounts it alongside the two bundles; that mount is a one-time addition requiring a
container recreate to take effect, and must be added only after the file already exists on
the remote side (see `deploy.sh`'s header for the bootstrap order), or Docker creates a
directory at that path instead of bind-mounting a file. `drift-check.sh` fetches it and
reports its claimed per-bundle sha256 values as a labelled claim alongside the real
served-vs-committed comparison — it can only ever add a failure (a contradiction between
its claim and the served bytes) and never supply or suppress a match; trusting it as the
basis of the drift decision would be the same proxy substitution the served-bytes check
exists to refuse.

**Exit-code contract.** Each script's own header comment carries its exit-code table —
restating those tables here would make this doc a second writer of a fact each script
already owns, and the numbers would drift the first time one is added. At class level, the
contract all three share: `0` means the invariant the script asserts held; every distinct
failure mode gets its own code; and a usage error never shares a code with a condition of
substance (since INFRA-017, `deploy.sh` holds this too: bad usage exits `64`, as it
already did in `drift-check.sh` and `make-provenance.sh`).

**Verification record — 2026-09-21.** By hand, before this phase's scripts existed: the
deployment host was found serving `index.html` as committed at `5ec8194` and
`gap-handoff.html` as committed at `813ce27` (both Phase 7, 2026-09-16), while the
repository stood at Phase 9 — six commits touching the two bundles, one of them a factual
correction, had not reached readers. Both live bundles were backed up under a shared
timestamp and copied; each file's sha256 was verified on the remote side and again locally;
both pages were then fetched over the reverse proxy, returning `200` with bodies hashing
equal to the repository's. This incident is what CER-014 and INFRA-006/007/008 exist to
prevent a gate from missing again.

---

## Claims manifest schema

This section is the authoritative definition of `docs/claims-manifest.json`. The CONTENT-030
to CONTENT-032 and CONTENT-035 to CONTENT-037 specs are its history, and where they disagree
this section says so below. It supersedes CONTENT-030 Instructions 7 ("Do not describe its
schema there, because the file already shows it"), because that premise no longer holds: the
file cannot show a field or value it has never contained (`closed`, `marker`, `unverified`,
`UNVERIFIED:`), and it no longer contains `MISMATCH:`. Status is measured against the
manifest's git history: `in use` occurs in the live manifest, `retired` is absent now but
occurs in an earlier committed version, and `unexercised` has never been held by any
committed version.

### Fields

| Field | Type | Status | Source | Meaning |
| --- | --- | --- | --- | --- |
| `release` | object | in use | CONTENT-030 | The one release commit every claim is verified against. `phase-12.md` § Release commit mirrors it, and the manifest is the authoritative copy. |
| `release.repo` | string | in use | CONTENT-030 | The slug of the repository the claims are about. |
| `release.commit` | string | in use | CONTENT-030 | The full 40-hex sha, taken as the tip of forqsite's `origin/main` when the release was pinned. |
| `release.committed` | string | in use | CONTENT-030 | The date of that commit. |
| `release.pinned` | string | in use | CONTENT-030 | The date the release was pinned. |
| `stamps` | array | in use | CONTENT-030 | One record per stamp occurrence in the template. Every stamp is cited by at least one claim. |
| `stamps[].id` | string | in use | CONTENT-030 | The stamp id, `S-NN`. |
| `stamps[].page` | string | in use | CONTENT-030 | The page the stamp is on, `index.html` or `gap-handoff.html`. |
| `stamps[].location` | string | in use | CONTENT-030 | Where on the page the stamp sits. |
| `stamps[].text` | string | in use | CONTENT-030, CONTENT-032, CONTENT-035 | The exact substring of the page's `bundle-template.py extract` output that contains `nullvalues/forqsite@<hex>`. It is not taken from the bundle or the rendered DOM, and it may be markup or script source (S-01 contains `<br>`, and S-06 is a JS array literal). |
| `stamps[].commit` | string | in use | CONTENT-030, CONTENT-032 | The sha as printed in the stamp. Since CONTENT-032 every stamp commit equals `release.commit[:8]`. |
| `stamps[].date` | string | in use | CONTENT-030 | The stamp's date in ISO form, while `text` carries the date in the stamp's own format. |
| `stamps[].scope` | string | in use | CONTENT-030 | The coverage reading of the stamp, following the footer, inline and table-row rules of CONTENT-030 Instructions 4. |
| `claims` | array | in use | CONTENT-030 | One record per claim the pages make about forqsite. |
| `claims[].id` | string | in use | CONTENT-030 | The claim id, `C-NNN`. Ids are never reused. |
| `claims[].page` | string | in use | CONTENT-030 | The page the claim is on. |
| `claims[].location` | string | in use | CONTENT-030 | Where on the page the claim sits. |
| `claims[].claim` | string | in use | CONTENT-030 | The claim in words. |
| `claims[].quote` | string | in use | CONTENT-030, CONTENT-031 | A verbatim substring of the extracted template. |
| `claims[].evidence` | array | in use | CONTENT-030 | The repo evidence for the claim. The Known-gaps claim carries the deduplicated union of the evidence of every claim that cites its stamp. |
| `claims[].evidence[].path` | string | in use | CONTENT-030 | A repo-relative path in forqsite. |
| `claims[].evidence[].symbol` | string | in use | CONTENT-030, CONTENT-031 | A single-line literal that `git grep -F` finds in that path at `release.commit`. |
| `claims[].stamp` | string | in use | CONTENT-030 | The `S-` id of the stamp covering the claim. The commit and date live only on the stamp. |
| `claims[].result` | string | in use | CONTENT-031, CONTENT-032, CONTENT-035 | The outcome of the re-verification at `release.commit` that produced the claim's current stamp, judged against the page as it stood before it. See Values. The Known-gaps claim has none, by design. |
| `claims[].note` | string | in use | CONTENT-030, CONTENT-031, CONTENT-032, CONTENT-035 | Free text that never names a claim id. It carries a prefix when the result needs explaining. See Values. |
| `claims[].marker` | string | unexercised | CONTENT-032, CONTENT-036 | For an `unverified` claim, an on-page phrase that contains "not verified" and is new to the page. No committed manifest has held one. |
| `claims[].absent` | array | in use | CONTENT-031 | Literals the claim says are missing from forqsite. |
| `claims[].absent[].path` | string | in use | CONTENT-031 | A path checked at the release commit. With no `symbol`, the path does not exist there. |
| `claims[].absent[].symbol` | string | in use | CONTENT-031 | The path exists at the release commit and this literal is not found in it. |
| `claims[].counts` | array | in use | CONTENT-032 | Directory counts the claim's quote states. |
| `claims[].counts[].path` | string | in use | CONTENT-032 | The directory counted, one level. |
| `claims[].counts[].suffix` | string | in use | CONTENT-032 | The name suffix counted. |
| `claims[].counts[].n` | number | in use | CONTENT-032 | The number of names in `git ls-tree --name-only <release> <path>/` that end in `suffix`. `n` also appears in the quote. |
| `claims[].closed_by` | object | in use | CONTENT-031, CONTENT-036 | Appears on a live claim that is only partly closed. |
| `claims[].closed_by.commit` | string | in use | CONTENT-031 | A full sha, an ancestor of `release.commit` and not an ancestor of the old stamp's commit. |
| `claims[].closed_by.path` | string | in use | CONTENT-031 | A path the `closed_by` commit touches. |
| `closed` | array | unexercised | CONTENT-031, CONTENT-036 | A closed gap's claims move out of `claims` into this array, and the gap is removed from both pages. No manifest has used it yet. |
| `closed[].id` | string | unexercised | CONTENT-031 | The claim id. |
| `closed[].gap` | string | unexercised | CONTENT-031 | The gap that was closed. |
| `closed[].claim` | string | unexercised | CONTENT-031 | The claim in words. |
| `closed[].closed_by` | object | unexercised | CONTENT-031 | The commit that closed the gap, as `{commit, path}`. |
| `closed[].closed_by.commit` | string | unexercised | CONTENT-031 | The closing commit, a full sha. |
| `closed[].closed_by.path` | string | unexercised | CONTENT-031 | A path the closing commit touches. |
| `closed[].evidence` | array | unexercised | CONTENT-031 | The claim's evidence, as for `claims[].evidence`. |

### Values

| Field | Value | Status | Source | Meaning |
| --- | --- | --- | --- | --- |
| `claims[].result` | `open` | in use | CONTENT-031, CONTENT-032 | The quote is unchanged. |
| `claims[].result` | `changed` | in use | CONTENT-031, CONTENT-032 | The quote is new, and the note starts `CHANGED:` and gives the old and new wording. A claim that had a `MISMATCH:` note became `changed`. |
| `claims[].result` | `added` | in use | CONTENT-031, CONTENT-035 | A new GAP entry. The quote is new, the claim has a new `C-` id and the footer stamp, and the note starts `ADDED:` and gives the verification date. |
| `claims[].result` | `unverified` | unexercised | CONTENT-032, CONTENT-036 | The note starts `UNVERIFIED:` and gives the reason. `marker` holds an on-page phrase that contains "not verified" and is new to the page. The stamp still names the release commit. |
| `claims[].note` | `CHANGED:` | in use | CONTENT-031, CONTENT-032 | Gives the old and new wording of a changed quote. |
| `claims[].note` | `ADDED:` | in use | CONTENT-035 | Gives the verification date of a new GAP entry. |
| `claims[].note` | `UNVERIFIED:` | unexercised | CONTENT-032 | Gives the reason a claim could not be verified. |
| `claims[].note` | `MISMATCH:` | retired | CONTENT-030, CONTENT-031, CONTENT-032 | The page's implied literal is absent at the release commit, and the claim cites what the file does contain. CONTENT-031 and CONTENT-032 resolved every one. |

The Known-gaps claim (CONTENT-030, CONTENT-031) is the one `index.html` claim whose note
names a `gap-handoff.html` stamp id. It has no `result`, by design.

### Restamps and closed records

Both rules were ruled by the operator on 2026-09-29 in INFRA-016's spec.

- **What `result` means after a restamp.** `result` always describes the most recent
  restamp. When a later forqsite commit is pinned as `release.commit`, every claim's
  `result` is derived again, against the pages as they stood at the previous release: a
  claim whose quote is unchanged is `open`, a claim whose quote was rewritten is `changed`,
  a new claim is `added`, and a claim that could not be verified is `unverified`. A
  prefixed note from an earlier release (`CHANGED:`, `ADDED:`) is removed along with the
  result it explained, and the manifest's git history keeps it. A live claim's `closed_by`
  is not derived again. Since CONTENT-032 every stamp names the release commit, so every
  claim is restamped at every release. A sticky `result`, a per-release history, and
  updating `result` only when a quote changes were rejected. The stale-claim checker does
  not read `result`, except to surface `unverified`.
- **How a `closed[]` record is checked for reopening.** A closed record's `evidence` is the
  literals at the release commit that show the fix (CONTENT-031). The checker re-checks
  them at the target by the same rules as a live claim's evidence (and `absent`/`counts`,
  if a record carries them). If every check passes, the record is `closed`; if any check
  fails, it is `reopened`, which fails the run the same way a stale claim does. A record
  with no checks at all is also `reopened`, because nothing shows the fix still holds.
  Detecting a `git revert` of `closed_by.commit`, and checking whether the gap reappears on
  a page, were rejected.

### Disagreements and unspecified behaviour

- `ADDED:` is specced by CONTENT-035 and in use, but CER-045 and INFRA-015's own Context omit it.
- CONTENT-030's schema sketch gives `symbol` as "symbol or behaviour", while its Ensures require a literal. The manifest follows the literal rule, and so does this reference.
- No single spec lists all four `result` values. CONTENT-031 allows `open`/`changed`/`added`, and CONTENT-032 allows `open`/`changed`/`unverified`.
- The Known-gaps claim has no `result`. CER-045 records this as a finding, but it is specced.
- CONTENT-030 specs `"evidence": []` with an explanatory note for a claim with no findable evidence. No manifest has used it.
- A `closed[]` record has no `page`, `quote`, `stamp` or `location`.
- What `result` means after a restamp, and how a `closed[]` record is checked for reopening, were unspecified until INFRA-016; § Restamps and closed records states both.
- `added` means new page text: a quote the page did not carry before, as CONTENT-035's GAP entries were. A claim that newly covers unchanged page text under an existing stamp is `open`. A restamp derives the same, because its test compares each quote against the previous release's pages, so § Restamps and closed records' "a new claim is `added`" applies to a claim whose quote is new. Ruled by the operator on 2026-09-30 in CONTENT-039's spec, where the Values row for `added` names only GAP entries and § Restamps and closed records covers only restamps.

---

## Layer rules

| Layer | May import from | May not import from |
|-------|----------------|---------------------|


---

## Build commands

```bash
# Build / test
none — static HTML, open file:// or serve with any static file server

# Run all tests
for t in scripts/*-selftest.sh; do bash "$t" && continue; exit 1; done
```

---

## Protected files

These files are working and must not be modified without a stated reason:

`index.html` and `gap-handoff.html` are generated-artifact bundles per
`docs/ideology.md`'s Generated-artifact discipline constraint — they are not
hand-edited outside the pairmode build loop (builder/reviewer subagents per story).
See that doc for the Phase 2 exception note covering loop-mediated, spec-cited,
reviewed edits.

---

## Non-negotiables


_(No non-negotiables defined yet — add them here as the project matures.)_

