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

**Count, confirmed from the extracted template (2026-09-30).** The planner's 2 is right.
Bounded from each section's own `<h2>` to its own stamp text, the Upgrade section (S-02)
holds one `<pre>` block, the six upgrade commands, and the Provider packs (condensed)
section (S-03) holds one, `journalctl -u forqsite | grep '\[block-registry\]'`. No
existing claim quote falls inside either block: C-002 to C-016 quote the paragraphs around
them. Both blocks hold at the release commit `1fda3228`, so no page text changes. The
S-03 install steps also carry inline commands (step 2's `pnpm add -w file:…`). They are
not `<pre>` blocks and stay in the Phase 15 remainder of CER-046.

## Requires

- CONTENT-038 is merged (the manifest holds C-001 to C-038, and CER-046 is in Do Later).
- A fetched forqsite clone contains `release.commit`. Its path is passed only as
  `FORQSITE_CLONE` and is never written into the repo.

## Ensures

`docs/claims-manifest.json` gains exactly C-039 (S-02) and C-040 (S-03), appended after
every base claim, as given in Instructions 1. Every other key, stamp and claim is
unchanged, and so is the file's `indent=2`, non-ASCII-escaped serialisation. Each block in
the two stamped sections contains the whitespace-normalised quote of a claim citing that
section's stamp. Each new quote occurs once in the extracted template, inside its own
section. Each evidence literal is a `git grep -F` hit at `release.commit`.
`scripts/stale-claims.py <release.commit>` exits 0 and reports both claims `untouched`.
The CER-046 row gains an appended note in its finding cell, and nothing else in
`docs/cer/backlog.md` changes. Both pages are byte-identical to base.

Forbidden proxy:
- a claim invented for a block rather than transcribed from Instructions 1;
- a coverage check that counts `<pre>` tags in the bundle, or bounds a section by a
  pattern that can close on its own start (CER-017);
- a quote matched line by line without normalising whitespace (CER-011).

## Instructions

1. **Manifest.** Append the two elements of the array below to `claims`, after C-038 and in this order. Then
   write the file back with `json.dumps(m, indent=2, ensure_ascii=False) + '\n'`, so that no
   other line moves. Transcribe them as given. If you build on a day other than 2026-09-30,
   change only the date in each note's opening sentence to the day you ran the Tests.

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
     }
   ]
   ```

   Why these values:
   - `result` is `open`. The quote is unchanged page text and the claim is not a GAP entry,
     so `added` does not fit: in § Values it means a new GAP entry with a new quote. The
     notes are unprefixed, as C-017's and C-022's are.
   - Each note says which parts of the block are this site's own choices and not forqsite
     claims: the systemd unit names, `cd /opt/forqsite`, and the upgrade's departures from
     the runbook's §12.1. It also says why the stamp's printed date is earlier. This
     follows CONTENT-035's `ADDED:` note.
   - No stamp changes. The claims were verified at `release.commit`, which both stamps
     already name.
2. **Backlog.** In `docs/cer/backlog.md`, append to the end of CER-046's finding cell, inside
   the cell and before ` | cold-eyes triage (CP-12)`, the following text. It is one line,
   with one leading space:

   ```text
    **Stamped-section part done 2026-09-30 — CONTENT-039: the only two `<pre>` blocks inside the Upgrade (S-02) and Provider packs (S-03) sections are claims C-039 and C-040. The inline commands in the S-03 install steps (step 2's `pnpm add`) and every block outside a stamped section stay open for Phase 15.**
   ```

   The row stays open.
3. **Pages.** Do not edit `index.html` or `gap-handoff.html`. Both blocks hold at the pin.
   If the Tests' executed checks fail against your clone, stop and report. Do not edit the
   page to make them pass.

Ideology: the evidence is forqsite's own `path` and literal ("Cite the source that makes a
claim checkable"). The notes name this site's conventions by route, and the claims name no
host ("Name the class, not the instance"). The Tests bound each section by its own heading
and stamp. They normalise whitespace, and they run the page's grep and the runbook's
ordering rather than trusting the quote ("Spec-authoring convention for mechanical
checks").

Preflight notes: `scripts/stale-claims.py` and `scripts/bundle-template.py` are only run,
not edited, so they are not in `touches:`. `index.html` stays in `touches:` from the stub but
must not change. `WHEN THE BUILD DID NOT INCLUDE THE PACK` is a heading on the page, not a
constant.

Length: past ~100 lines, because the two claim objects and the Tests script are what the
builder transcribes and the reviewer runs.

## Tests

The project has no test suite. Save this block to a scratch file outside the repo and run it
from the repo root with `FORQSITE_CLONE=<clone path> bash <file>`. On `main` it prints four
`FAIL:` lines and exits 1. This was checked on 2026-09-30, as was a clean pass on a
throwaway copy with Instructions 1 and 2 applied.

```bash
set -e
: "${FORQSITE_CLONE:?set FORQSITE_CLONE to the local forqsite clone}"
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT; BASE=$(git merge-base HEAD main)
git show $BASE:docs/claims-manifest.json > $S/base-manifest.json
git show $BASE:docs/cer/backlog.md > $S/base-backlog.md
python3 scripts/bundle-template.py verify index.html
python3 scripts/bundle-template.py extract index.html $S/index.html
git diff --quiet $BASE -- index.html gap-handoff.html || { echo 'FAIL: a page changed'; exit 1; }
python3 - "$S" <<'PY'
import html, json, os, re, subprocess, sys
S = sys.argv[1]; clone = os.environ['FORQSITE_CLONE']; bad = []
def check(ok, msg):
    if not ok: bad.append(msg)
raw = open('docs/claims-manifest.json').read(); m = json.loads(raw); b = json.load(open(f'{S}/base-manifest.json'))
rel = m['release']['commit']
def git(*a): return subprocess.run(['git', '-C', clone, *a], capture_output=True, text=True, errors='replace')
norm = lambda s: re.sub(r'\s+', ' ', s)
T = norm(open(f'{S}/index.html').read())
# 1. nothing else changed; the file keeps its serialisation
check(raw == json.dumps(m, indent=2, ensure_ascii=False) + '\n', 'manifest serialisation changed')
check({k: v for k, v in m.items() if k != 'claims'} == {k: v for k, v in b.items() if k != 'claims'}, 'release, stamps or another top-level key changed')
n = len(b['claims'])
check(m['claims'][:n] == b['claims'], 'a base claim changed or moved')
new = m['claims'][n:]
check([c['id'] for c in new] == ['C-039', 'C-040'], f"new claims are {[c['id'] for c in new]}, want C-039 and C-040")
# 2. the stamped sections, bounded by their own h2 and their own stamp text (CER-017)
st = {s['id']: s for s in m['stamps']}
sec = {}
for sid, h2 in (('S-02', '>Upgrade</h2>'), ('S-03', '>Provider packs (condensed)</h2>')):
    lo = T.index(h2); hi = T.index(norm(st[sid]['text']), lo); sec[sid] = (lo, hi)
check(sec['S-02'][1] < sec['S-03'][0], 'sections overlap')
pres = {sid: re.findall(r'<pre\b[^>]*>(.*?)</pre>', T[lo:hi], re.S) for sid, (lo, hi) in sec.items()}
check(sum(map(len, pres.values())) == 2 and all(pres.values()), f'expected 2 <pre> blocks, one per section: {[len(v) for v in pres.values()]}')
for sid, blocks in pres.items():
    qs = [norm(c['quote']) for c in m['claims'] if c['stamp'] == sid]
    for k, blk in enumerate(blocks):
        check(any(q in blk for q in qs), f'{sid}: <pre> block {k + 1} is checked by no claim')
# 3. each new claim: shape, quote inside its own section, evidence at the release commit
for c in new:
    i = c['id']
    check(set(c) == {'id', 'page', 'location', 'claim', 'quote', 'evidence', 'stamp', 'result', 'note'}, f'{i}: fields')
    check(c['page'] == 'index.html' and c['result'] == 'open' and c['stamp'] in sec, f'{i}: page, result or stamp')
    q = norm(c['quote']); lo, hi = sec.get(c['stamp'], (0, 0))
    check(T.count(q) == 1 and lo < T.find(q) < hi, f'{i}: quote not once inside its stamp section')
    check(not re.search(r'\bC-\d+', c['note']) and re.search(r'verified at the release commit on \d{4}-\d{2}-\d{2}', c['note'], re.I), f'{i}: note')
    check(c['evidence'], f'{i}: no evidence')
    for e in c['evidence']:
        check(git('grep', '-q', '-F', '-e', e['symbol'], rel, '--', e['path']).returncode == 0, f"{i}: {e['symbol']!r} not in {e['path']} at release")
    blob = json.dumps(c, ensure_ascii=False)
    check(not re.search(r'/mnt/|/home/|~/', blob) and clone not in blob, f'{i}: host path')
# 4. executed at the release commit
rb = git('show', f'{rel}:docs/operator-runbook.md').stdout
fence = rb.split('### 12.1', 1)[1].split('### 12.2', 1)[0].split('```bash', 1)[1].split('```', 1)[0]
steps = ['git pull', 'pnpm install', 'pnpm db:migrate', 'pnpm build']
def order(text):
    ls = [l.strip() for l in text.splitlines() if l.strip()]
    idx = [next((k for k, l in enumerate(ls) if l.startswith(s)), -1) for s in steps]
    return idx, (ls[-1] if ls else '')
full = open(f'{S}/index.html').read()
lo = full.index('>Upgrade</h2>'); blk = html.unescape(re.search(r'<pre\b[^>]*>(.*?)</pre>', full[lo:], re.S).group(1))
for name, text in (('page', blk), ('runbook 12.1', fence)):
    idx, last = order(text)
    check(-1 not in idx and idx == sorted(idx) and 'restart' in last, f'{name}: upgrade order is not pull, install, migrate, build, restart')
lo = full.index('>Provider packs (condensed)</h2>'); blk = html.unescape(re.search(r'<pre\b[^>]*>(.*?)</pre>', full[lo:], re.S).group(1))
pat = re.search(r"grep '([^']*)'", blk)
check(pat is not None, 'provider packs block has no grep pattern')
if pat:
    src = git('show', f'{rel}:src/services/block-registry/loader.ts').stdout
    check('`[block-registry] Provider "${provider.id}" rejected: block type(s) declare a ` +' in src, 'loader rejection line changed')
    g = lambda line: subprocess.run(['grep', '-q', '-e', pat.group(1)], input=line + '\n', text=True).returncode
    check(g('[block-registry] Provider "pack-x" rejected: block type(s) declare a clientComponent.importPath') == 0, 'page grep misses the rejection line')
    check(g('Provider pack-x rejected') == 1, 'page grep matches a line without the prefix')
# 5. backlog: only the CER-046 row, extended in its finding cell
B = open(f'{S}/base-backlog.md').read().splitlines(); N = open('docs/cer/backlog.md').read().splitlines()
check(len(B) == len(N), 'backlog line count changed')
rows = [k for k, l in enumerate(B) if l.startswith('| CER-046 |')]
check(len(rows) == 1, 'CER-046 row not found once in base')
if len(B) == len(N) and len(rows) == 1:
    r = rows[0]; check(all(B[k] == N[k] for k in range(len(B)) if k != r), 'a backlog line other than CER-046 changed')
    tail = ' | ' + ' | '.join(B[r].split(' | ')[-3:]); head = B[r][:-len(tail)]
    add = N[r][len(head):-len(tail)] if N[r].startswith(head) and N[r].endswith(tail) else ''
    check('CONTENT-039' in add and 'Phase 15' in add, 'CER-046 lacks an appended CONTENT-039 note naming Phase 15')
    check(not re.search(r'/mnt/|/home/|~/', add) and clone not in add, 'backlog host path')
for x in bad: print('FAIL:', x)
print('OK' if not bad else f'{len(bad)} FAILED'); sys.exit(1 if bad else 0)
PY
python3 scripts/stale-claims.py "$(python3 -c "import json; print(json.load(open('docs/claims-manifest.json'))['release']['commit'])")" > $S/report.txt || { echo "FAIL: stale-claims exit $?"; exit 1; }
for i in C-039 C-040; do grep -q "^$i untouched" $S/report.txt || { echo "FAIL: $i not untouched in the stale-claims report"; exit 1; }; done
echo DONE
```

Pass means the script prints `OK` then `DONE` and exits 0. The reviewer also reads both
claims against the blocks and the clone. The check is that neither claim asserts something
forqsite does not say, such as the unit names or `/opt/forqsite`.

## Out of scope

- Command blocks outside S-02 and S-03, and the inline commands in the S-03 install steps.
  These are Phase 15 (CER-046's remainder).
- Gap-status mentions outside the manifest (CER-056), and the U+200B comment lines (CER-051).
- Restamping, and any change to a stamp's text, date or scope. That is INFRA-020.
- Editing either page.
