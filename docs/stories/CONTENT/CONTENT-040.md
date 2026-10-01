---
id: CONTENT-040
rail: CONTENT
title: Close GAP-006 at cp-PM105-main
status: planned
phase: "14"
story_class: content
auth_gated: false
schema_introduces: false
primary_files:
  - docs/claims-manifest.json

touches:
  - gap-handoff.html
  - index.html
  - README.md
  - docs/cer/backlog.md
  - docs/architecture.md

narrative_roles: []
---

## Context

forqsite `8112020ec1d92e1bdd84cd86ffe3a90fd967c125` (2026-09-24, in `cp-PM105-main`)
replaced firstrun.sh step 7.5's inline grep with `scripts/lib/check-required-env.sh`. That
helper treats an empty or whitespace-only value as missing, and
`tests/repo/firstrun-required-vars.test.ts` covers it. Both Phase 14 planners verified this.

**Operator ruling 2026-09-30: close the gap in full.** GAP-006's third acceptance test asked
for "a tests/ or CI shellcheck step". The tests/ half is met, and the closed record says so
through its two `tests/repo/firstrun-required-vars.test.ts` evidence literals.

**Operator ruling 2026-10-01.** The unprefixed notes on C-039, C-040, C-041 and C-043 say
"Verified at the release commit on 2026-09-30". Rewrite them to name `1fda3228` explicitly, so
they stay true after any restamp, and sweep every other claim note for the same phrasing.

The fix is not an ancestor of the current pin, `1fda3228`. So this story's content targets
`cp-PM105-main` and ships only through the release job.
- **What the story does.** It moves GAP-006's claim (C-026) to `closed[]`, removes the gap
  from `gap-handoff.html`, and fixes all **three** of its mentions in `index.html`: a
  setup-route note, a pipeline step drawn as bad, and a ledger row. It recomputes the
  Known-gaps union, updates the README item count, and rewrites the notes.
- **The post-merge step** is the first real attended release, through `release.sh`
  (INFRA-021).
- **Not here.** The other gap-status mentions outside the manifest are CER-056 (Phase 15).

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent
planner drafts (docs/phases/phase-14.md).

**Spec-time findings (2026-10-01).** These were measured against main `a3881a7`, a forqsite
clone, and a throwaway copy with every edit below applied.
- **Merge happens at the old pin; release moves it.**
  - At the target, the checker on the edited manifest exits 0:
    `summary: 42 claims: 23 untouched, 19 holds, 0 stale, 0 unverified; 1 closed records: 1 closed, 0 reopened`.
    Unedited, it exits 3, because C-001 and C-026 are stale on the old step 7.5 line.
  - At `1fda3228` the same manifest reports C-026 `reopened`, because the fix is not there.
    That is expected, and nothing runs the checker at the pin.
  - Restamp's derivation was simulated against the `cp-13` pages. Its rules (INFRA-020
    Instruction 4) give 42 claims: 40 open, 1 changed (C-042), 0 added, 0 unverified.
    `restamp.py` itself is not merged yet.
- **None of the edited text sits inside a claim quote.** Every remaining quote occurs as
  often as before. So no live claim becomes `changed`. INFRA-020's Context guessed
  otherwise.
- **`closed_by` ancestry.** `8112020e` is an ancestor of `94f5c339` (`cp-PM105-main`) and not
  of `1fda3228`.
  - `docs/architecture.md`'s `closed[].closed_by.commit` row requires only a full sha. The
    ancestor rule there belongs to the live-claim row.
  - CONTENT-031, which defined `closed[]`, required "an ancestor of the release commit". It
    also required evidence "at the release commit".
  - So between this merge and the release, the record is ahead of its own pin. This breaks
    CONTENT-031's rule, though not a schema row, and the window closes when the release lands.
  - `stale-claims.py` never reads `closed_by`. `restamp.py` leaves `closed_by` and `closed[]`
    alone, and requires only checker exit 0 at the target. Neither refuses this state.
  - The story records the ruling in architecture.md (Instruction 5). This is why
    `docs/architecture.md` was added to `touches:`.
- **The schema's `closed` rows say `unexercised`, and "No manifest has used it yet."** Both
  go false at merge, because status is measured against git history. Instruction 5 fixes
  them.

## Requires

- CONTENT-039 is merged: C-039 to C-043 are in the manifest. This holds on main.
- INFRA-020 is merged before building, so Tests step 7 runs restamp's dry run. Without it the
  step prints `SKIP`, and Post-merge step 2 runs the same check.
- INFRA-021 must be merged before the post-merge release, but not before building.
- `FORQSITE_CLONE` names a forqsite clone in which `cp-PM105-main` is `94f5c339`. It is given
  on the command line and never written into the repo.

## Ensures

The Tests block below prints `OK` and `ALL-OK`, with no `SKIP` once INFRA-020 has merged.
- **Manifest.** C-026 is moved to `closed[]` exactly as Instruction 1 gives it, with evidence
  found at `cp-PM105-main` and absent at `1fda3228`. The pin, stamps and quotes are
  unchanged. C-001's evidence is the S-07 union. Exactly the nine swept notes changed, and
  each now names `1fda3228`.
- **Checker.** It exits 0 at `cp-PM105-main` with the summary above.
- **Templates.** Neither holds any GAP-006 text, and the index ledger matches the
  gap-handoff list.
- **Docs.** The README, backlog and architecture edits are in place.

## Instructions

Edit the bundles only through `docs/architecture.md` § Editing procedure: run `extract` into
a scratch directory, edit the template, then run `inject` and `verify`. Write the manifest
as `json.dumps(m, indent=2, ensure_ascii=False) + '\n'`. Change nothing not listed here.

1. **`closed[]` (manifest).**
   - Remove C-026 from `claims`, keeping the others in order.
   - Add a top-level `closed` key after `claims`, holding exactly one record, with keys in
     this order. `claim` is C-026's `claim` string, verbatim.
     ```json
     {"id": "C-026", "gap": "GAP-006", "claim": "<C-026's claim, verbatim>",
      "closed_by": {"commit": "8112020ec1d92e1bdd84cd86ffe3a90fd967c125", "path": "scripts/firstrun.sh"},
      "evidence": [
       {"path": "scripts/firstrun.sh", "symbol": "done < <(bash \"${SCRIPT_DIR}/lib/check-required-env.sh\" .env.local \"${REQUIRED_KEYS[@]}\" || true)"},
       {"path": "scripts/firstrun.sh", "symbol": "fail \"${var} is missing or empty in .env.local\""},
       {"path": "scripts/lib/check-required-env.sh", "symbol": "line=$(grep \"^${key}=\" \"$envfile\" 2>/dev/null | tail -n 1 || true)"},
       {"path": "scripts/lib/check-required-env.sh", "symbol": "value=\"${value#\"${value%%[![:space:]]*}\"}\""},
       {"path": "tests/repo/firstrun-required-vars.test.ts", "symbol": "it('reports MISSING for `K=` (empty value)', () => {"},
       {"path": "tests/repo/firstrun-required-vars.test.ts", "symbol": "it('reports MISSING for `K=   ` (whitespace-only value)', () => {"}
      ]}
     ```
     The whitespace-only literal has three spaces after `K=`. Each literal was confirmed
     with `git grep -F` at `cp-PM105-main` and is absent at `1fda3228`. Confirm them
     yourself.
   - **Known-gaps union.** Rebuild C-001's `evidence` as the deduplicated union of every
     remaining S-07 claim's evidence. Keep the existing order, and only drop pairs. Today
     that drops exactly the two `scripts/firstrun.sh` pairs only C-026 cited, leaving 48.

2. **Note sweep (manifest).** These are exact substring replacements. Each `old` occurs once
   in that claim's note. No other note, and no other field, changes.
   - **C-039, C-040, C-041 and C-043.** `<X>` is `block`, `block`, `paragraph` and `step`
     respectively.
     - Replace: `Verified at the release commit on 2026-09-30, when this <X> was brought under the section's stamp; the stamp's printed date, 2026-09-24, is the earlier verification of the claims it already covered.`
     - With: `Verified at forqsite commit 1fda3228 on 2026-09-30, when this <X> was brought under the section's stamp; that stamp then printed 2026-09-24, the date the claims it already covered were verified.`
   - **C-042.**
     - Replace `at the release commit the operator runbook's` with
       `at forqsite commit 1fda3228 the operator runbook's`.
     - Replace `Verified on 2026-09-30; the stamp's printed date, 2026-09-24, is the earlier verification of the claims it already covered.`
       with `Verified at forqsite commit 1fda3228 on 2026-09-30; the section's stamp then printed 2026-09-24, the date the claims it already covered were verified.`
   - **C-022.**
     - Replace `Re-checked at the release commit as` with
       `Re-checked at forqsite commit 1fda3228 as`.
     - Replace `unchanged in count since the previous stamp's commit,` with
       `unchanged in count between forqsite commits 17b78645 and 1fda3228,`.
       `17b78645` is S-05's commit in CONTENT-030's manifest. The runbook has 5 `docker`
       lines at both commits.
   - **C-002.** Replace `at the release commit that directory holds` with
     `at forqsite commit 1fda3228 that directory holds`.
   - **C-037 and C-038.**
     - Replace `ADDED: verified at the release commit on 2026-09-25` with
       `ADDED: verified at forqsite commit 1fda3228 on 2026-09-25`.
     - Replace the footer clause. In C-037 it is
       `the footer stamp's printed date, 24 september 2026, is the earlier verification of the entries it already covered.`
       and in C-038 it begins with a capital `The`. Replace it with
       `the footer stamp then printed 24 september 2026, the date the entries it already covered were verified.`,
       keeping the same capitalisation.

   **Why "printed date" goes too.** Once restamped, a stamp prints the release date, so "the
   stamp's printed date, 2026-09-24" would become false.

   **Why prefixed notes are swept.** The release will delete the prefixed notes of C-002,
   C-037 and C-038 anyway, because their quotes are unchanged since cp-13 (INFRA-020
   Instruction 4). They are swept regardless, so no note anywhere says "the release commit".

3. **`index.html` template**, three edits.
   - **Setup route** (the note after the firstrun re-run).
     - Before: `step 7.5 confirms required variables. <sc-if value="{{ gaps }}"><span>Note: the check has a shell-precedence bug and passes present-but-empty keys (GAP-006).</span></sc-if></div>`
     - After: `step 7.5 confirms required variables.</div>`
   - **Pipeline**, STAGE 02.
     - Before: `{ label: 'firstrun 7.5 required-var check', dot: bad, gap: 'GAP-006' },`
     - After: `{ label: 'firstrun 7.5 required-var check', dot: ok, gap: null },`
   - **Ledger.** Delete the whole line
     `{ id: 'GAP-006', pri: 'P2', priColor: P2, sum: 'firstrun.sh 7.5 shell-precedence bug: present-but-empty keys report as set — defeating the check\'s purpose.' },`
     including its leading indentation and newline.

4. **`gap-handoff.html` template.**
   - Delete the `mk('GAP-006', …)` entry. That is every line from `      mk('GAP-006'` up to,
     but not including, `      mk('GAP-007'`, the trailing blank line included.
   - Intro: `eleven of them,` becomes `ten of them,`.
   - TL;DR: `<strong>006, 008 and 013 whenever</strong>` becomes
     `<strong>008 and 013 whenever</strong>`.
   - Chip: `P2 — DATA-SAFETY / CORRECTNESS / TOIL × 5` becomes `… × 4`.
   - Leave every stamp alone. `release.sh` restamps them.

5. **Docs.**
   - **README.md**, in the `gap-handoff.html` row: `(GAP-003…010, 8 items)` becomes
     `(10 items, GAP-003 to GAP-014; a closed gap's number is never reused)`.
   - **docs/cer/backlog.md**, CER-056. Append this after `alongside CER-046.` in the Finding
     cell:
     `**Phase 14, CONTENT-040: the three GAP-006 mentions were removed when that gap closed; the class remains open for Phase 15.**`
     This is not a resolution marker, and CER-056 stays open.
   - **docs/architecture.md**, § Claims manifest schema.
     - In the intro, `never contained (`closed`, `marker`,` becomes `never contained (`marker`,`.
     - In all eight `closed…` Fields rows, `unexercised` becomes `in use`.
     - In the `closed` row, drop ` No manifest has used it yet.` and add `CONTENT-040` to its
       Source.
     - In the `closed[].closed_by.commit` row, extend the Meaning to:
       `The closing commit, a full sha. It is an ancestor of the `release.commit` the record is published with, and not an ancestor of the commit of the stamp the gap was listed under. A review story may merge the record while the pin still predates it, when the release that moves the pin is its post-merge step; until that release lands, the record holds only at the release target (CONTENT-040).`

Ideology, checked with no conflict.
- **Generated-artifact discipline.** The bundles change only through `bundle-template.py`
  in the reviewed loop (the Phase 2 exception).
- **Cite the source.** The closed record keeps checkable forqsite literals.
- **Assert the invariant.** Evidence must hold at the target and be absent at the old pin,
  so it shows the fix rather than surviving context.
- **Name the class.** No clone path, host or URL is written anywhere.

Length: past the baseline. Every edit is a published-text or manifest literal the builder
must not guess, and the post-merge release is this phase's proof. Spec-preflight flags
`MISSING` and `REQUIRED_KEYS`, which are forqsite literals inside the evidence, and `SKIP`,
which is this block's own output word. All three are intentional.

## Tests

Run from the repo root with `FORQSITE_CLONE=<clone path> bash <this block>`. On main
`a3881a7` it printed `49 failed` and exited 1. On a throwaway copy with the edits above, it
printed `OK`, then the `SKIP` (no `restamp.py` yet), then `ALL-OK`. Step 7 checks
restamp's result through its exact summary line. It is not a whole-line `git diff` scan.

```bash
set -euo pipefail
: "${FORQSITE_CLONE:?set FORQSITE_CLONE to a local forqsite clone that has cp-PM105-main}"
cd "$(git rev-parse --show-toplevel)"
BASE=25c2e6621e9dfa1d39e68efaf0e08ba90e28dc8c   # last commit to change the manifest or either bundle
S=$(mktemp -d); trap 'rm -rf "${S:?}"' EXIT
for p in index.html gap-handoff.html; do
  python3 scripts/bundle-template.py verify "$p" > /dev/null
  python3 scripts/bundle-template.py extract "$p" "$S/$p" > /dev/null
  python3 -c "import re,sys; [open(f'{sys.argv[2]}.{i}.js','w').write(s) for i,s in enumerate(re.findall(r'<script type=.text/x-dc.[^>]*>(.*?)</script>', open(sys.argv[1]).read(), re.S))]" "$S/$p" "$S/js-$p"
  for f in "$S/js-$p".*.js; do node --check "$f"; done
  git show "$BASE:$p" > "$S/base-$p"; python3 scripts/bundle-template.py extract "$S/base-$p" "$S/base.$p" > /dev/null
done
git show "$BASE:docs/claims-manifest.json" > "$S/base-manifest.json"
set +e
python3 scripts/stale-claims.py --no-commits --manifest docs/claims-manifest.json cp-PM105-main > "$S/check.out" 2>&1; echo $? > "$S/check.rc"
set -e
python3 - "$S" <<'EOF'
import json, os, re, subprocess, sys
S = sys.argv[1]; clone = os.environ['FORQSITE_CLONE']; F = []
def need(ok, msg):
    if not ok: F.append(msg)
def git(*a): return subprocess.run(['git', '-C', clone, *a], capture_output=True, text=True, errors='replace')
OLD, FIX = '1fda3228322d5ad779f44c321c4013ccd247b3fa', '8112020ec1d92e1bdd84cd86ffe3a90fd967c125'
TGT = git('rev-parse', 'cp-PM105-main^{commit}').stdout.strip()
need(TGT == '94f5c339c085869c390d92f567461185b03f1bea', 'cp-PM105-main is not 94f5c339 in this clone')
m = json.load(open('docs/claims-manifest.json')); b = json.load(open(f'{S}/base-manifest.json'))
T = {p: open(f'{S}/{p}').read() for p in ('index.html', 'gap-handoff.html')}
need(m['release'] == b['release'] and m['stamps'] == b['stamps'], 'release pin or a stamp changed')
need(open('docs/claims-manifest.json').read() == json.dumps(m, indent=2, ensure_ascii=False) + '\n', 'manifest serialisation changed')
ids = [c['id'] for c in m['claims']]
need('C-026' not in ids and ids == [c['id'] for c in b['claims'] if c['id'] != 'C-026'], 'C-026 not moved out of claims, or claims reordered')
# 1. the closed record
cl = m.get('closed', [])
need(len(cl) == 1, 'closed[] does not hold exactly one record')
x = cl[0] if cl else {}
need(list(x) == ['id', 'gap', 'claim', 'closed_by', 'evidence'], f'closed record keys {list(x)}')
need(x.get('id') == 'C-026' and x.get('gap') == 'GAP-006', 'closed record id/gap')
need(x.get('claim') == next(c['claim'] for c in b['claims'] if c['id'] == 'C-026'), 'closed record claim is not C-026\'s claim')
need(x.get('closed_by') == {'commit': FIX, 'path': 'scripts/firstrun.sh'}, 'closed_by')
need(git('merge-base', '--is-ancestor', FIX, TGT).returncode == 0, 'closer not an ancestor of the target')
need(git('merge-base', '--is-ancestor', FIX, OLD).returncode == 1, 'closer is an ancestor of the old pin')
need('scripts/firstrun.sh' in git('show', '--name-only', '--format=', FIX).stdout.split(), 'closer does not touch its path')
ev = x.get('evidence', [])
need(len(ev) == 6 and len({(e['path'], e['symbol']) for e in ev}) == 6, 'closed evidence is not six distinct literals')
for e in ev:
    need(git('grep', '-q', '-F', '-e', e['symbol'], TGT, '--', e['path']).returncode == 0, f"not at target: {e['path']}: {e['symbol']}")
    need(git('grep', '-q', '-F', '-e', e['symbol'], OLD, '--', e['path']).returncode != 0, f"already at the old pin: {e['path']}: {e['symbol']}")
need(not re.search(r'/mnt/|/home/|~/|https?://', json.dumps(x)), 'closed record names a host or local path')
# 2. checker at the target
rc = open(f'{S}/check.rc').read().strip(); out = open(f'{S}/check.out').read()
need(rc == '0', f'checker exit {rc} at cp-PM105-main')
need('summary: 42 claims: 23 untouched, 19 holds, 0 stale, 0 unverified; 1 closed records: 1 closed, 0 reopened' in out, 'checker summary')
need(re.search(r'^C-026 closed  gap GAP-006$', out, re.M), 'C-026 not closed in checker output')
# 3. Known-gaps union
key = lambda e: (e['path'], e['symbol'])
kg = next(c for c in m['claims'] if c['id'] == 'C-001'); bkg = next(c for c in b['claims'] if c['id'] == 'C-001')
u = {key(e) for c in m['claims'] if c['stamp'] == 'S-07' for e in c['evidence']}
got = [key(e) for e in kg['evidence']]
need(len(got) == len(set(got)) and set(got) == u, 'Known-gaps evidence is not the S-07 union')
need(got == [key(e) for e in bkg['evidence'] if key(e) in u], 'Known-gaps evidence reordered')
need(not any(p == 'scripts/firstrun.sh' and ('|| true | cut' in s or '7.5' in s) for p, s in got), 'GAP-006 evidence left in the union')
# 4. notes: only the swept notes change, and every one names the old pin
SWEPT = {'C-002', 'C-022', 'C-037', 'C-038', 'C-039', 'C-040', 'C-041', 'C-042', 'C-043'}
bc = {c['id']: c for c in b['claims']}
for c in m['claims']:
    o = bc[c['id']]
    rest = lambda d: {k: v for k, v in d.items() if k not in ('note', 'evidence' if c['id'] == 'C-001' else '')}
    need(rest(c) == rest(o), f"{c['id']}: changed outside note")
    n = c.get('note', '')
    need((n != o.get('note', '')) == (c['id'] in SWEPT), f"{c['id']}: note changed = {n != o.get('note', '')}")
    need(not re.search(r"the release commit|printed date|previous stamp's commit|\bC-\d+", n), f"{c['id']}: note still says 'the release commit', a printed date, or a claim id")
    if c['id'] in SWEPT: need('1fda3228' in n and not re.search(r'/mnt/|/home/|~/|https?://', n), f"{c['id']}: note does not name 1fda3228")
# 5. pages: GAP-006 gone from both templates, lists consistent
W = r"GAP-006|gap-006|shell-precedence|present-but-empty|pipes cut from true|\b006\b"
for p, t in T.items(): need(not re.search(W, t), f'{p}: GAP-006 text remains: {re.findall(W, t)[:3]}')
need("{ label: 'firstrun 7.5 required-var check', dot: ok, gap: null }," in T['index.html'], 'pipeline step not ok')
need('step 7.5 confirms required variables.</div>' in T['index.html'], 'setup-route note not removed cleanly')
gh = re.findall(r"mk\('(GAP-\d+)'", T['gap-handoff.html'])
need(gh == re.findall(r"\{ id: '(GAP-\d+)'", T['index.html']), 'index ledger differs from gap-handoff list')
need(len(gh) == 10 and 'ten of them,' in T['gap-handoff.html'] and 'eleven' not in T['gap-handoff.html'], 'gap count wording')
pri = re.findall(r"mk\('GAP-\d+', '(P\d)'", T['gap-handoff.html'])
for p, k in re.findall(r'(P\d) — [^<×]*× (\d+)', T['gap-handoff.html']): need(pri.count(p) == int(k), f'{p} chip count')
need('<strong>008 and 013 whenever</strong>' in T['gap-handoff.html'], 'TL;DR bullet')
for p, t in T.items():
    for c in m['claims']:
        if c['page'] == p: need(t.count(c['quote']) == open(f'{S}/base.{p}').read().count(c['quote']), f"{c['id']}: quote count changed")
# 6. docs (whitespace-normalised, CER-011)
norm = lambda s: re.sub(r'\s+', ' ', s)
r = [l for l in open('README.md') if l.startswith('| `gap-handoff.html` |')]
need(len(r) == 1 and "(10 items, GAP-003 to GAP-014; a closed gap's number is never reused)" in r[0], 'README item count')
row = [l for l in open('docs/cer/backlog.md') if l.startswith('| CER-056 |')]
need(len(row) == 1 and 'the class remains open for Phase 15.**' in row[0] and not re.search(r'(^|\| |\*\*|[.!?] )(resolved|superseded|obsolete)', row[0], re.I), 'CER-056 annotation')
a = open('docs/architecture.md').read(); rows = [l for l in a.splitlines() if l.startswith('| `closed')]
need(len(rows) == 8 and all('| in use |' in l for l in rows) and 'No manifest has used it yet' not in a, 'closed[] schema rows not in use')
need('never contained (`marker`,' in norm(a), 'schema intro still lists closed as never contained')
need(any(l.startswith('| `closed[].closed_by.commit` |') and 'post-merge step' in l and 'CONTENT-040' in l for l in rows), 'closed_by.commit row lacks the ancestry timing')
for f in F: print('FAIL:', f)
print('OK' if not F else f'{len(F)} failed'); sys.exit(1 if F else 0)
EOF
# 7. restamp would succeed at the target (needs INFRA-020's restamp.py)
if [ -f scripts/restamp.py ]; then
  git clone -q . "$S/fh"
  cp docs/claims-manifest.json "$S/fh/docs/"; cp index.html gap-handoff.html "$S/fh/"
  git -C "$S/fh" -c user.name=t -c user.email=t@example.invalid commit -qam scratch --allow-empty
  git -C "$S/fh" tag -d rel-1fda3228 > /dev/null 2>&1 || true
  git -C "$S/fh" -c user.name=t -c user.email=t@example.invalid tag -a -m bootstrap rel-1fda3228 'cp-13^{commit}'
  D=$(date +%F)
  python3 "$S/fh/scripts/restamp.py" --dry-run --date "$D" cp-PM105-main > "$S/r.out"
  grep -qxF "restamp: nullvalues/forqsite 1fda3228 -> 94f5c339 on $D: 42 claims: 40 open, 1 changed, 0 added, 0 unverified (dry run; nothing written)" "$S/r.out"
else
  echo 'SKIP: scripts/restamp.py is not merged; Post-merge step 2 runs this check'
fi
echo ALL-OK
```

**Acceptance.** `OK` and `ALL-OK`, exit 0, and no `SKIP` once INFRA-020 has merged. The
whole `scripts/*-selftest.sh` loop from CLAUDE.md stays green. The reviewer also reads the
closed record's six literals in the clone at `cp-PM105-main`, and confirms they show the
empty-value fix and the tests/ coverage.

## Post-merge (orchestrator + operator)

This is the first attended release. The orchestrator runs it, and the operator gives each go.
Use the clone through `FORQSITE_CLONE` only. Do not run `deploy.sh` by hand between this
merge and the release: main's pages drop GAP-006 while their stamps still name `1fda3228`.

1. **Gate. Stop if any of these fails.**
   - `scripts/restamp.py` and `scripts/release.sh` are on main, so INFRA-020 and INFRA-021
     are merged.
   - The annotated `rel-1fda3228` tag exists locally at `cp-13^{commit}`, and
     `git ls-remote origin refs/tags/rel-1fda3228` shows the same object. It is pushed only
     with the operator's approval (INFRA-020 Instruction 7).
   - The operator has said go.
2. **Re-run this story's Tests block on main.** Expect `ALL-OK` with no `SKIP`. The restamp
   line must read
   `restamp: nullvalues/forqsite 1fda3228 -> 94f5c339 on <date>: 42 claims: 40 open, 1 changed, 0 added, 0 unverified (dry run; nothing written)`.
3. **Dry run:** `scripts/release.sh --latest-checkpoint`. Expect exit 0 with these lines:
   - `release: target cp-PM105-main (94f5c339)`;
   - restamp's dry-run line as above;
   - `release: would commit: release: nullvalues/forqsite@94f5c339, 42 claims: 23 untouched, 19 holds, 0 unverified`.

   Show the operator any `ahead of origin` listing. **If the target is a newer checkpoint
   than `cp-PM105-main`, stop and ask.** This story was verified only at `cp-PM105-main`.
   `scripts/release.sh cp-PM105-main` is the fallback, used only on the operator's word.
4. **Release, on the operator's go:** `scripts/release.sh --yes --latest-checkpoint`, or the
   explicit target agreed in step 3. Expect exit 0, the commit, the annotated `rel-94f5c339`
   tag, then the deploy, the drift check and the push.
5. **After.**
   - The manifest's `release.commit` is `94f5c339c085869c390d92f567461185b03f1bea`, and
     every stamp names `94f5c339` with the run date.
   - `stale-claims.py --no-commits cp-PM105-main` exits 0 with
     `42 claims: 42 untouched, 0 holds, 0 stale, 0 unverified; 1 closed records: 1 closed, 0 reopened`.
   - `8112020e` is now an ancestor of `release.commit`, so CONTENT-031's rule holds.
6. **On any stop,** follow the recovery lines `release.sh` prints, and nothing else.
   - **Exit 3** means a claim went stale. That needs a new review story, not a hand edit.
   - **Exit 16** is the operator's call (`deploy.sh --rollback` is printed, never run).

## Out of scope

- The other gap-status mentions outside the manifest, and bringing them under it (CER-056,
  Phase 15).
- Restamping, deploying, tagging or pushing inside the story. That is the post-merge
  release, and the builder never runs `release.sh --yes` or creates any tag.
- An `absent` check on the old step 7.5 line in the closed record. The schema has no
  `closed[].absent` row, and evidence alone decides reopening.
- A `note` field on `closed[]`. The tests/ half of the acceptance test is recorded through
  the test-file evidence.
- Other stale gap counts outside the touched files (e.g. the `GAP-002…011` remark in
  `docs/ideology.md`), and `docs/checkpoints.md`'s dated records.
- Rewording any note beyond the listed replacements, and command-block coverage (Phase 15).
