---
id: INFRA-015
rail: INFRA
title: Claims manifest schema reference
status: planned
phase: "13"
story_class: doc
auth_gated: false
schema_introduces: false
primary_files:
  - docs/architecture.md
touches:
  - docs/cer/backlog.md
narrative_roles: []
---

## Context

This story closes the documentation half of CER-045. The field vocabulary of
`docs/claims-manifest.json` is defined only across the CONTENT-030 to CONTENT-032 and
CONTENT-035 to CONTENT-037 specs, and no reference states it. These fields are `release`,
`stamps`, `claims`, `quote`, `evidence`, `absent`, `counts`, `result`
(`open`/`changed`/`added`/`unverified`), `marker`, `closed_by`, `note` prefixes
(`CHANGED:`, `UNVERIFIED:`, `MISMATCH:`), and the top-level `closed` array that no manifest
has used yet. The stale-claim checker (INFRA-016) reads this manifest and needs one
authoritative definition to build against. Write that definition once, where a reader of
the architecture finds it, and derive every field's meaning from the specs that introduced
it and from the live manifest. Do not invent semantics. Where a spec and the manifest
disagree, or a field was specced but never exercised (`closed`, `marker`), say so.

Operator decision 2026-09-29: this story and INFRA-016 are Phase 13's checker work. CER-046
(command blocks into the manifest) is deferred.

Operator decisions 2026-09-29, on this spec's open questions:
- The schema goes in a new `docs/architecture.md` section, which reverses CONTENT-030
  Instructions 7. The section itself must state the reversal and its reason.
- What `result` means after a restamp, and how a `closed[]` record is checked for reopening,
  are decided in INFRA-016's spec, not here.
- This story adds a progress note to CER-045. The row stays open until INFRA-016's fixture
  tests ship.

**Where the reference goes.** It goes in `docs/architecture.md`, as the stub proposes.
CLAUDE.md makes that file required reading before any task, so INFRA-016's builder reads it
cold without being pointed at it. This reverses CONTENT-030 Instructions 7 ("Do not describe
its schema there, because the file already shows it"). That instruction's premise no longer
holds. The file cannot show a field or value that it has never contained (`closed`,
`marker`, `unverified`, `UNVERIFIED:`), and it no longer contains `MISMATCH:`. A separate
`docs/claims-manifest.md` was considered and rejected, because it would need a pointer that
a cold reader might not follow.

## Requires

- CONTENT-038 is merged (it is, per `docs/phases/phase-13.md`).
- `docs/claims-manifest.json` is unchanged from `main`. This story only reads it.

## Ensures

`docs/architecture.md` has a `## Claims manifest schema` section that the Tests script can
check against the manifest. It documents every key that has ever occurred in any committed
version of the manifest, and every specced or observed `result` value and `note` prefix.
Each of these carries a status that matches the manifest's git history, and cites a spec
that names it. The section records the disagreements and unspecified behaviour listed in
Instructions 4. The existing **Claims manifest.** paragraph points to the section. CER-045's
row in `docs/cer/backlog.md` carries the Instructions 5 note and is still open, and no other
backlog line changes. The manifest and both pages are byte-identical to `main`.

## Instructions

1. **Placement.** Add `## Claims manifest schema` between the `---` that ends
   `## Deployment` and `## Layer rules`. Open it with two or three sentences. Say that this
   section is the authoritative definition, that the CONTENT specs are its history, and that
   it supersedes CONTENT-030 Instructions 7, with the reason from Context. At the end of the
   existing **Claims manifest.** paragraph, add a sentence naming `§ Claims manifest schema`.
2. **Two tables, parsed by the Tests script.** Both go under their own `###` headings,
   `### Fields` then `### Values`. Put one row per line, with no `|` inside a cell.
   - `| Field | Type | Status | Source | Meaning |`. Field is one backticked path. Use `.`
     for nesting and `[]` for an array element, for example `` `claims[].absent[].symbol` ``.
     Document every level, including `release`, `stamps`, `claims`, `closed` and each
     sub-object.
   - `| Field | Value | Status | Source | Meaning |`. Field is `` `claims[].result` `` or
     `` `claims[].note` `` (for a prefix), and Value is backticked.
   - Status is exactly one of these three:
     - `in use`: it occurs in the live manifest.
     - `retired`: it is absent now but occurs in an earlier committed version.
     - `unexercised`: no committed version has ever held it.
   - Source lists the story IDs that specced it, for example `CONTENT-031, CONTENT-032`.
3. **Meanings. Take them from these specs and nowhere else.** Where a rule is a check a
   spec's Tests ran, state it as the check.
   - **`release`** (030). `repo` is the slug. `commit` is the full 40-hex sha, taken as the
     tip of forqsite's `origin/main` when the release was pinned. `committed` is that
     commit's date and `pinned` is the date it was pinned. `phase-12.md` § Release commit
     mirrors this, and the manifest is the authoritative copy.
   - **`stamps[]`** (030, 032, 035). `id` is `S-NN`.
     - `text` is the exact substring of the page's `bundle-template.py extract` output that
       contains `nullvalues/forqsite@<hex>`. It is not taken from the bundle or the rendered
       DOM, and it may be markup or script source (S-01 contains `<br>`, and S-06 is a JS
       array literal).
     - `commit` is the sha as printed. `date` is ISO, while `text` carries the date in the
       stamp's own format.
     - `scope` records the coverage reading, following CONTENT-030 Instructions 4's
       footer/inline/table-row rules.
     - Invariants: there is one record per stamp occurrence in the template, and every
       stamp is cited by at least one claim. Since CONTENT-032, every `commit` equals
       `release.commit[:8]`.
   - **`claims[]`** (030, 031, 035). `id` is `C-NNN`, and IDs are never reused. `quote` is
     a verbatim substring of the extracted template.
     - Each `evidence[]` entry has a repo-relative `path` and a single-line `symbol` literal
       that `git grep -F` finds in that path at `release.commit`.
     - `stamp` is an `S-` id. The commit and date live only on the stamp.
     - `note` is free text and never names a claim ID.
   - **The Known-gaps claim** (030, 031). It is the one `index.html` claim whose note names
     a `gap-handoff.html` stamp id. Its `evidence` is the deduplicated union of the evidence
     of every claim that cites that stamp. It has no `result`, by design.
   - **`result`** (031, 032, 035). It is the outcome of the re-verification at
     `release.commit` that produced the claim's current stamp, judged against the page as it
     stood before that re-verification.
     - `open`: the quote is unchanged.
     - `changed`: the quote is new, and the note starts `CHANGED:` and gives the old and new
       wording. A claim that had a `MISMATCH:` note became `changed`.
     - `added`: a new GAP entry. The quote is new, the claim has a new `C-` id and the
       footer stamp, and the note starts `ADDED:` and gives the verification date.
     - `unverified`: the note starts `UNVERIFIED:` and gives the reason. `marker` holds an
       on-page phrase that contains "not verified" and is new to the page. The stamp still
       names the release commit.
   - **`MISMATCH:`** (030). The page's implied literal is absent at the release commit. The
     claim cites what the file does contain. It is retired: CONTENT-031 and CONTENT-032
     resolved every one.
   - **`absent[]`** (031). `{path, symbol}` means the path exists at the release commit and
     the literal is not found in it. `{path}` alone means the path does not exist there.
   - **`counts[]`** (032). The number of names in `git ls-tree --name-only <release>
     <path>/` that end in `suffix` equals `n`, which is one directory level. `n` also
     appears in the quote.
   - **`closed_by`** (031). It appears on a live claim that is only partly closed. `commit`
     is a full sha, an ancestor of `release.commit` and not an ancestor of the old stamp's
     commit, and it touches `path`.
   - **`closed[]`** (031). A closed gap's claims move out of `claims` into this array as
     `{id, gap, claim, closed_by: {commit, path}, evidence}`, and the gap is removed from
     both pages.
4. **`### Disagreements and unspecified behaviour`**, a list with one short entry each:
   - `ADDED:` is specced by CONTENT-035 and in use, but CER-045 and this story's own
     Context omit it.
   - CONTENT-030's schema sketch gives `symbol` as "symbol or behaviour", while its Ensures
     require a literal. The manifest follows the literal rule, and so does this reference.
   - No single spec lists all four `result` values. CONTENT-031 allows
     `open`/`changed`/`added`, and CONTENT-032 allows `open`/`changed`/`unverified`.
   - The Known-gaps claim has no `result`. CER-045 records this as a finding, but it is
     specced.
   - CONTENT-030 specs `"evidence": []` with an explanatory note for a claim with no
     findable evidence. No manifest has used it.
   - A `closed[]` record has no `page`, `quote`, `stamp` or `location`.
   - It is not specified what `result` means once a later release commit is pinned and the
     claims are restamped. It is also not specified how a `closed[]` record is checked for
     reopening. The entry says both are decided in INFRA-016's spec, by operator ruling on
     2026-09-29, and names INFRA-016. Do not decide them here.
5. **CER-045 progress note.** In `docs/cer/backlog.md`, append this text to the end of
   CER-045's Finding cell, after `which no manifest has yet exercised.`, with one space
   before it. Change nothing else in the row or the file. Keep the Source, Date and Phase
   cells as they are, and add no resolution marker. The note is the one line in this block,
   backticks included:

   ```text
   Progress (INFRA-015, 2026-09-29): the documentation half is done; `docs/architecture.md` § Claims manifest schema is the schema reference. This row stays open until INFRA-016's fixture tests for the `unverified` marker path and the `closed` array ship.
   ```

Ideology check: this is documentation only. It names no host or path of ours ("Name the
class, not the instance"). Its checks compare the reference to the manifest itself and read
prose whitespace-normalised or through table structure ("Assert the invariant, not a proxy
for it" and its spec-authoring convention). No page changes, so "Zero runtime dependencies"
is untouched.

Preflight note: `INFRA` is this story's rail prefix, as in `INFRA-015` in the CER-045 note,
not a constant in the source tree.

Length: this spec runs past the ~100-line guideline for doc stories. The derived meanings
are the deliverable, and restating them loosely would invite the invented semantics the
stub forbids.

## Tests

The project has no test suite. Save this block to a scratch file outside the repo, then run
it from the repo root with `bash <file>`. It needs no forqsite clone. On `main` before the
edit, checks 1 to 6 each print `FAIL` and the script exits 1. The opening `git diff` guard
and the closing host-path guard (over `docs/architecture.md` and `docs/cer/backlog.md`)
pass on `main` by design.

```bash
set -e
git diff --quiet main -- docs/claims-manifest.json index.html gap-handoff.html
python3 - <<'EOF'
import json, os, re, subprocess
def git(*a): return subprocess.run(['git', *a], capture_output=True, text=True, check=True).stdout
norm = lambda s: re.sub(r'\s+', ' ', s)
arch = open('docs/architecture.md').read()
live = json.load(open('docs/claims-manifest.json'))
hist = [json.loads(git('show', f'{h}:docs/claims-manifest.json'))
        for h in git('log', '--format=%H', 'main', '--', 'docs/claims-manifest.json').split()]
def paths(o, p=''):
    out = set()
    if isinstance(o, dict):
        for k, v in o.items():
            q = f'{p}.{k}' if p else k; out |= {q} | paths(v, q)
    elif isinstance(o, list):
        for x in o: out |= paths(x, p + '[]')
    return out
def values(m):
    v = {('claims[].result', c['result']) for c in m.get('claims', []) if 'result' in c}
    for x in m.get('claims', []) + m.get('closed', []) + m.get('stamps', []):
        k = re.match(r'[A-Z]+:', x.get('note', ''))
        if k: v.add(('claims[].note', k.group(0)))
    return v
LP, HP = paths(live), set().union(*map(paths, hist))
LV, HV = values(live), set().union(*map(values, hist))
status = lambda live_, any_: 'in use' if live_ else 'retired' if any_ else 'unexercised'
m = re.search(r'^## Claims manifest schema\n(.*?)(?=^## )', arch, re.S | re.M)
sec = m.group(1) if m else ''
def table(h):
    s = re.search(rf'^### {h}\n(.*?)(?=^### |\Z)', sec, re.S | re.M)
    return [[c.strip() for c in l.strip().strip('|').split('|')] for l in (s.group(1) if s else '').splitlines() if l.startswith('| `')]
F = {r[0].strip('`'): r for r in table('Fields')}
V = {(r[0].strip('`'), r[1].strip('`')): r for r in table('Values')}
fails = []
def check(name, bad):
    print(('FAIL ' if bad else 'PASS ') + name + (f': {sorted(bad)[:8]}' if bad else ''))
    if bad: fails.append(name)
# 1. every key that occurs in the live manifest, or in any committed version of it, is documented
check('1 every manifest key documented', (LP | HP) - set(F) or ({'no Fields table'} if not F else set()))
# 2. each field's Status matches the manifest history; closed and marker are named unexercised
bad = {f for f, r in F.items() if len(r) != 5 or r[2] != status(f in LP, f in HP)}
bad |= {f for f in ('closed', 'claims[].marker') if F.get(f, [0, 0, ''])[2] != 'unexercised'}
check('2 field status matches manifest history', bad)
# 3. every specced or observed result value and note prefix is documented, with its true status
REQ = {('claims[].result', v) for v in ('open', 'changed', 'added', 'unverified')} | \
      {('claims[].note', v) for v in ('CHANGED:', 'ADDED:', 'MISMATCH:', 'UNVERIFIED:')}
bad = (REQ | LV | HV) - set(V)
bad |= {k for k, r in V.items() if len(r) != 5 or r[2] != status(k in LV, k in HV)}
check('3 enum values documented with true status', bad)
# 4. provenance: each row cites a spec that names the field's leaf key or the value
def cited(r, token):
    ids = re.findall(r'CONTENT-\d{3}', r[3]) if len(r) == 5 else []
    texts = [open(f'docs/stories/CONTENT/{i}.md').read() for i in ids if os.path.exists(f'docs/stories/CONTENT/{i}.md')]
    return ids and len(texts) == len(ids) and any(token in t for t in texts) and r[4]
bad = {f for f, r in F.items() if not cited(r, f.split('.')[-1].replace('[]', ''))}
bad |= {k for k, r in V.items() if not cited(r, k[1])}
check('4 every row cites a spec that names it', bad or ({'no rows'} if not (F and V) else set()))
# 5. the pointer, and the recorded disagreements (whitespace-normalised, CER-011)
cm = re.search(r'\*\*Claims manifest\.\*\*(.*?)\n\n', arch, re.S)
bad = set() if cm and '§ Claims manifest schema' in norm(cm.group(1)) else {'pointer'}
d = re.search(r'^### Disagreements and unspecified behaviour\n(.*?)(?=^### |\Z)', sec, re.S | re.M)
dn = norm(d.group(1)) if d else ''
bad |= {a for a in ('ADDED:', 'symbol or behaviour', 'Known-gaps claim', '"evidence": []', 'CONTENT-030',
                     'not specified', 'INFRA-016') if a not in dn}
check('5 pointer and disagreements recorded', bad)
# 6. CER-045 carries the progress note, stays open, and is the only backlog change
NOTE = ("Progress (INFRA-015, 2026-09-29): the documentation half is done; `docs/architecture.md` § Claims "
        "manifest schema is the schema reference. This row stays open until INFRA-016's fixture tests for the "
        "`unverified` marker path and the `closed` array ship.")
MARK = re.compile(r'(?:^|\|\s*|[.!?]\s+|\*\*|\(|\[)(resolved|superseded|obsolete)\b', re.I)
old, new = git('show', 'main:docs/cer/backlog.md').splitlines(), open('docs/cer/backlog.md').read().splitlines()
is045 = lambda l: l.startswith('| CER-045 ')
cell = lambda l: l.split('|', 2)[2].rsplit('|', 4)[0].strip()
bad = set()
if len(old) != len(new) or any(a != b for a, b in zip(old, new) if not is045(a)): bad.add('a backlog line other than CER-045 changed')
o, n = [l for l in old if is045(l)], [l for l in new if is045(l)]
if len(o) != 1 or len(n) != 1: bad.add('CER-045 row not found once')
else:
    oc, nc = cell(o[0]), cell(n[0]); added = nc[len(oc):]
    if not nc.startswith(oc) or norm(added).strip() != norm(NOTE): bad.add('progress note missing or not appended verbatim')
    if n[0].split('|')[-4:] != o[0].split('|')[-4:]: bad.add('Source/Date/Phase changed')
    if MARK.search(added): bad.add('note closes the row')
check('6 CER-045 progress note is the only backlog change', bad)
print('FAILED:', fails) if fails else print('OK')
raise SystemExit(1 if fails else 0)
EOF
if git diff main -- docs/architecture.md docs/cer/backlog.md | grep '^+' | grep -nE '/mnt/|/home/|~/'; then exit 1; fi
echo DONE
```

Pass means six `PASS` lines, then `OK` and `DONE`, and exit 0. The spec-writer confirmed
the failing run on `main`, and confirmed a pass against a mock section and the CER-045 note
in a throwaway clone.
The reviewer also reads each Meaning cell against the cited spec's own wording. A test can
prove that a row cites a spec that names the field. It cannot prove that the meaning was
copied rather than invented.

## Out of scope

- The stale-claim checker, its fixture tests for the `unverified` and `closed` paths (the
  other half of CER-045), and any decision left open in Instructions 4. All of these are
  INFRA-016's.
- Resolving CER-045, or changing any backlog line other than the Instructions 5 note. The
  row stays open until its fixture half ships.
- Any change to `docs/claims-manifest.json`, either page, or a CONTENT spec, including
  fixing a disagreement this story records.
- A JSON Schema file or other machine-readable schema artifact.
- Command blocks in the manifest (CER-046, deferred to Phase 14).
