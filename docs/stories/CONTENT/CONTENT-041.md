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
  `copyCmd` strips the character, but a copy made by hand does not.
- **CER-048.** No forqsite file names `/etc/forqsite/env`, and the page never creates it, so a
  unit copied as written fails to start. `pnpm start` loads `.env.local` itself, but
  `pnpm scheduler` loads nothing, so the scheduler unit wraps it in dotenv, as `scripts/dev.sh`
  does. GAP-003's proposal repeats the old units' assumptions and is reconciled with them.
- **CER-049.** forqsite never runs `dotenv -o`. Its runbook retargets a command by prefixing the
  variable (`DATABASE_URL=<…> pnpm …`), which works only because the shell's value wins.
- **CER-059.** Runbook §16.3 says a published version is two objects: the tarball, and a packument
  at `@<scope>/<name>`. §16.5 pins by scoped name, installs with the frozen lockfile, then commits.
  The page's steps 3 and 4, and its "Config & packs" backup advice, still describe the withdrawn
  tarball install.
- **CER-058.** The in-product install page prints `pnpm add -w file:/path/to/pack.tgz`, at the pin
  and at forqsite `origin/main` on 2026-10-05. GAP-001 to GAP-014 have all been used and GAP-015
  never has, so it is the next number.

**Operator rulings (2026-10-05), made on the first draft after two back-checks:**
1. CER-048: keep the units, and drop the `chmod 600 .env.local` advice. The page never creates the
   `forqsite` user, and it runs `pnpm build` as the operator, so a chmod-600 file becomes unreadable
   and dotenv silently loads nothing. Cite forqsite's own first-run advice instead.
2. CER-049, reversed: drop `-o` from `index.html`, and leave GAP-013's proposal unchanged.
3. CER-059 widens to step 3, and step 4 gains §16.5's tail.
4. GAP-003 comes into scope.
5. GAP-015 stays P2 CORRECTNESS. It gains an accurate reason, the history evidence, an
   "in-product" title and the runbook's list of live documents.
6. Fix the "Config & packs" backup wording.

Length: about 250 lines, above the 150 target. A builder needs the exact text of each edit, and
the operator asked for a check block.

## Requires

Phase 14-post1 complete. The manifest `release.commit` is `94f5c339c085869c390d92f567461185b03f1bea`.

## Ensures

The Tests block exits 0 and prints `OK`: each old text is gone and its new text appears exactly
once, no U+200B or `dotenv -o` remains, GAP-013 is unchanged, GAP-015 and C-044 exist and every
count agrees, every evidence literal and history fact holds at the pin, both bundles verify, and
`stale-claims.py` exits 0 at the pin.

## Instructions

Follow architecture.md § Editing procedure: `verify`, `extract`, edit, `inject`, `verify`, then
`node --check` the edited scripts. Below, `M(x)` means
`<span style="font-family:'Geist Mono',monospace; font-size:12px;">x</span>` and `M5(x)` is the
same with `12.5px`. Each "before" occurs exactly once.

1. **index.html template.**
   - CER-051: delete all 5 U+200B characters. Leave `copyCmd` as it is.
   - forqsite.service: delete the line `EnvironmentFile=/etc/forqsite/env          # move secrets here, chmod 600`.
   - forqsite-scheduler.service: delete the line `EnvironmentFile=/etc/forqsite/env`, and change
     `ExecStart=/usr/bin/pnpm exec tsx scripts/scheduler.ts` to
     `ExecStart=/usr/bin/pnpm exec dotenv -e .env.local -- tsx scripts/scheduler.ts`.
   - Caption under forqsite.service: replace everything from `<strong>Dotenv caveat:</strong>`
     through `directly).` with:
     `<strong>Environment:</strong> both units read the checkout's M(.env.local) through forqsite's own loader, M(dotenv -e .env.local). M(pnpm start) runs it from M(package.json)'s M(start) and M(prestart) scripts. The scheduler unit runs it explicitly, as forqsite's M(scripts/dev.sh) does, because M(pnpm scheduler) loads nothing. A value set in the unit's own environment wins over M(.env.local), because forqsite's dotenv calls do not pass M(-o).`
   - Install route: `For production, prefer moving secrets out of M(.env.local) into the systemd M(EnvironmentFile) (see Process supervision).`
     becomes `For production, forqsite's first-run guide says to move these values into your process manager or container environment instead; the systemd units on Process supervision load M(.env.local) as written.`
   - Backup & recovery (CER-049): change all 4 occurrences of `dotenv -o -e .env.local` to
     `dotenv -e .env.local`. In the backup caption, `M(-o) makes the file win over anything already exported in the shell.`
     becomes `As in forqsite's own scripts, a value already exported in the shell wins over the file.`
     In the restore caption, `names in M(DATABASE_URL), and the name you type`
     becomes `names in M(DATABASE_URL) (a M(DATABASE_URL) already exported in your shell wins over it), and the name you type`.
   - "4 — Config &amp; packs": ` and any third-party pack tarballs you installed from M5(.tgz) files. Without them a rebuilt host`
     becomes `. Packs need no copy of their own: each is pinned by name, version and integrity in the committed M5(package.json) and M5(pnpm-lock.yaml), and M5(pnpm install --frozen-lockfile) fetches it again from the pack store. Without it a rebuilt host`.
   - Provider lifecycle intro: `still prints the withdrawn disk install for step 2, so`
     becomes `still prints the withdrawn disk install for step 2 (<a href="gap-handoff.html#gap-015" style="font-weight:500;">GAP-015</a>), so`.
   - "Publishing a reviewed pack", step 3: `<strong>Upload</strong> to the M5(packs) bucket, keyed by the bare filename.`
     becomes `<strong>Upload two objects, then verify both.</strong> Upload the tarball to the M5(packs) bucket keyed M5(&lt;flattened-name&gt;-&lt;version&gt;.tgz), and its packument, the registry metadata derived from the tarball's own M5(package.json), keyed M5(@&lt;scope&gt;/&lt;name&gt;). The tarball alone is not publishable: without the packument, the scoped install in step 4 has nothing to resolve. Re-fetch both. The tarball must hash to the recorded integrity, and the packument's M5(dist.integrity) and M5(dist.tarball) must match it.`
   - Step 4: `<strong>Verify then pin.</strong> Re-fetch the uploaded tarball, confirm its hash matches the local file byte for byte, then pin the HTTPS specifier with M5(pnpm add --workspace-root --save-exact).`
     becomes `<strong>Pin.</strong> With the scope mapped in the deployment's M5(.npmrc), pin by scoped package name and version, never by the tarball's HTTPS URL, which pins without an integrity hash: M5(pnpm add -w "@forqsite-packs/&lt;name&gt;@&lt;version&gt;"). Run M5(pnpm verify:provider-pins) and confirm the lockfile entry carries both M5(integrity) and M5(tarball). Then run M5(pnpm install --frozen-lockfile) and commit M5(package.json) and M5(pnpm-lock.yaml).`
   - Known-gaps ledger: on the line after the `{ id: 'GAP-013', …` line, insert
     `      { id: 'GAP-015', pri: 'P2', priColor: P2, sum: 'The in-product pack install page prints pnpm add -w file:/path/to/pack.tgz, the install form the runbook withdrew, and nothing checks a pin made from it automatically.' },`
2. **gap-handoff.html template.** GAP-013 is unchanged. In the templates, `\'` is literal.
   - GAP-003's approach: `using EnvironmentFile=/etc/forqsite/env (secrets out of the repo dir, chmod 600), Restart=on-failure`
     becomes `with Restart=on-failure`. Then replace everything from `Caveat: ExecStart=/usr/bin/pnpm start`
     through `tsx directly).` with
     `Load the environment as forqsite\'s own scripts do: pnpm start already runs dotenv -e .env.local, and the scheduler unit must wrap tsx scripts/scheduler.ts in it, as scripts/dev.sh does. Values moved into the process manager, as first-run.md advises for production, win over .env.local, because forqsite runs dotenv without -o.`
   - GAP-003's third acceptance item: `without .env.local present in the working directory.`
     becomes `whether it comes from .env.local or from the process manager.`
   - Insert the entry below directly before `      mk('GAP-009'`, followed by one blank line.
   - Change `ten of them,` to `eleven of them,`, `<strong>008 and 013 whenever</strong>` to
     `<strong>008, 013 and 015 whenever</strong>`, and `P2 — DATA-SAFETY / CORRECTNESS / TOIL × 4` to `… × 5`.
     Leave every stamp alone, since the release restamps them.

   ```js
      mk('GAP-015', 'P2', 'CORRECTNESS', 'Stop the in-product pack install page printing the withdrawn file: install',
        'The platform-admin pack install page tells the operator to install a reviewed pack with pnpm add -w file:/path/to/pack.tgz. The operator runbook names that form as withdrawn: ADR 0004\'s invariant I1 requires an artifact stored outside any working tree. Nothing catches an operator who follows the page instead: nothing runs pnpm verify:provider-pins automatically, and a file: pin is the one form its review check cannot bind to a review record, because there is no tarball URL to match. The runbook withdrew the form the day after the page last changed, and the handover contract and the provider-reviews README moved with it. The page did not.',
        [['src/app/platform-admin/block-providers/install/page.tsx', 'install sequence, step 1: pnpm add -w file:/path/to/pack.tgz; last changed at 07d05a75, 2026-09-15'],
         ['docs/operator-runbook.md', '§14.2: the file: install "is withdrawn", since ac679353, 2026-09-16; §16 lists three live documents that state the install sequence, and the install page is not one of them'],
         ['docs/handoff/forqsite-sdk-handover-contract.md, docs/provider-reviews/README.md', 'both moved to the scoped pack-store install on 2026-09-16']],
        'Proposed: make step 1 print the runbook\'s §14.2 install, by scoped package name and version from the pack store, with its two checks: the sha512 against the one handed over, and a lockfile entry that carries both integrity and tarball. Or point step 1 at §14.2 instead of restating it. Either way, add the install page to the runbook\'s list of live documents that state the install sequence.',
        ['The install page prints no file: specifier.',
         'The page\'s install step and the runbook\'s §14.2 agree.',
         'The install page is on the runbook\'s list of live documents that state the install sequence.']),
   ```
3. **docs/claims-manifest.json.** Append the claim below to `claims`. Then append each of its
   `evidence` items that C-001 does not already hold to the end of C-001's `evidence`, so C-001
   stays the ordered union over S-07. Write the file back with
   `json.dumps(m, indent=2, ensure_ascii=False) + '\n'`. Set the note's date to the day you run
   the Tests. No existing claim's quote changes. In particular, no claim quotes any `-o` text,
   GAP-003's approach or acceptance text, or the other passages edited above, so no claim
   becomes `changed`.

   ```json
   {"id": "C-044", "page": "gap-handoff.html", "location": "GAP-015 entry, problem and evidence",
    "claim": "forqsite's in-product pack install page prints pnpm add -w file:/path/to/pack.tgz, which the operator runbook withdrew (ADR 0004's invariant I1); nothing runs verify:provider-pins automatically, a file: pin cannot be bound to a review record, and the install page is not on the runbook's list of live documents that state the install sequence.",
    "quote": "The operator runbook names that form as withdrawn",
    "evidence": [
     {"path": "src/app/platform-admin/block-providers/install/page.tsx", "symbol": "pnpm add -w file:/path/to/pack.tgz"},
     {"path": "docs/operator-runbook.md", "symbol": "**`pnpm add -w file:/path/to/<received-pack>.tgz` is withdrawn**"},
     {"path": "docs/operator-runbook.md", "symbol": "invariant I1 requires an artifact stored outside any working tree"},
     {"path": "docs/operator-runbook.md", "symbol": "This assertion is **not** run automatically."},
     {"path": "docs/operator-runbook.md", "symbol": "no record whose `artifact_url` equals this pin's tarball URL"},
     {"path": "docs/operator-runbook.md", "symbol": "**Three live documents state this install/pin sequence, and changing one obliges you to change all"}],
    "stamp": "S-07", "result": "added", "note": "ADDED: verified at the release commit on 2026-10-05."}
   ```
4. **README.md**, in the `gap-handoff.html` row: change `(10 items, GAP-003 to GAP-014;` to
   `(11 items, GAP-003 to GAP-015;`.
5. **docs/cer/backlog.md.** Append to the end of each Finding cell:
   - CER-051: ` **RESOLVED Phase 15 — CONTENT-041.**`
   - CER-048: ` **RESOLVED Phase 15 — CONTENT-041 (units and GAP-003 reconciled).**`
   - CER-049: ` **RESOLVED Phase 15 — CONTENT-041: operator ruling 2026-10-05, forqsite never uses dotenv -o, so index.html drops it and GAP-013 stands.**`
   - CER-059: ` **RESOLVED Phase 15 — CONTENT-041 (steps 3 and 4, and the Config & packs backup wording).**`
   - CER-058: ` **RESOLVED Phase 15 — CONTENT-041 (filed as GAP-015).**`

Ideology check: both bundles change only through `bundle-template.py`, which respects the
generated-artifact constraint. Nothing becomes external.

## Tests

From the repo root, run `FORQSITE_CLONE=<clone> bash <file>` with this block saved outside the
repo. The spec-writer ran it on 2026-10-05, after the operator rulings.
- On `main` it printed 42 `FAIL:` lines and exited 1. Every evidence literal and history check
  held at the pin.
- On a throwaway clone with Instructions 1 to 5 applied, it printed `OK` and all selftests passed.
  A headless render showed 11 gap cards, the new step 3 and the GAP-015 link.

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
r = lambda *a: subprocess.run(['git', '-C', os.environ['FORQSITE_CLONE'], *a], capture_output=True, text=True)
git = lambda *a: r(*a).returncode
for page, gone, now in [
    (I, 'EnvironmentFile', 'ExecStart=/usr/bin/pnpm exec dotenv -e .env.local -- tsx scripts/scheduler.ts'),
    (I, '/etc/forqsite/env', "because forqsite's dotenv calls do not pass " + M('-o') + '.'),
    (I, 'chmod 600', "forqsite's first-run guide says to move these values into your process manager or container environment instead;"),
    (I, 'dotenv -o', "As in forqsite's own scripts, a value already exported in the shell wins over the file."),
    (I, 'makes the file win', M('DATABASE_URL') + ' already exported in your shell wins over it)'),
    (I, 'pack tarballs you installed from', 'Packs need no copy of their own:'),
    (I, 'keyed by the bare filename', '<strong>Upload two objects, then verify both.</strong>'),
    (I, 'pnpm add --workspace-root --save-exact', "never by the tarball's HTTPS URL, which pins without an integrity hash: " + M('pnpm add -w "@forqsite-packs/&lt;name&gt;@&lt;version&gt;"', '12.5px')),
    (I, 'Verify then pin.', 'Then run ' + M('pnpm install --frozen-lockfile', '12.5px') + ' and commit'),
    (I, None, 'disk install for step 2 (<a href="gap-handoff.html#gap-015"'),
    (I, None, "{ id: 'GAP-015', pri: 'P2', priColor: P2,"),
    (G, '/etc/forqsite/env', 'the scheduler unit must wrap tsx scripts/scheduler.ts in it, as scripts/dev.sh does.'),
    (G, 'without .env.local present', 'whether it comes from .env.local or from the process manager.'),
    (G, 'dotenv -o', 'pnpm exec dotenv -e .env.local -- scripts/backup.sh, and the same for restore.sh.'),
    (G, None, "load .env.local the same way package.json\\'s start script does."),
    (G, None, 'a file: pin is the one form its review check cannot bind to a review record'),
    (G, 'ten of them,', 'eleven of them,'),
    (G, '<strong>008 and 013 whenever</strong>', '<strong>008, 013 and 015 whenever</strong>'),
    (G, 'TOIL × 4', 'TOIL × 5')]:
    ck(gone is None or n(gone) not in page, f'old text present: {gone!r}'); ck(page.count(n(now)) == 1, f'new text not once: {now!r}')
ck(not any(chr(0x200b) in t for t in raw.values()), 'U+200B remains')
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
    ('scripts/dev.sh', 'pnpm exec dotenv -e .env.local -- tsx scripts/scheduler.ts'),
    ('docs/first-run.md', 'For production, move those values into your process manager or'),
    ('docs/operator-runbook.md', 'DATABASE_URL=<the new URL> pnpm dotenv -- drizzle-kit migrate'), ('docs/operator-runbook.md', 'DATABASE_URL=<test url> pnpm db:reset'),
    ('docs/operator-runbook.md', 'pnpm add -w "@forqsite-packs/<name>@<version>"'), ('docs/operator-runbook.md', 'alternative either: it pins without an integrity hash.'),
    ('docs/operator-runbook.md', 'Install **by scoped package name and version**. Never by a filesystem path, and never by a bare'),
    ('docs/operator-runbook.md', '**A published version is two objects.**'), ('docs/operator-runbook.md', '| `@<scope>/<name>` | the packument, JSON | `application/json` |'),
    ('docs/operator-runbook.md', '3. **Verify what the store actually serves** — both objects, before anyone pins anything:'),
    ('docs/operator-runbook.md', 'pnpm install --frozen-lockfile'), ('docs/operator-runbook.md', 'Commit `package.json` and `pnpm-lock.yaml` once the')]
for p, s in ev: ck(git('grep', '-q', '-F', '-e', s, rel, '--', p) == 0, f'{s!r} not in {p} at the pin')
ck(git('grep', '-q', '-F', '-e', '/etc/forqsite/env', rel) == 1, '/etc/forqsite/env exists at the pin')
ck(git('grep', '-q', '-F', '-e', 'dotenv -o', rel) == 1, 'forqsite uses dotenv -o at the pin')
ck(git('grep', '-q', '-F', '-e', 'block-providers/install', rel, '--', 'docs/operator-runbook.md') == 1, 'runbook already lists the install page')
ck(r('log', '-1', '--format=%H %cs', rel, '--', 'src/app/platform-admin/block-providers/install/page.tsx').stdout.startswith('07d05a75') and '2026-09-15' in r('log', '-1', '--format=%cs', rel, '--', 'src/app/platform-admin/block-providers/install/page.tsx').stdout, 'page.tsx history')
for h, paths in (('ac679353', {'docs/operator-runbook.md', 'docs/provider-reviews/README.md'}), ('333d8e99', {'docs/handoff/forqsite-sdk-handover-contract.md'})):
    ck(git('merge-base', '--is-ancestor', h, rel) == 0 and r('show', '-s', '--format=%cs', h).stdout.strip() == '2026-09-16' and paths <= set(r('show', '--format=', '--name-only', h).stdout.split()), f'{h} history')
ck('(11 items, GAP-003 to GAP-015;' in open('README.md').read(), 'README count')
b = open('docs/cer/backlog.md').read()
for i in ('048', '049', '051', '058', '059'): ck(re.search(rf'^\| CER-{i} \|[^\n]*\*\*RESOLVED Phase 15 — CONTENT-041', b, re.M), f'CER-{i} not resolved')
ck(re.search(r'^\| CER-049 \|[^\n]*GAP-013 stands', b, re.M), 'CER-049 resolution text')
print('\n'.join(f'FAIL: {x}' for x in bad) or 'OK'); sys.exit(1 if bad else 0)
PY
```

Acceptance: `OK`, exit 0. Then run the suite: `for t in scripts/*-selftest.sh; do bash "$t" || exit 1; done`.

## Out of scope

- GAP-013's proposal, which stands as written (ruling 2).
- The rest of GAP-003, including its problem text and evidence (C-023).
- The Publishing route's "every HTTPS pack specifier in the lockfile" paragraph, and steps 1 and 2.
- `hint-placeholder-count` values, `copyCmd`, restamping and release (CONTENT-042), and CER-046/056.
