---
id: CONTENT-042
rail: CONTENT
title: Review the stale claims at the newest forqsite checkpoint, then release
status: planned
phase: "15"
story_class: content
auth_gated: false
schema_introduces: false
primary_files:
  - docs/claims-manifest.json

touches:
  - index.html
  - gap-handoff.html
  - docs/cer/backlog.md
  - README.md
  - docs/architecture.md

narrative_roles: []
---

## Context

The site is pinned to forqsite `94f5c339` (`cp-PM105-main`). The target is `cp-PM107-main`,
which is `afed86a735c8d171be5ee42ce58fee5b7ea25e37`, 108 commits later. At that target
`stale-claims.py` finds 5 stale claims:
- C-001, the Known-gaps union;
- C-005, where the `invalid_data` return gained fields;
- C-022, C-024 and C-025, because forqsite restructured its deployment.

**What forqsite now does.** Measured at `cp-PM107-main`:
- `b2f0712d` (INFRA-065) added a `Dockerfile` for one production image, which defaults to
  port 3000 through `PORT`.
- `f316120f` (INFRA-066) made these changes:
  - deleted `docker-compose.yml` and `docs/deployment/Caddyfile.example`;
  - rewrote `docs/deployment/docker-compose.rolling.yml` to run a digest-pinned
    `FORQSITE_IMAGE` on the `edge` network, with no build step;
  - made `scripts/rolling-restart.sh -f <compose> <digest>` take the compose file as an
    argument and drive `docker compose` only.
- `87c200ba` (INFRA-067) added `scripts/r1-build.sh`, which builds an image from a commit plus
  an overlay so that its digest can be promoted.
- What is unchanged:
  - forqsite's `docs/architecture.md` still says "Single-instance, maintenance-window installs
    remains the **default**" and keeps the rolling restart opt-in;
  - the runbook's §2.7 checkout path listens on 6020, and §12.1 still restarts it with a
    process manager;
  - `docs/first-run.md` still says `:3000` (lines 165, 267-268, 278 and 327-330).

**Operator rulings, 2026-10-05.**
1. **Option A.** The site keeps documenting forqsite's default single-instance, non-docker
   path. Correct every fact about forqsite, then release. Add one sentence that names
   forqsite's opt-in Docker rolling pair and points to its runbook §12.2. Add no Docker route.
2. **GAP-004 is "Closed, superseded".**
   - Its `closed[]` record carries `closed_by` `f316120f`, plus `b2f0712d` for the
     Dockerfile.
   - Its note says the problem no longer exists because forqsite took the opposite approach.
   - It never presents the site's proposed fix as done.
   - The schema has no `closed[].note` row yet, so this story adds one to
     `docs/architecture.md`. That is why `README.md` and `docs/architecture.md` joined
     `touches:`.

**Before the build, show the operator** the drafted TL;DR bullet 1 (Instruction 3) and the
GAP-004 note (Instruction 1).

Depends on CONTENT-041, which is merged. Its edits ship in this release. The operator ruled
for a short spec with no proving pass.

**Length.** This spec runs past the baseline. Every edit is a published-text or manifest literal
the builder must not guess, and the release is the phase's proof. Spec-preflight flags `/api/health`,
`CMD`, `COMPOSE_FILE`, `FORQSITE_IMAGE`, `PORT`, `PM107`, `BLOCKS`, `PROD` and `TLS`. All of
them are forqsite literals or page text, so the flags are intentional.

## Requires

- CONTENT-041 is merged.
- `scripts/restamp.py` and `scripts/release.sh` are on main.
- The annotated tag `rel-94f5c339` exists. It peels to `d4c3991`.
- `FORQSITE_CLONE` names a forqsite clone in which `cp-PM107-main` is `afed86a7`.
  - Pass it on the command line only. Never write a path, host or URL into the repo.
  - The operator fetches. The job never fetches.

## Ensures

The Tests block prints `OK` and then `ALL-OK`. That means:
- the checker exits 0 at `cp-PM107-main` with
  `summary: 42 claims: 21 untouched, 21 holds, 0 stale, 0 unverified; 2 closed records: 2 closed, 0 reopened`;
- both bundles verify;
- every old sentence below is gone, and every new one is present (whitespace-normalised);
- restamp's dry run predicts `38 open, 2 changed, 1 added`.

## Instructions

Edit the bundles only through `docs/architecture.md` § Editing procedure: `extract` into a
scratch directory, edit the template, then `inject` and `verify`.

Write the manifest as `json.dumps(m, indent=2, ensure_ascii=False) + '\n'`. Change nothing not
listed here. Leave every stamp alone, because `release.sh` restamps them. Below, `M` stands for
the existing mono span: `<span style="font-family:'Geist Mono',monospace; font-size:12.5px;">`.

1. **Manifest.** Confirm each literal yourself with `git grep -F` at `cp-PM107-main`.
   - **C-005.** Change only the evidence symbol `return { ok: false, error: 'invalid_data', detail }`.
     It becomes `return { ok: false, error: 'invalid_data', detail, blockType: block.type, blockIndex: index }`
     (block-registry/index.ts:515, from `d311d837`). The quote is unchanged, and `result` stays `open`.
   - **C-022**, rewritten as the site's own premise:
     - `claim`: `The gap ordering assumes the reader runs forqsite's default single-instance install, not docker, with network Postgres and MinIO.`
     - `quote`: `Ordering assumes you run forqsite's default single-instance install`
     - `evidence`: drop the `docker-compose.yml` pair. Append
       `{"path": "docs/operator-runbook.md", "symbol": "For a single instance run from a checkout (§ 2.7):"}`.
     - `absent`: drop the `Dockerfile` entry.
     - `result`: `changed`.
     - `note`, which replaces the old note:
       `CHANGED: was "Ordering assumes production stays non-docker: network Postgres and MinIO, with compose as a dev convenience."; now "Ordering assumes you run forqsite's default single-instance install, not docker: network Postgres and MinIO, with the app and scheduler under a process supervisor." The non-docker premise is this page's own; no file in the forqsite repository designates production as non-docker. At forqsite commit afed86a7 (cp-PM107-main) the old wording no longer held: the root docker-compose.yml is gone, and a Dockerfile builds the one production image that forqsite's opt-in rolling pair runs (b2f0712d, f316120f), so compose is no longer a dev convenience. What the page now assumes holds there: architecture.md keeps single-instance installs the default and the rolling restart opt-in, the runbook's single-instance upgrade is a checkout restarted by a process manager, and Postgres and MinIO are network services that the rolling compose file does not declare.`
   - **C-025**, for GAP-005:
     - `claim`: `A checkout binds port 6020 (package.json dev and start) while docs/first-run.md uses 3000; the production Docker image defaults to 3000 through PORT, which the checkout's start script does not read.`
     - `quote`: `but docs/first-run.md still says 3000`
     - `result`: `changed`.
     - `evidence`, in this order, as `[path, symbol]`:
       1. `package.json`: `"dev": "next dev -p 6020",`
       2. `package.json`: `"start": "dotenv -e .env.local -- next start -H 0.0.0.0 -p 6020",`
       3. `docs/first-run.md`: `APP_URL=http://admin.forqsite.test:3000`
       4. `docs/first-run.md`: `curl http://localhost:3000/api/health`
       5. `docs/operator-runbook.md`: ``` `pnpm start` wraps `next start -H 0.0.0.0 -p 6020` — the application listens on port 6020, not ```
       6. `Dockerfile`: `CMD ["sh", "-c", "node_modules/.bin/next start -H 0.0.0.0 -p ${PORT:-3000}"]`
     - `note`:
       `CHANGED: was "reverse_proxy * forqsite_a:3000 forqsite_b:3000"; now "but docs/first-run.md still says 3000". At forqsite commit afed86a7 (cp-PM107-main) docs/deployment/Caddyfile.example no longer exists, the runbook states 6020 for a checkout and 3000 for the Docker image (§2.7), and the rolling compose file and the edge Caddy site file agree on 3000 inside the container. first-run.md is the remaining drift, and only the image reads PORT.`
   - **C-024 moves to `closed[]`** (ruling 2). Remove it from `claims`, keeping the others in
     order. Append a second `closed` record after the GAP-006 record, with keys in this order:
     - `id` `C-024`; `gap` `GAP-004`; `claim`: C-024's claim, verbatim.
     - `closed_by`: `{"commit": "f316120f8a2f120c1b03741071381038a5b0f223", "path": "scripts/rolling-restart.sh"}`.
     - `evidence`, as `[path, symbol]`. All four are present at the target and absent at the pin.
       The Dockerfile line is also present at `b2f0712d`, which is how the record carries that
       commit.
       1. `Dockerfile`: `CMD ["sh", "-c", "node_modules/.bin/next start -H 0.0.0.0 -p ${PORT:-3000}"]`
       2. `docs/deployment/docker-compose.rolling.yml`: `image: ${FORQSITE_IMAGE:?set FORQSITE_IMAGE to a digest-pinned image reference}`
       3. `scripts/rolling-restart.sh`: `docker compose -f "$COMPOSE_FILE" "$@"`
       4. `docs/deployment/forqsite.caddy.example`: `reverse_proxy forqsite_a:3000 forqsite_b:3000 {`
     - `note`. **Draft, shown to the operator before the build:**
       `Closed, superseded. The problem this gap described no longer exists, because forqsite took the opposite approach: it made Docker a production path rather than rescoping it to development. b2f0712d added the Dockerfile that builds forqsite's one production image; f316120f deleted the root docker-compose.yml and docs/deployment/Caddyfile.example, rewrote docs/deployment/docker-compose.rolling.yml to run that image by digest with no build step, and made scripts/rolling-restart.sh take the compose file as an argument. The fix this site proposed, compose rescoped to development dependencies and a systemd rolling pair, was not done, and its done-when tests were never met. Verified at forqsite commit afed86a7 (cp-PM107-main).`
   - **C-001, the Known-gaps union.** Rebuild C-001's `evidence` as the deduplicated union of
     every S-07 claim's evidence.
     - Keep the surviving pairs in their existing order.
     - Then append the new pairs in claim order, then evidence order. These are C-025's runbook
       6020 line and its Dockerfile `CMD`.
     - That gives 54 pairs, minus 9 dropped, plus 2 added: 47.

2. **`index.html` template**, before → after.
   - **:478** `<span>Production runtime is non-docker with network PostgreSQL and MinIO. Compose files are dev conveniences (see `
     → `<span>Production runtime is forqsite's default single-instance install, not docker, with network PostgreSQL and MinIO (see `
   - **:616** `The designated production architecture: forqsite runs as a plain Node process on the host, supervised by systemd, talking to <strong>network</strong> PostgreSQL and MinIO you operate separately. Caddy terminates TLS in front. The compose files in the repo are dev conveniences, not the prod path.</p>`
     → `The designated production architecture: forqsite's default single-instance install, run as a plain Node process on the host, supervised by systemd, talking to <strong>network</strong> PostgreSQL and MinIO you operate separately. Caddy terminates TLS in front. forqsite also ships an opt-in Docker path, a two-instance rolling pair run from one digest-pinned image, which this site does not cover; forqsite's operator runbook §12.2 does.</p>`
     This is ruling 1's one sentence. The :615 H1, "Production, without docker", stays.
   - **:767** `The repo's rolling-restart story is docker-shaped (two containers + Caddy). The same pattern works with two systemd instances`
     → `forqsite's own rolling restart is docker-shaped: two containers on one digest-pinned image behind Caddy, swapped by Mscripts/rolling-restart.sh</span>, which drives docker compose and nothing else. The same pattern works by hand with two systemd instances`
     The :766 H2 stays.
   - **:1085** `The designated shape: one app host, network data services, TLS at the edge. Nothing containerised in production.</p>`
     → `The designated shape: forqsite's default single-instance install on one app host, network data services, TLS at the edge. Nothing containerised in production; forqsite's opt-in Docker rolling pair is a different shape, not covered here.</p>`
   - **:863**, in Promoting a change. The text stays the site's own path. `</span> in between. After the build,`
     → `</span> in between. forqsite&rsquo;s opt-in Docker path promotes differently: Mscripts/r1-build.sh</span> builds one image from a commit plus a provider overlay, and that image&rsquo;s digest is what moves between environments, with no build on the deployment host. After the build,`
     The evidence is forqsite's runbook §2.7b and §12.2.
   - **:662**, port note: `several repo docs still say 3000 (GAP-005).` → `forqsite's first-run.md still says 3000 (GAP-005).`
   - **:1591**: delete the line `{ label: 'compose files claim a Dockerfile that does not exist', dot: bad, gap: 'GAP-004' },`,
     including its indentation and newline.
   - **:1592**: `{ label: 'port 6020 vs docs saying 3000', dot: bad, gap: 'GAP-005' },` → `{ label: 'port 6020 vs first-run.md saying 3000', dot: bad, gap: 'GAP-005' },`
   - **:1607**: delete the whole `{ id: 'GAP-004', …` ledger line, including its newline.
   - **:1608**: `sum: 'Port drift: app binds 6020, docs and rolling topology say 3000. Honor PORT with one documented default.'`
     → `sum: 'Port drift: a checkout binds 6020 but first-run.md still says 3000. Honor PORT with one documented default.'`

3. **`gap-handoff.html` template**, before → after.
   - **Count.** `eleven of them,` → `ten of them,`
   - **Ordering paragraph (C-022).** `Ordering assumes production stays non-docker: network Postgres and MinIO, with compose as a dev convenience.`
     → `Ordering assumes you run forqsite's default single-instance install, not docker: network Postgres and MinIO, with the app and scheduler under a process supervisor.`
     The stamp that follows stays as it is.
   - **TL;DR bullet 1. Draft, shown to the operator before the build:**
     `<strong>003 + 004, together</strong> &mdash; they decide the same thing &mdash; whether production is supervised by systemd, with compose rescoped to development. Fold <strong>005</strong> in: all three touch ports and the same documents.`
     → `<strong>003 + 005, together</strong> &mdash; both settle the single-instance install this page assumes: 003 how the app and scheduler are supervised, 005 which port the app listens on. They touch the same documents, so do them as one change.`
   - **One caution.** `003, 004 and 005 all change operator-facing behaviour` → `003 and 005 both change operator-facing behaviour`
   - **Chip.** `P1 — BLOCKS PROD PATH × 3` → `P1 — BLOCKS PROD PATH × 2`
   - **GAP-003 problem.** `'The designated production architecture is non-docker, but the repo ships no process supervision artifacts.`
     → `'This page assumes forqsite\'s default single-instance install, which is not docker, but the repo ships no process supervision artifacts for it.`
   - **GAP-004.** Delete every line from `      mk('GAP-004'` up to, but not including,
     `      mk('GAP-005'`.
   - **GAP-005.** Replace the whole entry, from `      mk('GAP-005'` up to, but not including,
     `      mk('GAP-007'`, with this exactly. Every line ends in a newline.
     ```
           mk('GAP-005', 'P1', 'CONSISTENCY', 'Resolve the 6020 / 3000 port drift',
             'A checkout binds 6020 (package.json dev and start pin -p 6020), but docs/first-run.md still says 3000: its APP_URL example, its expected output, its health check and its troubleshooting. An admin following first-run.md health-checks the wrong port. forqsite\'s production Docker image defaults to 3000 instead, through PORT, which the checkout\'s start script does not read; the operator runbook states that difference.',
             [['package.json', 'dev/start pin -p 6020; start does not read PORT'],
              ['docs/first-run.md', 'APP_URL example, expected output, health check and troubleshooting all use :3000'],
              ['docs/operator-runbook.md', '§2.7: pnpm start listens on port 6020, not 3000; the Docker image defaults to 3000 via PORT'],
              ['Dockerfile', 'CMD: next start -H 0.0.0.0 -p ${PORT:-3000}']],
             'Make the checkout\'s start script honour PORT, as the image already does, with one documented default for the checkout (recommend keeping 6020, since it is what the code does): next start -H 0.0.0.0 -p ${PORT:-6020}. Sweep first-run.md to that value.',
             ['grep -n "3000" docs/first-run.md returns no reference to the app port.',
              'PORT=7000 pnpm start binds 7000; unset binds the documented default.',
              'first-run.md expected output matches an actual run.']),
     ```

4. **Docs.**
   - **README.md**, `gap-handoff.html` row: `(11 items, GAP-003 to GAP-015;` → `(10 items, GAP-003 to GAP-015;`
   - **docs/architecture.md** § Claims manifest schema. Insert this row directly after the
     `` `closed[].evidence` `` row:
     ``| `closed[].note` | string | in use | CONTENT-042 | Free text that never names a claim id. It explains a closure the evidence alone does not show, such as a gap closed because forqsite took a different approach than the gap proposed (the note starts `Closed, superseded.`), and names any further commit behind the closure. Neither the checker nor `restamp.py` reads it. |``

**Ideology check: no conflict.**
- The bundles change only through `bundle-template.py`.
- Every new claim cites checkable forqsite literals.
- The closed record's evidence holds at the target and is absent at the pin.
- No clone path, host or URL is written. The `http://` strings are forqsite literals inside
  evidence.

## Tests

Run from the repo root with `FORQSITE_CLONE=<clone path> bash <this block>`.
- **Measured at spec time, 2026-10-05.** On main `e73bbf6` it printed `57 failed` and exited 1.
  On a throwaway copy with the edits above, it printed `OK`, then `ALL-OK`, and exited 0. The
  `scripts/*-selftest.sh` loop was green on that copy.
- **Acceptance.** `OK` and `ALL-OK`, exit 0, and the CLAUDE.md selftest loop stays green.
- **The reviewer** also reads the closed record's four literals in the clone at
  `cp-PM107-main`, and confirms that the GAP-004 note claims no fix the site proposed.

```bash
set -euo pipefail
: "${FORQSITE_CLONE:?set FORQSITE_CLONE to a local forqsite clone that has cp-PM107-main}"
cd "$(git rev-parse --show-toplevel)"
BASE=d62bd2b1fbbb159b5a6e80c4cb7dc39f860f0679   # last commit to change the manifest, either bundle, README or architecture.md
S=$(mktemp -d); trap 'rm -rf "${S:?}"' EXIT
for p in index.html gap-handoff.html; do
  python3 scripts/bundle-template.py verify "$p" > /dev/null
  python3 scripts/bundle-template.py extract "$p" "$S/$p" > /dev/null
  python3 -c "import re,sys; [open(f'{sys.argv[2]}.{i}.js','w').write(s) for i,s in enumerate(re.findall(r'<script type=.text/x-dc.[^>]*>(.*?)</script>', open(sys.argv[1]).read(), re.S))]" "$S/$p" "$S/js-$p"
  for f in "$S/js-$p".*.js; do node --check "$f"; done
  git show "$BASE:$p" > "$S/b-$p"; python3 scripts/bundle-template.py extract "$S/b-$p" "$S/base.$p" > /dev/null
done
git show "$BASE:docs/claims-manifest.json" > "$S/base-manifest.json"
set +e
python3 scripts/stale-claims.py --no-commits --manifest docs/claims-manifest.json cp-PM107-main > "$S/check.out" 2>&1; echo $? > "$S/check.rc"
set -e
python3 - "$S" <<'EOF'
import json, os, re, subprocess, sys
S = sys.argv[1]; clone = os.environ['FORQSITE_CLONE']; F = []
def need(ok, msg):
    if not ok: F.append(msg)
def git(*a): return subprocess.run(['git', '-C', clone, *a], capture_output=True, text=True, errors='replace')
PIN, TGT = '94f5c339c085869c390d92f567461185b03f1bea', 'afed86a735c8d171be5ee42ce58fee5b7ea25e37'
F316, B2F0 = 'f316120f8a2f120c1b03741071381038a5b0f223', 'b2f0712d6ef814641fdda79db63e57edd42d29aa'
need(git('rev-parse', 'cp-PM107-main^{commit}').stdout.strip() == TGT, 'cp-PM107-main is not afed86a7 in this clone')
norm = lambda s: re.sub(r'\s+', ' ', s)
m = json.load(open('docs/claims-manifest.json')); b = json.load(open(f'{S}/base-manifest.json'))
T = {p: open(f'{S}/{p}').read() for p in ('index.html', 'gap-handoff.html')}
B = {p: open(f'{S}/base.{p}').read() for p in T}
need(m['release'] == b['release'] and m['stamps'] == b['stamps'], 'release pin or a stamp changed')
need(open('docs/claims-manifest.json').read() == json.dumps(m, indent=2, ensure_ascii=False) + '\n', 'manifest serialisation')
C = {c['id']: c for c in m['claims']}; BC = {c['id']: c for c in b['claims']}
need([c['id'] for c in m['claims']] == [c['id'] for c in b['claims'] if c['id'] != 'C-024'], 'C-024 not moved out of claims, or claims reordered')
# 1. checker
rc = open(f'{S}/check.rc').read().strip(); out = open(f'{S}/check.out').read()
need(rc == '0', f'checker exit {rc} at cp-PM107-main')
need('summary: 42 claims: 21 untouched, 21 holds, 0 stale, 0 unverified; 2 closed records: 2 closed, 0 reopened' in out, 'checker summary')
need(re.search(r'^C-024 closed  gap GAP-004$', out, re.M), 'C-024 not closed')
# 2. GAP-004 closed record (ruling 2)
cl = m.get('closed', [])
need(len(cl) == 2 and cl[0] == b['closed'][0], 'closed[] is not the GAP-006 record plus one')
x = cl[1] if len(cl) == 2 else {}
need(list(x) == ['id', 'gap', 'claim', 'closed_by', 'evidence', 'note'], f'closed record keys {list(x)}')
need(x.get('id') == 'C-024' and x.get('gap') == 'GAP-004' and x.get('claim') == BC['C-024']['claim'], 'closed record id/gap/claim')
need(x.get('closed_by') == {'commit': F316, 'path': 'scripts/rolling-restart.sh'}, 'closed_by')
for c in (F316, B2F0):
    need(git('merge-base', '--is-ancestor', c, TGT).returncode == 0 and git('merge-base', '--is-ancestor', c, PIN).returncode == 1, f'{c[:8]} ancestry')
need('scripts/rolling-restart.sh' in git('show', '--name-only', '--format=', F316).stdout.split(), 'closer does not touch its path')
ev = x.get('evidence', [])
need(len(ev) == 4, 'closed evidence is not four literals')
for e in ev:
    need(git('grep', '-q', '-F', '-e', e['symbol'], TGT, '--', e['path']).returncode == 0, f"not at target: {e['path']}")
    need(git('grep', '-q', '-F', '-e', e['symbol'], PIN, '--', e['path']).returncode != 0, f"already at the pin: {e['path']}")
need(any(e['path'] == 'Dockerfile' and git('grep', '-q', '-F', '-e', e['symbol'], B2F0, '--', 'Dockerfile').returncode == 0 for e in ev), 'no Dockerfile literal from b2f0712d')
n = x.get('note', '')
need(n.startswith('Closed, superseded. The problem this gap described no longer exists, because forqsite took the opposite approach'), 'closure note opening')
need(all(s in n for s in ('b2f0712d', 'f316120f', 'was not done', 'afed86a7')), 'closure note lacks a commit or the not-done sentence')
# 3. claims
need(C['C-005']['quote'] == BC['C-005']['quote'] and C['C-005']['result'] == 'open', 'C-005 quote or result changed')
need([e['symbol'] for e in C['C-005']['evidence']] == [e['symbol'] if 'detail }' not in e['symbol'] else "return { ok: false, error: 'invalid_data', detail, blockType: block.type, blockIndex: index }" for e in BC['C-005']['evidence']], 'C-005 evidence')
for cid, q, old in (('C-022', "Ordering assumes you run forqsite's default single-instance install", 'Ordering assumes production stays non-docker'),
                    ('C-025', 'but docs/first-run.md still says 3000', 'reverse_proxy * forqsite_a:3000 forqsite_b:3000')):
    c = C[cid]
    need(c['quote'] == q and c['result'] == 'changed' and c.get('note', '').startswith(f'CHANGED: was "{old}') and 'afed86a7' in c.get('note', ''), f'{cid} quote/result/note')
    need(T[c['page']].count(q) == 1, f'{cid} quote not on the page once')
need(not any(e['path'] in ('docker-compose.yml', 'docs/deployment/Caddyfile.example') for c in m['claims'] for e in c['evidence'] + c.get('absent', [])), 'a claim still cites a removed file')
need(not any(a['path'] == 'Dockerfile' for a in C['C-022'].get('absent', [])), 'C-022 still says no Dockerfile')
for cid in C:
    if cid in ('C-001', 'C-005', 'C-022', 'C-025'): continue
    need(C[cid] == BC[cid], f'{cid} changed')
    need(T[C[cid]['page']].count(C[cid]['quote']) == B[C[cid]['page']].count(C[cid]['quote']), f'{cid} quote count changed')
need({k: v for k, v in C['C-001'].items() if k != 'evidence'} == {k: v for k, v in BC['C-001'].items() if k != 'evidence'}, 'C-001 changed outside evidence')
key = lambda e: (e['path'], e['symbol'])
u = []
for c in m['claims']:
    if c['stamp'] == 'S-07':
        u += [key(e) for e in c['evidence'] if key(e) not in u]
got = [key(e) for e in C['C-001']['evidence']]
need(len(got) == len(set(got)) and set(got) == set(u), 'Known-gaps evidence is not the S-07 union')
old = [key(e) for e in BC['C-001']['evidence'] if key(e) in u]
need(got == old + [k for k in u if k not in old], 'Known-gaps order: kept pairs in order, then new pairs')
# 4. pages: old sentences gone, new present
GONE = {'index.html': ['Compose files are dev conveniences', 'The compose files in the repo are dev conveniences', "The repo's rolling-restart story", 'The designated shape: one app host', 'several repo docs still say 3000', 'compose files claim a Dockerfile', 'port 6020 vs docs saying 3000', 'GAP-004', 'rolling topology say 3000'],
        'gap-handoff.html': ['eleven of them', 'production stays non-docker', 'compose rescoped to development', '003, 004 and 005', 'BLOCKS PROD PATH × 3', 'The designated production architecture is non-docker', 'GAP-004', 'Caddyfile.example', 'rolling topology all say 3000']}
NEW = {'index.html': ["Production runtime is forqsite's default single-instance install, not docker, with network PostgreSQL and MinIO (see",
                      "forqsite also ships an opt-in Docker path, a two-instance rolling pair run from one digest-pinned image, which this site does not cover; forqsite's operator runbook §12.2 does.</p>",
                      "forqsite's own rolling restart is docker-shaped: two containers on one digest-pinned image behind Caddy, swapped by",
                      "which drives docker compose and nothing else. The same pattern works by hand with two systemd instances",
                      "Nothing containerised in production; forqsite's opt-in Docker rolling pair is a different shape, not covered here.</p>",
                      "forqsite&rsquo;s opt-in Docker path promotes differently:",
                      "and that image&rsquo;s digest is what moves between environments, with no build on the deployment host. After the build,",
                      "forqsite's first-run.md still says 3000 (GAP-005).",
                      "{ label: 'port 6020 vs first-run.md saying 3000', dot: bad, gap: 'GAP-005' },",
                      "sum: 'Port drift: a checkout binds 6020 but first-run.md still says 3000. Honor PORT with one documented default.'"],
       'gap-handoff.html': ['ten of them,',
                            "Ordering assumes you run forqsite's default single-instance install, not docker: network Postgres and MinIO, with the app and scheduler under a process supervisor.",
                            '<strong>003 + 005, together</strong> &mdash; both settle the single-instance install this page assumes: 003 how the app and scheduler are supervised, 005 which port the app listens on. They touch the same documents, so do them as one change.',
                            '003 and 005 both change operator-facing behaviour', 'BLOCKS PROD PATH × 2',
                            "This page assumes forqsite\\'s default single-instance install, which is not docker, but the repo ships no process supervision artifacts for it.",
                            "['Dockerfile', 'CMD: next start -H 0.0.0.0 -p ${PORT:-3000}']"]}
for p in T:
    t = norm(T[p])
    for s in GONE[p]: need(norm(s) not in t, f'{p}: still has {s!r}')
    for s in NEW[p]: need(norm(s) in t, f'{p}: missing {s[:60]!r}')
gh = re.findall(r"mk\('(GAP-\d+)'", T['gap-handoff.html'])
need(gh == re.findall(r"\{ id: '(GAP-\d+)'", T['index.html']) and len(gh) == 10, 'gap list and ledger disagree, or not ten')
pri = re.findall(r"mk\('GAP-\d+', '(P\d)'", T['gap-handoff.html'])
for p, k in re.findall(r'(P\d) — [^<×]*× (\d+)', T['gap-handoff.html']): need(pri.count(p) == int(k), f'{p} chip count')
# 5. docs
r = [l for l in open('README.md') if l.startswith('| `gap-handoff.html` |')]
need(len(r) == 1 and '(10 items, GAP-003 to GAP-015;' in r[0], 'README item count')
need(any(l.startswith('| `closed[].note` | string | in use | CONTENT-042 |') for l in open('docs/architecture.md')), 'architecture closed[].note row')
need(not re.search(r'/mnt/|/home/|~/|https?://', json.dumps([x.get('note'), C['C-022'].get('note', ''), C['C-025'].get('note', '')])), 'a new note names a host or local path')
for f in F: print('FAIL:', f)
print('OK' if not F else f'{len(F)} failed'); sys.exit(1 if F else 0)
EOF
# 6. restamp would succeed at the target (dry run, in a throwaway clone)
git clone -q . "$S/fh"
cp docs/claims-manifest.json "$S/fh/docs/"; cp index.html gap-handoff.html "$S/fh/"
git -C "$S/fh" -c user.name=t -c user.email=t@example.invalid commit -qam scratch --allow-empty
D=$(date +%F)
python3 "$S/fh/scripts/restamp.py" --dry-run --date "$D" cp-PM107-main > "$S/r.out"
grep -qxF "restamp: nullvalues/forqsite 94f5c339 -> afed86a7 on $D: 42 claims: 38 open, 2 changed, 1 added, 0 unverified (dry run; nothing written)" "$S/r.out"
echo ALL-OK
```

## Post-merge (orchestrator + operator)

This is an attended release, run as CONTENT-040's was. The orchestrator runs it, and the
operator gives each go. Pass the clone through `FORQSITE_CLONE` only.

Do not run `deploy.sh` by hand between this merge and the release. Main's pages drop GAP-004
while their stamps still name `94f5c339`.

1. **Gate.** Stop if any of these fails.
   - `rel-94f5c339` exists locally, and `git ls-remote origin refs/tags/rel-94f5c339` shows the
     same object.
   - The operator has said go.
2. **Re-run this story's Tests block on main.** Expect `OK` and `ALL-OK`.
3. **Dry run:** `scripts/release.sh cp-PM107-main`. Always use the explicit target, never
   `--latest-checkpoint`. Expect exit 0 and these lines:
   - `release: target cp-PM107-main (afed86a7)`;
   - `restamp: nullvalues/forqsite 94f5c339 -> afed86a7 on <date>: 42 claims: 38 open, 2 changed, 1 added, 0 unverified (dry run; nothing written)`;
   - `release: would commit: release: nullvalues/forqsite@afed86a7, 42 claims: 21 untouched, 21 holds, 0 unverified`.

   Show the operator the whole output. If any line differs, stop and ask.
4. **Release, on the operator's go:** `scripts/release.sh --yes cp-PM107-main`. Expect exit 0,
   then the commit, the annotated `rel-afed86a7` tag, the deploy, the drift check and the push.
5. **After.**
   - The manifest's `release.commit` is `afed86a735c8d171be5ee42ce58fee5b7ea25e37`, and every
     stamp names `afed86a7` with the run date.
   - `stale-claims.py --no-commits cp-PM107-main` exits 0 with
     `42 claims: 42 untouched, 0 holds, 0 stale, 0 unverified; 2 closed records: 2 closed, 0 reopened`.
   - **CER-063's loop.** In the drift check's output, the `provenance         claims <sha> deployed …`
     line names the same full sha as its `ref` line. That sha is the release commit, not the
     tag object. Report it to the operator.
6. **On any stop,** follow the recovery lines `release.sh` prints, and nothing else.
   - Exit 3 means a claim went stale. That needs a new review story, not a hand edit.
   - Exit 16 is the operator's call. `deploy.sh --rollback` is printed, never run.

## Out of scope

- A Docker route, or any page that documents forqsite's image, R1 build or rolling pair beyond
  the sentences above (ruling 1).
- Presenting GAP-004's proposed fix (dev-only compose, a systemd rolling pair) as done
  (ruling 2).
- GAP-003's approach and acceptance tests, and GAP-005's title.
- Other mentions of "non-docker" that stay true as the site's own path: the :615 H1, the :766
  H2, the :796 link text, and :1341.
- `docs/cer/backlog.md`. CER-063 is already marked resolved by INFRA-022, and this release only
  shows the sidecar fix live, so no edit is needed.
- A `closed[].absent` check. Evidence alone decides reopening (CONTENT-040).
- Restamping, deploying, tagging or pushing inside the story. The builder never runs
  `release.sh --yes`, `restamp.py` without `--dry-run`, or `deploy.sh`.
- Coverage of command blocks (CER-046 and CER-056, Do Much Later).
