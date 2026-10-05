---
id: CONTENT-041
rail: CONTENT
title: Fix the reader-facing command errors and record the admin-page install as a gap
status: planned
phase: "15"
story_class: content
auth_gated: false
schema_introduces: false
primary_files:
  - index.html

touches:
  - gap-handoff.html
  - docs/claims-manifest.json
  - docs/cer/backlog.md
  - README.md

narrative_roles: []
---

## Context

Page fixes for errors a reader can hit today, each verified against forqsite at the pin
`94f5c339`. This is a content story (operator ruling 2026-10-05), so there is no proving pass.
- **CER-051.** The index template has 5 U+200B characters, one opening each comment-first `<pre>`.
  The gap template has none. `copyCmd` strips the character, but a copy made by hand does not.
- **CER-048.** No forqsite file names `/etc/forqsite/env`, and the page never creates it, so a
  unit copied as written fails to start. `pnpm start` loads `.env.local` itself. `pnpm scheduler`
  loads nothing, so the scheduler unit must wrap it in dotenv, as `scripts/dev.sh` does.
- **CER-049.** `-o` is right: dotenv-cli 11.0.0 documents it as `override system variables`, and
  `index.html` already uses it. GAP-013's proposed fix is the one to change.
- **CER-059.** Runbook §14.2 says a bare HTTPS tarball URL pins without an integrity hash, and
  §16.5 pins by scoped name.
- **CER-058.** The admin install page prints `pnpm add -w file:/path/to/pack.tgz`, at the pin and
  at forqsite `origin/main` on 2026-10-05. GAP-001 to GAP-014 have all been used, and GAP-015
  appears nowhere in the repo's history, so it is the next number. The entry is P2 CORRECTNESS,
  because following the page breaks ADR 0004's I1.

Length: about 190 lines, over the 150 target. Most of it is exact before and after text, the
GAP-015 entry, the C-044 record and the 50-line check block the operator asked for.

## Requires

Phase 14-post1 complete. The manifest `release.commit` is `94f5c339c085869c390d92f567461185b03f1bea`.

## Ensures

The Tests block exits 0 and prints `OK`: each old text is gone and its new text appears exactly
once, no U+200B remains, GAP-015 and C-044 exist and every count agrees, every evidence literal
is at the pin, both bundles verify, and `stale-claims.py` exits 0 at the pin.

## Instructions

Follow architecture.md § Editing procedure: `verify`, `extract`, edit, `inject`, `verify`, then
`node --check` the edited scripts. Below, `M(x)` means
`<span style="font-family:'Geist Mono',monospace; font-size:12px;">x</span>` and `M5(x)` is the
same with `12.5px`. Each "before" occurs exactly once.

1. **index.html template.**
   - CER-051: delete all 5 U+200B characters. Leave `copyCmd`'s `.replace(/^​/, '')` as it is.
   - forqsite.service: delete the line `EnvironmentFile=/etc/forqsite/env          # move secrets here, chmod 600`.
   - forqsite-scheduler.service: delete the line `EnvironmentFile=/etc/forqsite/env`, and change
     `ExecStart=/usr/bin/pnpm exec tsx scripts/scheduler.ts` to
     `ExecStart=/usr/bin/pnpm exec dotenv -e .env.local -- tsx scripts/scheduler.ts`.
   - Caption under forqsite.service: replace everything from `<strong>Dotenv caveat:</strong>`
     through `directly).` with:
     `<strong>Environment:</strong> both units read the checkout's M(.env.local) through forqsite's own loader, M(dotenv -e .env.local). M(pnpm start) runs it from M(package.json)'s M(start) and M(prestart) scripts. The scheduler unit runs it explicitly, as forqsite's M(scripts/dev.sh) does, because M(pnpm scheduler) loads nothing. Keep M(.env.local) readable only by the M(forqsite) user (M(chmod 600)).`
   - Install route: `For production, prefer moving secrets out of M(.env.local) into the systemd M(EnvironmentFile) (see Process supervision).`
     becomes `For production, make M(.env.local) readable only by the user the app runs as (M(chmod 600)); both systemd units load it (see Process supervision).`
   - "Publishing a reviewed pack", step 4: `then pin the HTTPS specifier with M5(pnpm add --workspace-root --save-exact).`
     becomes `then pin by scoped package name and version, never by the tarball's HTTPS URL, which pins without an integrity hash: M5(pnpm add -w "@forqsite-packs/&lt;name&gt;@&lt;version&gt;"), with the scope mapped in the deployment's M5(.npmrc). Run M5(pnpm verify:provider-pins) and confirm the lockfile entry carries both M5(integrity) and M5(tarball).`
   - Known-gaps ledger: on the line after the `{ id: 'GAP-013', …` line, insert
     `      { id: 'GAP-015', pri: 'P2', priColor: P2, sum: 'The platform-admin pack install page prints pnpm add -w file:/path/to/pack.tgz, the install form the runbook names as withdrawn and verify:provider-pins reports.' },`
2. **gap-handoff.html template.**
   - GAP-013's approach: `pnpm exec dotenv -e .env.local -- scripts/backup.sh, and the same for restore.sh.`
     becomes `pnpm exec dotenv -o -e .env.local -- scripts/backup.sh, and the same for restore.sh. Keep -o: without it a DATABASE_URL already exported in the shell wins over the file.`
   - GAP-013's third acceptance item: `'The runbook\'s backup and restore commands load .env.local the same way package.json\'s start script does.'`
     becomes `'The runbook\'s backup and restore commands load .env.local with the dotenv loader package.json\'s start script uses, with -o so the file wins over the shell.'`
     The `\'` are literal, as they appear in the template.
   - Insert the entry below directly before `      mk('GAP-009'`, followed by one blank line.
   - Change `ten of them,` to `eleven of them,`, `<strong>008 and 013 whenever</strong>` to
     `<strong>008, 013 and 015 whenever</strong>`, and `P2 — DATA-SAFETY / CORRECTNESS / TOIL × 4` to `… × 5`.
     Leave every stamp alone, since the release restamps them.

   ```js
      mk('GAP-015', 'P2', 'CORRECTNESS', 'Replace the withdrawn file: install on the platform-admin pack install page',
        'The platform-admin pack install page tells the operator to install a reviewed pack with pnpm add -w file:/path/to/pack.tgz. The operator runbook names that form as withdrawn: ADR 0004\'s invariant I1 requires an artifact stored outside any working tree, and pnpm verify:provider-pins reports a file: specifier as a file-specifier finding. An operator who follows the page rather than the runbook installs the pack in a form forqsite\'s own pin check flags.',
        [['src/app/platform-admin/block-providers/install/page.tsx', 'install sequence, step 1: pnpm add -w file:/path/to/pack.tgz'],
         ['docs/operator-runbook.md', '§14.2: the file: install "is withdrawn"; install by scoped package name and version from the pack store']],
        'Proposed: make step 1 print the runbook\'s §14.2 install, by scoped package name and version from the pack store, with its two checks: the sha512 against the one handed over, and a lockfile entry that carries both integrity and tarball. Or point step 1 at §14.2 instead of restating it.',
        ['The install page prints no file: specifier.',
         'The page\'s install step and the runbook\'s §14.2 agree.']),
   ```
3. **docs/claims-manifest.json.** Append the claim below to `claims`. Then append each of its
   `evidence` items that C-001 does not already hold to the end of C-001's `evidence`, so C-001
   stays the ordered union over S-07. Write the file back with
   `json.dumps(m, indent=2, ensure_ascii=False) + '\n'`. Set the note's date to the day you run
   the Tests. No existing claim's quote changes: no claim quotes any of the text edited above.

   ```json
   {"id": "C-044", "page": "gap-handoff.html", "location": "GAP-015 entry, problem and evidence",
    "claim": "forqsite's platform-admin pack install page prints pnpm add -w file:/path/to/pack.tgz, the install form forqsite's operator runbook names as withdrawn, because ADR 0004's invariant I1 requires an artifact stored outside any working tree and verify:provider-pins reports a file: specifier.",
    "quote": "The operator runbook names that form as withdrawn",
    "evidence": [
     {"path": "src/app/platform-admin/block-providers/install/page.tsx", "symbol": "pnpm add -w file:/path/to/pack.tgz"},
     {"path": "docs/operator-runbook.md", "symbol": "**`pnpm add -w file:/path/to/<received-pack>.tgz` is withdrawn**"},
     {"path": "docs/operator-runbook.md", "symbol": "invariant I1 requires an artifact stored outside any working tree"},
     {"path": "docs/operator-runbook.md", "symbol": "reports a `file:` specifier as a `file-specifier` finding"}],
    "stamp": "S-07", "result": "added", "note": "ADDED: verified at the release commit on 2026-10-05."}
   ```
4. **README.md**, in the `gap-handoff.html` row: change `(10 items, GAP-003 to GAP-014;` to
   `(11 items, GAP-003 to GAP-015;`.
5. **docs/cer/backlog.md.** At the end of the Finding cell of CER-048, CER-049, CER-051 and CER-059,
   append ` **RESOLVED Phase 15 — CONTENT-041.**`. For CER-058, append
   ` **RESOLVED Phase 15 — CONTENT-041 (filed as GAP-015).**`.

Ideology check: both bundles change only through `bundle-template.py`, which respects the
generated-artifact constraint. Nothing becomes external.

## Tests

From the repo root, run `FORQSITE_CLONE=<clone> bash <file>` with this block saved outside the
repo. The spec-writer ran it on 2026-10-05. On `main` it printed 29 `FAIL:` lines and exited 1, and every evidence
literal was found at the pin. On a throwaway clone with Instructions 1 to 5 applied, it printed
`OK`, all selftests passed, and a headless render showed 11 gap cards and the unit blocks
starting with `#`.

```bash
set -e
: "${FORQSITE_CLONE:?set FORQSITE_CLONE to the local forqsite clone}"
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
for p in index.html gap-handoff.html; do python3 scripts/bundle-template.py verify $p; python3 scripts/bundle-template.py extract $p $S/$p >/dev/null; done
python3 scripts/stale-claims.py --no-commits 94f5c339c085869c390d92f567461185b03f1bea >/dev/null
python3 - "$S" <<'PY'
import json, os, re, subprocess, sys
S = sys.argv[1]; bad = []; rel = '94f5c339c085869c390d92f567461185b03f1bea'
def ck(ok, msg):
    if not ok: bad.append(msg)
n = lambda s: re.sub(r'\s+', ' ', s).strip()
raw = {p: open(f'{S}/{p}').read() for p in ('index.html', 'gap-handoff.html')}
P = {p: n(t) for p, t in raw.items()}; I, G = P['index.html'], P['gap-handoff.html']
M = lambda x, s='12px': f"<span style=\"font-family:'Geist Mono',monospace; font-size:{s};\">{x}</span>"
git = lambda *a: subprocess.run(['git', '-C', os.environ['FORQSITE_CLONE'], *a], capture_output=True, text=True).returncode
for page, gone, now in [
    (I, 'EnvironmentFile', 'ExecStart=/usr/bin/pnpm exec dotenv -e .env.local -- tsx scripts/scheduler.ts'),
    (I, '/etc/forqsite/env', '<strong>Environment:</strong> both units read the checkout'),
    (I, 'prefer moving secrets out of', 'both systemd units load it (see Process supervision).'),
    (I, 'pnpm add --workspace-root --save-exact', "never by the tarball's HTTPS URL, which pins without an integrity hash: " + M('pnpm add -w "@forqsite-packs/&lt;name&gt;@&lt;version&gt;"', '12.5px')),
    (G, 'pnpm exec dotenv -e .env.local -- scripts/backup.sh', 'pnpm exec dotenv -o -e .env.local -- scripts/backup.sh'),
    (G, "the same way package.json\\'s start script does", 'with -o so the file wins over the shell.'),
    (G, 'ten of them,', 'eleven of them,'),
    (G, '<strong>008 and 013 whenever</strong>', '<strong>008, 013 and 015 whenever</strong>'),
    (G, 'TOIL × 4', 'TOIL × 5'), (I, None, "{ id: 'GAP-015', pri: 'P2', priColor: P2,")]:
    ck(gone is None or n(gone) not in page, f'old text present: {gone!r}'); ck(page.count(n(now)) == 1, f'new text not once: {now!r}')
ck(not any('​' in t for t in raw.values()), 'U+200B remains')
ck(G.find("mk('GAP-013'") < G.find("mk('GAP-015'") < G.find("mk('GAP-009'") and G.count("mk('GAP-015'") == 1, 'GAP-015 entry missing or misplaced')
pri = re.findall(r"mk\('GAP-\d+', '(P\d)'", G)
for p, k in re.findall(r'(P\d) — [^<×]*× (\d+)', G): ck(pri.count(p) == int(k), f'{p} chip count')
ck(len(pri) == 11 and len(re.findall(r"\{ id: 'GAP-\d+'", I)) == 11, 'gap count is not 11')
js = [s for t in raw.values() for s in re.findall(r'<script type="text/x-dc"[^>]*>(.*?)</script>', t, re.S)]
for k, s in enumerate(js): open(f'{S}/s{k}.js', 'w').write(s); ck(subprocess.run(['node', '--check', f'{S}/s{k}.js']).returncode == 0, f'script {k} fails node --check')
f = open('docs/claims-manifest.json').read(); m = json.loads(f); C = {c['id']: c for c in m['claims']}
ck(f == json.dumps(m, indent=2, ensure_ascii=False) + '\n', 'manifest serialisation')
c = C.get('C-044', {}); ck(m['claims'][-1] is c and c.get('result') == 'added' and c.get('stamp') == 'S-07' and c.get('note', '').startswith('ADDED: '), 'C-044 shape')
u = []; [u.append(e) for x in m['claims'] if x['stamp'] == 'S-07' for e in x['evidence'] if e not in u]
ck(C['C-001']['evidence'] == u, 'C-001 is not the ordered S-07 evidence union')
for x in m['claims']: ck(n(x['quote']) in P[x['page']], f"{x['id']}: quote not on page")
ev = [(e['path'], e['symbol']) for x in m['claims'] for e in x['evidence']] + [
    ('package.json', '"start": "dotenv -e .env.local -- next start -H 0.0.0.0 -p 6020",'), ('package.json', '"scheduler": "tsx scripts/scheduler.ts",'),
    ('scripts/dev.sh', 'pnpm exec dotenv -e .env.local -- tsx scripts/scheduler.ts'), ('package.json', '"dotenv-cli": "^11.0.0",'),
    ('docs/operator-runbook.md', 'pnpm add -w "@forqsite-packs/<name>@<version>"'), ('docs/operator-runbook.md', 'alternative either: it pins without an integrity hash.'),
    ('docs/operator-runbook.md', 'Install **by scoped package name and version**. Never by a filesystem path, and never by a bare')]
for p, s in ev: ck(git('grep', '-q', '-F', '-e', s, rel, '--', p) == 0, f'{s!r} not in {p} at the pin')
ck(git('grep', '-q', '-F', '-e', '/etc/forqsite/env', rel) == 1, '/etc/forqsite/env exists at the pin')
ck('(11 items, GAP-003 to GAP-015;' in open('README.md').read(), 'README count')
b = open('docs/cer/backlog.md').read()
for i in ('048', '049', '051', '058', '059'): ck(re.search(rf'^\| CER-{i} \|[^\n]*\*\*RESOLVED Phase 15 — CONTENT-041', b, re.M), f'CER-{i} not resolved')
print('\n'.join(f'FAIL: {x}' for x in bad) or 'OK'); sys.exit(1 if bad else 0)
PY
```

Acceptance: `OK`, exit 0. Then run the suite: `for t in scripts/*-selftest.sh; do bash "$t" || exit 1; done`.

## Out of scope

- GAP-003's proposed fix, which still proposes `EnvironmentFile=/etc/forqsite/env` for units
  forqsite would ship. That is a proposal to forqsite, not a command a reader runs.
- The backup caption's "the database the app runs against" remark (the CER-049 security note). With
  `EnvironmentFile=` gone, the app's environment comes only from `.env.local`.
- The Publishing route's "every HTTPS pack specifier in the lockfile" paragraph and its other steps.
- `hint-placeholder-count` values, `copyCmd`, restamping and release (CONTENT-042), and CER-046/056.
