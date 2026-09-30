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
  - docs/architecture.md

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

**Operator rulings (2026-09-30), on the first draft of this spec:**
1. **`open` for a claim that newly covers unchanged page text.** Research found no
   precedent: C-037 and C-038, the only claims added since `result` existed, were both for
   new page text. The § Restamps and closed records ruling ("a new claim is `added`")
   governs restamps, and this story is not one. The ruling is written into
   `docs/architecture.md` (Instructions 4).
2. **Inline commands count.** The story's purpose is that a restamp never re-asserts an
   unchecked command inside a stamped section, whether or not the command is in a `<pre>`
   block. So install step 2 (`pnpm add -w file:…tgz` and its sha512 check) gets a claim,
   and S-02 and S-03 were swept again for any other inline command text.

**What the sweep found (extracted template, 2026-09-30).** Each section is bounded by its
own `<h2>` and its own stamp text. S-02 and S-03 each hold one `<pre>` block, 2 in total, as
the planner counted. The inline command text in both sections, from every Geist Mono span
that starts with a command or an env assignment, is:

| Section | Element | Command text | Checked by |
|---|---|---|---|
| S-02 | `<pre>` block | the six upgrade commands | C-039 (new) |
| S-02 | opening paragraph; "That window…" paragraph | `pnpm build`, `pnpm db:migrate` | not a new instruction: these name commands from the C-039 block |
| S-02 | migrations paragraph | `pnpm db:migrate`, `drizzle-kit migrate` | C-002 |
| S-02 | ROLLING BACK, first paragraph | `pnpm install --frozen-lockfile`, `pnpm build`, restart | C-041 (new): a procedure in its own right |
| S-02 | A MISSED MIGRATION paragraph | `journalctl -u forqsite \| grep check-migration` | C-004: its claim covers both checks' `check-migration` log lines |
| S-03 | ceiling paragraph | `pnpm db:migrate` | C-009 |
| S-03 | install step 2 | `pnpm add -w file:/path/to/pack.tgz`, sha512 check | C-042 (new, `changed`) |
| S-03 | install step 4 | `pnpm build` → restart | C-043 (new) |
| S-03 | signatures note | `REQUIRE_PACK_SIGNATURES=true` | C-013 |
| S-03 | `<pre>` block | `journalctl -u forqsite \| grep '\[block-registry\]'` | C-040 (new) |
| S-03 | last paragraph | `pnpm generate:registries` | C-016. It is also a `package.json` script at the pin. |

The other Mono spans are paths, identifiers, env names and routes, not commands:
`config/providers.json`, `jsonb`, `import('<path>')`, `/api/health`, and the like. The
S-03 opening paragraph ("put the previous pin back … rebuild, restart") restates C-041's
rollback in words and has no command text.

**Step 2 is wrong at the pin.** The operator runbook's §14.2, at `1fda3228`, installs by
scoped package name: `pnpm add -w "@forqsite-packs/<name>@<version>"`. It verifies the
sha512 first, then requires the lockfile entry to carry both `integrity` and `tarball`. It
withdraws `pnpm add -w file:/path/to/<received-pack>.tgz` by name, and
`pnpm verify:provider-pins` reports a `file:` specifier. The handover contract, which the
runbook calls authoritative, was rewritten the same way. forqsite's own platform-admin
install page still prints the withdrawn command, which is a forqsite-side inconsistency. So
this story rewrites step 2, and C-042 records it as `changed`. The other four blocks hold at
the pin.

## Requires

- CONTENT-038 is merged (the manifest holds C-001 to C-038, and CER-046 is in Do Later).
- A fetched forqsite clone contains `release.commit`. Its path is passed only as
  `FORQSITE_CLONE` and is never written into the repo.
- `chromium` is on PATH, for the rendered-DOM check.

## Ensures

`docs/claims-manifest.json` gains exactly C-039 to C-043, appended after every base claim, as
given in Instructions 1. Every other key, stamp and claim is unchanged, and the file keeps
its `indent=2`, non-ASCII-escaped serialisation. In S-02 and S-03, every `<pre>` block
contains the whitespace-normalised quote of a claim on that section's stamp. So does every
element holding inline command text, unless each of its commands appears verbatim in a
covered `<pre>` of the same section. Each new quote occurs once in the extracted template,
inside its own section. Each new claim is `open` if its quote is unchanged page text and
`changed` (with a `CHANGED:` note) if it is not. Every evidence literal is a `git grep -F`
hit at `release.commit`, and every `absent` literal is a verified miss there. Install step
2's command equals the runbook §14.2 command at the pin.

In `index.html` only install step 2 changes, and `#ops` renders the new step with
`<script>` stripped first. `gap-handoff.html` is byte-identical to base, and both bundles
verify. `docs/architecture.md` gains exactly one bullet, at the end of § Disagreements and
unspecified behaviour. The CER-046 row gains one appended note, and nothing else in the
backlog changes. `scripts/stale-claims.py <release.commit>` exits 0 and reports all five
new claims `untouched`.

Forbidden proxy:
- a claim invented rather than transcribed from Instructions 1;
- coverage counted from the bundle, or a section bounded by a pattern that can close on its
  own start (CER-017);
- a quote or a ruling matched line by line without normalising whitespace (CER-011);
- a page or doc change checked by scanning diff lines that could match text already there.

## Instructions

1. **Manifest.** Append the five elements of the array below to `claims`, after C-038 and
   in this order. Then write the file back with
   `json.dumps(m, indent=2, ensure_ascii=False) + '\n'`, so no other line moves. Transcribe
   them as given. If you build on a day other than 2026-09-30, change only the verification
   date in each note to the day you ran the Tests.

   ```json
   [
     {
       "id": "C-039",
       "page": "index.html",
       "location": "Operations route, \"Upgrade\" section, the six-command block under the section's opening paragraph",
       "claim": "An upgrade is forqsite's documented single-instance sequence: git pull, a dependency install, pnpm db:migrate, pnpm build, then a restart of the app and its scheduler, which costs about 10–20 seconds of downtime; the install is frozen to the lockfile, as forqsite's own first-run install is.",
       "quote": "pnpm install --frozen-lockfile\npnpm db:migrate\npnpm build",
       "evidence": [
         {
           "path": "docs/operator-runbook.md",
           "symbol": "### 12.1 Standard upgrade (single instance)"
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "pm2 restart forqsite   # or your process manager"
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "Expect ~10–20 seconds of downtime while the process restarts."
         },
         {
           "path": "scripts/firstrun.sh",
           "symbol": "pnpm install --frozen-lockfile"
         },
         {
           "path": "package.json",
           "symbol": "\"db:migrate\": \"dotenv -e .env.local -- drizzle-kit migrate\","
         },
         {
           "path": "package.json",
           "symbol": "\"build\": \"dotenv -e .env.local -- next build\","
         },
         {
           "path": "package.json",
           "symbol": "\"scheduler\": \"tsx scripts/scheduler.ts\","
         }
       ],
       "stamp": "S-02",
       "result": "open",
       "note": "Verified at the release commit on 2026-09-30, when this block was brought under the section's stamp; the stamp's printed date, 2026-09-24, is the earlier verification of the claims it already covered. The block departs from the runbook's section 12.1 where this site makes its own choice, not a forqsite claim: it restarts this site's systemd units, named on the Process supervision route, where the runbook writes pm2 restart forqsite or your process manager, and it installs with --frozen-lockfile, as forqsite's first-run script does, where the runbook writes pnpm install. The cd path is this site's install location from the Install sequence route."
     },
     {
       "id": "C-040",
       "page": "index.html",
       "location": "Operations route, \"Provider packs (condensed)\" section, the log command under \"WHEN THE BUILD DID NOT INCLUDE THE PACK\"",
       "claim": "The rejection of a pack whose client component is missing from the generated client registry is logged with a [block-registry] prefix, so grepping the process log for that prefix finds it.",
       "quote": "journalctl -u forqsite | grep '\\[block-registry\\]'",
       "evidence": [
         {
           "path": "src/services/block-registry/loader.ts",
           "symbol": "`[block-registry] Provider \"${provider.id}\" rejected: block type(s) declare a ` +"
         },
         {
           "path": "src/services/block-registry/loader.ts",
           "symbol": "`clientComponent.importPath not present in the generated client registry ` +"
         }
       ],
       "stamp": "S-03",
       "result": "open",
       "note": "Verified at the release commit on 2026-09-30, when this block was brought under the section's stamp; the stamp's printed date, 2026-09-24, is the earlier verification of the claims it already covered. The unit name is this site's own systemd unit from the Process supervision route, not a forqsite claim. The page's grep pattern was run against a line that begins with the logged prefix, and matched it."
     },
     {
       "id": "C-041",
       "page": "index.html",
       "location": "Operations route, \"Upgrade\" section, the first paragraph under \"ROLLING BACK\"",
       "claim": "Rolling back is putting the previous commit, lockfile and provider manifest back, then a frozen-lockfile install, pnpm build and a restart; that restores the build and not the schema, because forqsite has no down migration and no rollback script.",
       "quote": "that returns the artifact and only the artifact",
       "evidence": [
         {
           "path": "scripts/firstrun.sh",
           "symbol": "pnpm install --frozen-lockfile"
         },
         {
           "path": "package.json",
           "symbol": "\"build\": \"dotenv -e .env.local -- next build\","
         },
         {
           "path": "next.config.mjs",
           "symbol": "process.env.PROVIDER_MANIFEST_PATH ?? path.resolve(process.cwd(), 'config/providers.json')"
         },
         {
           "path": "package.json",
           "symbol": "\"db:migrate\": \"dotenv -e .env.local -- drizzle-kit migrate\","
         }
       ],
       "stamp": "S-02",
       "result": "open",
       "absent": [
         {
           "path": "package.json",
           "symbol": "rollback"
         }
       ],
       "note": "Verified at the release commit on 2026-09-30, when this paragraph was brought under the section's stamp; the stamp's printed date, 2026-09-24, is the earlier verification of the claims it already covered. The restart is this site's systemd restart from the Upgrade block."
     },
     {
       "id": "C-042",
       "page": "index.html",
       "location": "Operations route, \"Provider packs (condensed)\" section, install step 2",
       "claim": "A reviewed pack is installed by scoped package name and version from the pack store, after its sha512 is checked against the one handed over, and the resulting lockfile entry must carry both integrity and tarball; installing the tarball from disk with a file: specifier is withdrawn, and forqsite's pin check reports it.",
       "quote": "Installing the tarball from disk",
       "evidence": [
         {
           "path": "docs/operator-runbook.md",
           "symbol": "pnpm add -w \"@forqsite-packs/<name>@<version>\""
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "Verify the sha512 against the one handed over first, and confirm"
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "the resulting lockfile entry carries **both** `integrity` and `tarball` before continuing"
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "**`pnpm add -w file:/path/to/<received-pack>.tgz` is withdrawn**, and is named here rather than"
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "reports a `file:` specifier as a `file-specifier` finding."
         },
         {
           "path": "package.json",
           "symbol": "\"verify:provider-pins\": \"tsx scripts/verify-provider-pins.ts\","
         },
         {
           "path": "scripts/verify-provider-pins.ts",
           "symbol": "findings.push({ file, line: lineNo, kind: 'file-specifier', match: m[0] })"
         },
         {
           "path": "docs/handoff/forqsite-sdk-handover-contract.md",
           "symbol": "**That step 9 no longer says this**"
         }
       ],
       "stamp": "S-03",
       "result": "changed",
       "note": "CHANGED: step 2 said \"pnpm add -w file:/path/to/pack.tgz — after verifying its sha512 against what the author handed over\"; at the release commit the operator runbook's section 14.2 installs by scoped package name, pnpm add -w \"@forqsite-packs/<name>@<version>\", withdraws the file: tarball install by name, and requires the lockfile entry to carry integrity and tarball, and the handover contract's step 9, which the runbook names as authoritative, was rewritten the same way. Step 2 now gives the scoped install, keeps the sha512 check, names the lockfile check, and says the file: install is withdrawn. forqsite's own platform-admin install page still prints the withdrawn command. Verified on 2026-09-30; the stamp's printed date, 2026-09-24, is the earlier verification of the claims it already covered."
     },
     {
       "id": "C-043",
       "page": "index.html",
       "location": "Operations route, \"Provider packs (condensed)\" section, install step 4",
       "claim": "After the manifest entry, pnpm build then a restart is all it takes: the build regenerates the server registry, the client-component registry and the transpile list from the provider manifest, with no hand edit to any source file, and a pack the install page lists as not registered means the generated registry is stale and needs a rebuild.",
       "quote": "The build regenerates both registries and the transpile list from the manifest",
       "evidence": [
         {
           "path": "package.json",
           "symbol": "\"prebuild\": \"pnpm build:sdk && dotenv -e .env.local -- tsx scripts/generate-client-registry.ts\","
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "The build's prebuild step regenerates `src/services/block-registry/server-provider-registry.ts`,"
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "`src/components/blocks/client-registry.ts` and the transpile list from the manifest — there is"
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "no hand-edited registry and no `next.config.mjs` edit (BLOCKS-025)"
         },
         {
           "path": "docs/operator-runbook.md",
           "symbol": "Then restart the application"
         },
         {
           "path": "src/app/platform-admin/block-providers/install/page.tsx",
           "symbol": " * the GENERATED server registry, so \"not registered\" means \"stale — rebuild\"."
         }
       ],
       "stamp": "S-03",
       "result": "open",
       "note": "Verified at the release commit on 2026-09-30, when this step was brought under the section's stamp; the stamp's printed date, 2026-09-24, is the earlier verification of the claims it already covered. The regenerated registries are generated files that forqsite commits; the page's no source file is edited means no hand edit."
     }
   ]
   ```

   Why these values:
   - C-039, C-040, C-041 and C-043 are `open`, per ruling 1. Their quotes are unchanged page
     text.
   - C-042 is `changed`, because its quote is new text written by Instructions 2.
   - The notes say which parts of the page are this site's own choices and not forqsite
     claims (the systemd units, `cd /opt/forqsite`, and the upgrade's departures from
     §12.1), and why the stamp's printed date is earlier.
   - No stamp changes. Every claim was verified at `release.commit`, which both stamps
     already name.
2. **Page: install step 2.** Follow `docs/architecture.md` § Editing procedure
   (`bundle-template.py extract`, edit, `inject`, `verify`). In the extracted `index.html`
   template, replace this exact substring, which occurs once:

   ```html
   <span style="font-family:'Geist Mono',monospace; font-size:12.5px;">pnpm add -w file:/path/to/pack.tgz</span> &mdash; after verifying its sha512 against what the author handed over.</span></div>
   ```

   with:

   ```html
   <span style="font-family:'Geist Mono',monospace; font-size:12.5px;">pnpm add -w "@forqsite-packs/&lt;name&gt;@&lt;version&gt;"</span> &mdash; by package name from the pack store, after verifying its sha512 against what the author handed over. The lockfile entry must then carry both <span style="font-family:'Geist Mono',monospace; font-size:12.5px;">integrity</span> and <span style="font-family:'Geist Mono',monospace; font-size:12.5px;">tarball</span>. Installing the tarball from disk with <span style="font-family:'Geist Mono',monospace; font-size:12.5px;">file:</span> is withdrawn: forqsite&rsquo;s pin check rejects it.</span></div>
   ```

   Change nothing else on either page. The same withdrawn command on the unstamped Provider
   lifecycle route ("The swap") is out of scope (see Out of scope).
3. **Backlog.** Append the following text to the end of CER-046's finding cell in
   `docs/cer/backlog.md`, inside the cell, just before ` | cold-eyes triage (CP-12)`. It is
   one line, with one leading space. The row stays open.

   ```text
 **Stamped-section part done 2026-09-30 — CONTENT-039: every command inside the Upgrade (S-02) and Provider packs (S-03) sections is now checked by a claim. The two `<pre>` blocks are C-039 and C-040, the Rolling back paragraph is C-041, and install steps 2 and 4 are C-042 and C-043. Step 2 was wrong at the pin (the withdrawn `file:` tarball install) and now gives the scoped-package install. The same withdrawn `pnpm add -w file:` install still appears in the unstamped Provider lifecycle swap steps, and it stays open for Phase 15 with every other block outside a stamped section.**
   ```
4. **Architecture (ruling 1).** Append this bullet as the last item of
   `docs/architecture.md` § Disagreements and unspecified behaviour, directly after the
   INFRA-016 bullet:

   ```markdown
- `added` means new page text: a quote the page did not carry before, as CONTENT-035's GAP entries were. A claim that newly covers unchanged page text under an existing stamp is `open`. A restamp derives the same, because its test compares each quote against the previous release's pages, so § Restamps and closed records' "a new claim is `added`" applies to a claim whose quote is new. Ruled by the operator on 2026-09-30 in CONTENT-039's spec, where the Values row for `added` names only GAP entries and § Restamps and closed records covers only restamps.
   ```

   Why § Disagreements rather than the Values table's `added` row: that section is where
   rulings that reconcile two specs go, and the INFRA-016 `result` bullet already sits
   there. The Values row's Status and Source cells record what CONTENT-031 and CONTENT-035
   specced. Rewriting the row's meaning would credit a ruling to sources that never made
   it.

Ideology:
- The evidence is forqsite's own `path` and literal ("Cite the source that makes a claim
  checkable").
- The notes name this site's conventions by route, and no host ("Name the class, not the
  instance").
- The step-2 rewrite is a loop-mediated, spec-cited bundle edit, which the Generated-artifact
  discipline's Phase 2 exception accepts.
- The Tests bound sections by their own heading and stamp, normalise whitespace, compare
  page and doc content rather than diff lines, and run the page's commands against the pin
  ("Spec-authoring convention for mechanical checks").

Preflight notes: `scripts/stale-claims.py` and `scripts/bundle-template.py` are only run, not
edited, so they are not in `touches:`. `WHEN THE BUILD DID NOT INCLUDE THE PACK` and
`ROLLING BACK` are page headings, not constants. `PROVIDER_MANIFEST_PATH`, `GENERATED` and
`BLOCKS-025` are literals in the forqsite source, and `CHANGED:` is a note prefix.

Length: well past ~100 lines, because the five claim objects, the exact page substring and
the Tests script are what the builder transcribes and the reviewer runs.

## Tests

The project has no test suite. Save this block to a scratch file outside the repo and run it
from the repo root with `FORQSITE_CLONE=<clone path> bash <file>`. It was run on 2026-09-30:
- On `main` it printed 14 `FAIL:` lines and exited 1.
- On a throwaway copy with Instructions 1 to 4 applied, it printed `OK` then `DONE`.
- Three mutations each made it fail: C-041 set to `added`, C-043 dropped, and one line
  added to `docs/architecture.md` outside § Disagreements.

```bash
set -e
: "${FORQSITE_CLONE:?set FORQSITE_CLONE to the local forqsite clone}"
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT; BASE=$(git merge-base HEAD main)
for f in docs/claims-manifest.json docs/cer/backlog.md docs/architecture.md index.html; do git show $BASE:$f > $S/base.${f##*/}; done
for p in index.html gap-handoff.html; do python3 scripts/bundle-template.py verify $p; done
python3 scripts/bundle-template.py extract index.html $S/index.t.html
python3 scripts/bundle-template.py extract $S/base.index.html $S/base.index.t.html
git diff --quiet $BASE -- gap-handoff.html || { echo 'FAIL: gap-handoff.html changed'; exit 1; }
timeout 60 chromium --headless --disable-gpu --no-sandbox --virtual-time-budget=5000 --dump-dom "file://$PWD/index.html#ops" > $S/dom-ops 2>/dev/null
python3 - "$S" <<'PY'
import html, json, os, re, subprocess, sys
S = sys.argv[1]; clone = os.environ['FORQSITE_CLONE']; bad = []
def check(ok, msg):
    if not ok: bad.append(msg)
norm = lambda s: re.sub(r'\s+', ' ', s).strip()
raw = open('docs/claims-manifest.json').read(); m = json.loads(raw); b = json.load(open(f'{S}/base.claims-manifest.json'))
rel = m['release']['commit']
def git(*a): return subprocess.run(['git', '-C', clone, *a], capture_output=True, text=True, errors='replace')
def show(p): return git('show', f'{rel}:{p}').stdout
T = norm(open(f'{S}/index.t.html').read()); BT = norm(open(f'{S}/base.index.t.html').read())
MONO = "<span style=\"font-family:'Geist Mono',monospace; font-size:12.5px;\">"
# 1. manifest: base untouched, five new claims appended, serialisation kept
check(raw == json.dumps(m, indent=2, ensure_ascii=False) + '\n', 'manifest serialisation changed')
check({k: v for k, v in m.items() if k != 'claims'} == {k: v for k, v in b.items() if k != 'claims'}, 'release, stamps or another top-level key changed')
n = len(b['claims']); check(m['claims'][:n] == b['claims'], 'a base claim changed or moved')
new = m['claims'][n:]; want = ['C-039', 'C-040', 'C-041', 'C-042', 'C-043']
check([c['id'] for c in new] == want, f"new claims are {[c['id'] for c in new]}, want {want}")
# 2. the stamped sections, each bounded by its own h2 and its own stamp text (CER-017)
st = {s['id']: s for s in m['stamps']}
def sections(t):
    out = {}
    for sid, h2 in (('S-02', '>Upgrade</h2>'), ('S-03', '>Provider packs (condensed)</h2>')):
        lo = t.index(h2); out[sid] = (lo, t.index(norm(st[sid]['text']), lo))
    return out
sec = sections(T); bsec = sections(BT)
# 3. coverage: each <pre> block, and each element holding inline command text, carries a quote of a claim on that stamp
CMD = re.compile(r'^(pnpm|git|sudo|journalctl|drizzle-kit|systemctl|npm|npx|tsx|cd)\s|^[A-Z][A-Z0-9_]*=')
pres_total = 0
for sid, (lo, hi) in sec.items():
    qs = [norm(c['quote']) for c in m['claims'] if c['stamp'] == sid]
    chunks = re.split(r'(?=<(?:p|pre|div)\b)', T[lo:hi])
    pres = [c for c in chunks if c.startswith('<pre')]; pres_total += len(pres)
    covered_pre = [c for c in pres if any(q in c for q in qs)]
    for k, c in enumerate(pres): check(c in covered_pre, f'{sid}: <pre> block {k + 1} is checked by no claim')
    for c in chunks:
        if c.startswith('<pre'): continue
        cmds = [html.unescape(x) for x in re.findall(re.escape(MONO) + r'(.*?)</span>', c) if CMD.search(html.unescape(x))]
        if not cmds or any(q in c for q in qs): continue
        loose = [x for x in cmds if not any(html.escape(x, quote=False) in p for p in covered_pre)]
        check(not loose, f'{sid}: inline command {loose} is checked by no claim')
check(pres_total == 2, f'expected 2 <pre> blocks in S-02 and S-03, found {pres_total}')
# 4. each new claim: shape, quote once inside its own section, the result rule, evidence at the release commit
for c in new:
    i = c['id']; q = norm(c['quote']); lo, hi = sec.get(c['stamp'], (0, 0)); blo, bhi = bsec.get(c['stamp'], (0, 0))
    check(set(c) - {'absent'} == {'id', 'page', 'location', 'claim', 'quote', 'evidence', 'stamp', 'result', 'note'}, f'{i}: fields')
    check(c['page'] == 'index.html' and c['stamp'] in ('S-02', 'S-03') and c['evidence'], f'{i}: page, stamp or evidence')
    check(T.count(q) == 1 and lo < T.find(q) < hi, f'{i}: quote not once inside its stamp section')
    was = q in BT[blo:bhi]  # the operator's 2026-09-30 rule: open iff the quote is unchanged page text
    check(c['result'] == ('open' if was else 'changed'), f"{i}: result {c['result']} but quote {'is' if was else 'is not'} in the base page")
    check(c['note'].startswith('CHANGED:') == (c['result'] == 'changed') and not re.search(r'\bC-\d+', c['note']), f'{i}: note')
    for e in c['evidence']:
        check(git('grep', '-q', '-F', '-e', e['symbol'], rel, '--', e['path']).returncode == 0, f"{i}: {e['symbol']!r} not in {e['path']} at release")
    for a in c.get('absent', []):
        check(git('cat-file', '-e', f"{rel}:{a['path']}").returncode == 0 and git('grep', '-q', '-F', '-e', a['symbol'], rel, '--', a['path']).returncode == 1, f'{i}: absent {a}')
    blob = json.dumps(c, ensure_ascii=False); check(not re.search(r'/mnt/|/home/|~/', blob) and clone not in blob, f'{i}: host path')
# 5. executed at the release commit
full = open(f'{S}/index.t.html').read()
def pre_after(h2): return html.unescape(re.search(r'<pre\b[^>]*>(.*?)</pre>', full[full.index(h2):], re.S).group(1))
rb = show('docs/operator-runbook.md')
fence = lambda sec_, nxt: rb.split(sec_, 1)[1].split(nxt, 1)[0].split('```bash', 1)[1].split('```', 1)[0]
steps = ['git pull', 'pnpm install', 'pnpm db:migrate', 'pnpm build']
for name, text in (('page', pre_after('>Upgrade</h2>')), ('runbook 12.1', fence('### 12.1', '### 12.2'))):
    ls = [l.strip() for l in text.splitlines() if l.strip()]
    idx = [next((k for k, l in enumerate(ls) if l.startswith(s)), -1) for s in steps]
    check(-1 not in idx and idx == sorted(idx) and ls and 'restart' in ls[-1], f'{name}: upgrade order is not pull, install, migrate, build, restart')
g = lambda pat, line: subprocess.run(['grep', '-q', '-e', pat], input=line + '\n', text=True).returncode
pat = re.search(r"grep '([^']*)'", pre_after('>Provider packs (condensed)</h2>'))
check(pat and g(pat.group(1), '[block-registry] Provider "pack-x" rejected: block type(s) declare a clientComponent.importPath') == 0 and g(pat.group(1), 'Provider pack-x rejected') == 1, 'provider packs grep does not select the [block-registry] line')
s3 = T[sec['S-03'][0]:sec['S-03'][1]]
step2 = [html.unescape(x) for x in re.findall(re.escape(MONO) + r'(pnpm add [^<]*)</span>', s3)]
check(len(step2) == 1 and step2[0].strip() in fence('### 14.2', '### 14.3').splitlines(), f'step 2 install {step2} is not the runbook 14.2 command')
check('file:/path/to/pack.tgz' not in s3, 'S-03 still gives the file: install')
cm = re.search(r'grep (check-migration)</span>', T[sec['S-02'][0]:sec['S-02'][1]])
check(cm and all(cm.group(1) in s for s in ('[WARN] check-migrations:', '[check-migration-hashes]')) and '[WARN] check-migrations:' in show('scripts/check-migrations.ts'), 'check-migration grep')
# 6. index.html: only install step 2 changed (compared as template content, not diff lines)
def cut(t, lo, hi):
    k = t.index('<span style="color:#2f3aff; font-weight:600;">2</span>', lo); e = t.index('</div>', k)
    check(k < hi, 'step 2 not in S-03'); return t[:k] + t[e:], t[k:e]
rest, s2 = cut(T, *sec['S-03']); brest, bs2 = cut(BT, *bsec['S-03'])
check(rest == brest, 'index.html changed outside install step 2')
check(s2 != bs2 and 'Installing the tarball from disk' in s2, 'install step 2 not rewritten')
dom = norm(html.unescape(re.sub(r'<[^>]+>', ' ', re.sub(r'(?is)<(script|style)\b.*?</\1>', '', open(f'{S}/dom-ops').read()))))
check('pnpm add -w "@forqsite-packs/<name>@<version>"' in dom and 'Installing the tarball from disk' in dom, 'new step 2 not rendered on #ops')
# 7. architecture.md: one bullet appended to § Disagreements and unspecified behaviour, nothing else
def disagree(t):
    lo = t.index('### Disagreements and unspecified behaviour'); hi = t.index('\n---', lo)
    return t[:lo] + t[hi:], [norm(x) for x in re.split(r'\n- ', t[lo:hi])[1:]]
A, AB = disagree(open('docs/architecture.md').read()), disagree(open(f'{S}/base.architecture.md').read())
check(A[0] == AB[0] and A[1][:len(AB[1])] == AB[1] and len(A[1]) == len(AB[1]) + 1, 'architecture.md: not exactly one bullet appended to Disagreements')
if len(A[1]) == len(AB[1]) + 1:
    for k in ('`added` means new page text', 'unchanged page text under an existing stamp is `open`', 'restamp', "previous release's pages", '2026-09-30'):
        check(k in A[1][-1], f'architecture bullet lacks {k!r}')
# 8. backlog: only the CER-046 row, extended in its finding cell
B = open(f'{S}/base.backlog.md').read().splitlines(); N = open('docs/cer/backlog.md').read().splitlines()
rows = [k for k, l in enumerate(B) if l.startswith('| CER-046 |')]
check(len(B) == len(N) and len(rows) == 1, 'backlog line count or CER-046 row')
if len(B) == len(N) and len(rows) == 1:
    r = rows[0]; check(all(B[k] == N[k] for k in range(len(B)) if k != r), 'a backlog line other than CER-046 changed')
    tail = ' | ' + ' | '.join(B[r].split(' | ')[-3:]); head = B[r][:-len(tail)]
    add = N[r][len(head):-len(tail)] if N[r].startswith(head) and N[r].endswith(tail) else ''
    check(all(k in add for k in ['CONTENT-039', 'Phase 15'] + want), 'CER-046 lacks the CONTENT-039 note naming Phase 15 and the five claims')
    check(not re.search(r'/mnt/|/home/|~/', add) and clone not in add, 'backlog host path')
for x in bad: print('FAIL:', x)
print('OK' if not bad else f'{len(bad)} FAILED'); sys.exit(1 if bad else 0)
PY
python3 scripts/stale-claims.py "$(python3 -c "import json; print(json.load(open('docs/claims-manifest.json'))['release']['commit'])")" > $S/report.txt || { echo "FAIL: stale-claims exit $?"; exit 1; }
for i in C-039 C-040 C-041 C-042 C-043; do grep -q "^$i untouched" $S/report.txt || { echo "FAIL: $i not untouched in the stale-claims report"; exit 1; }; done
echo DONE
```

Pass means the script prints `OK` then `DONE` and exits 0. The reviewer also reads each claim
against its element and the clone. The check is that none asserts something forqsite does
not say, such as the unit names or `/opt/forqsite`, and that the new step 2 reads correctly
in the rendered `#ops` route.

## Out of scope

- Command text outside S-02 and S-03. That is Phase 15 (CER-046's remainder). It includes
  the same withdrawn `pnpm add -w file:` install on the unstamped Provider lifecycle route,
  which the CER-046 note records.
- forqsite's own install page still printing the withdrawn command. That is an upstream
  inconsistency, and a GAP entry for it is not this story's.
- Gap-status mentions outside the manifest (CER-056), and the U+200B comment lines (CER-051).
- Restamping, and any change to a stamp's text, date or scope. That is INFRA-020.
- Changing the Values table or § Restamps and closed records. Ruling 1 is recorded only as
  the Disagreements bullet.
