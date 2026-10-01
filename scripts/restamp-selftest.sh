#!/usr/bin/env bash
#
# restamp-selftest.sh — exercises scripts/restamp.py against throwaway fixture
# repositories: a fixture forqsite clone and a fixture forqsite.help repo. Needs no real
# forqsite clone and contacts no host.
#
# Fixture forqsite clone (fixed commit dates, all at noon UTC):
#   B  2026-01-01  base
#   X  2026-01-05  on a side branch from B
#   R  2026-01-10  the release: every claim's evidence
#   T  2026-01-20  descends from R; adds a file no claim cites
#   S  2026-01-25  descends from T; breaks C-007's evidence (and so the Known-gaps union)
#
# Fixture forqsite.help repo, slug fixture/forq, release R:
#   A0  scripts (restamp.py, stale-claims.py, bundle-template.py) and a README; older
#       annotated decoy tags rel-ffffffff (sorts first by name) and rel-00000001 (sorts
#       last) point at it
#   A1  both pages as released; annotated tag rel-<R8>, the newest
#   A2  the story commit: rewrites C-004's quote, adds C-008's GAP entry, and the manifest
#   Both bundles are built from templates with bundle-template.py's own encode(), loaded
#   through importlib; each template contains a "/" and a "</script>".
#   Stamps: S-01 ISO with <br>; S-02 and S-03 share one text on index.html; S-04 is the
#   gap-handoff.html long-form footer, whose new date (2026-02-03) has a one-digit day.
#   Claims: C-001 Known-gaps (union of S-04); C-002 changed, quote unchanged since the
#   tag; C-003 added, quote unchanged; C-004 changed after the tag (CHANGED:); C-005 open
#   with an unprefixed note and closed_by; C-006 unverified with marker; C-007 open;
#   C-008 added after the tag (ADDED:). One closed[] record, C-010.
#
# Cases, each on a fresh clone of the fixture repo:
#   (a) clean restamp to T     exit 0; exact summary; only the three files change; both
#                              bundles verify; each template changes only in stamps; the
#                              manifest equals the expected one byte for byte
#   (b) dry run                with an untracked file: exit 0, dry-run summary, nothing
#                              written
#   (c) refusals               each with its exit code and an unchanged git status and
#                              sha256 of the three files: 6, 4, 3, 7, 8, 9, 2, 64;
#                              the 9s include a staged bundle that fails to re-extract
#                              to the intended template, the last check before writing
#   (d) hygiene                no fixture or work-directory path in any output; every git
#                              subcommand run is read-only
#
# Every run uses HOME set to an empty directory and XDG_CONFIG_HOME unset.
# Exits non-zero if any case fails.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
SRC_SCRIPTS="$REPO_ROOT/scripts"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

FQ="$WORK_DIR/fixture-forqsite"
FH="$WORK_DIR/fixture-help"
EMPTY_HOME="$WORK_DIR/empty-home"
STUB_BIN="$WORK_DIR/stub-bin"
GIT_LOG="$WORK_DIR/git-subcommands"
HELPER="$WORK_DIR/helper.py"
ALL_OUTPUT="$WORK_DIR/all-output"
SLUG="fixture/forq"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
# Loading bundle-template.py through importlib must not drop a __pycache__ into a fixture.
export PYTHONDONTWRITEBYTECODE=1
export HOME="$EMPTY_HOME"
unset XDG_CONFIG_HOME
mkdir -p "$EMPTY_HOME"
: > "$ALL_OUTPUT"

FAILURES=0
PASS_COUNT=0
report() {
  local name="$1" ok="$2" detail="$3"
  if [ "$ok" -eq 0 ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — $detail"
    FAILURES=$((FAILURES + 1))
  fi
}

# Fixed dates for every fixture commit and tag.
at() { GIT_AUTHOR_DATE="$1T12:00:00+0000" GIT_COMMITTER_DATE="$1T12:00:00+0000" "${@:2}"; }
ident() { git -C "$1" config user.email "selftest@example.invalid"
          git -C "$1" config user.name "restamp-selftest"
          git -C "$1" config commit.gpgsign false
          git -C "$1" config tag.gpgsign false; }

# =====================================================================================
# Fixture forqsite clone
# =====================================================================================
q() { git -C "$FQ" "$@"; }
qcommit() { q add -A && at "$1" git -C "$FQ" commit -q -m "$2" && q rev-parse HEAD; }

git -c init.defaultBranch=main init -q "$FQ"
ident "$FQ"
printf 'fixture forqsite\n' > "$FQ/README"
B="$(qcommit 2026-01-01 "base")"
q checkout -q -b side
printf 'side\n' > "$FQ/side.txt"
X="$(qcommit 2026-01-05 "side branch")"
q checkout -q main
mkdir -p "$FQ/src" "$FQ/docs"
printf 'def start_app():\n    start_app()\n' > "$FQ/src/app.txt"
printf 'gap evidence one\ngap evidence two\n' > "$FQ/src/gap.txt"
printf 'fixed()\n' > "$FQ/src/fix.txt"
printf 'run the thing\n' > "$FQ/docs/run.md"
R="$(qcommit 2026-01-10 "release")"
printf 'unrelated\n' > "$FQ/NOTES.md"
T="$(qcommit 2026-01-20 "later, no evidence touched")"
printf 'gap evidence one\n' > "$FQ/src/gap.txt"
S="$(qcommit 2026-01-25 "breaks gap evidence two")"
R8="${R:0:8}"
T8="${T:0:8}"
: "$B" "$S"

# =====================================================================================
# Helper: builds templates, bundles and the manifest, and checks results
# =====================================================================================
cat > "$HELPER" <<'PYEOF'
import hashlib, importlib.util, json, os, sys

SLUG = 'fixture/forq'


def bt(repo):
    spec = importlib.util.spec_from_file_location(
        'bundle_template', os.path.join(repo, 'scripts', 'bundle-template.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def wrap(encoded, title):
    return ('<!doctype html><html><head><meta charset="utf-8"><title>' + title +
            '</title></head><body><script type="__bundler/template">' + encoded +
            '</script></body></html>\n')


def templates(r8, story):
    ref = f'{SLUG}@{r8}'
    step = 'run it twice now' if story else 'run it once'
    index = (
        '<!doctype html><html><body>\n'
        '<nav><a href="gap-handoff.html">Known gaps →</a>'
        f'<p class="stamp">repo: {ref}<br>verified: 2026-01-10</p></nav>\n'
        '<section><h2>Upgrade</h2><p>the app starts with start_app</p>'
        f'<footer>verified 2026-01-10 against {ref}</footer></section>\n'
        f'<section><h2>Providers</h2><p>{step}</p><p>this step is not verified</p>'
        f'<footer>verified 2026-01-10 against {ref}</footer></section>\n'
        '<script>var route = "ops/upgrade"; if (route) { nav(route); }</script>\n'
        '</body></html>\n')
    four = '<p>gap four is new</p>\n' if story else ''
    gap = (
        '<!doctype html><html><body><h1>Known gaps</h1>\n'
        '<p>gap one is open</p>\n<p>gap two is partly fixed</p>\n'
        '<p>gap three: the evidence two</p>\n' + four +
        f'<footer>known gaps · verified against {ref} · 10 january 2026</footer>\n'
        '<script>/* a/b */ var x = 1;</script>\n</body></html>\n')
    return {'index.html': index, 'gap-handoff.html': gap}


def manifest(r, r8):
    ref = f'{SLUG}@{r8}'
    ev = lambda p, s: {'path': p, 'symbol': s}
    c3 = [ev('src/gap.txt', 'gap evidence one')]
    c5 = [ev('src/fix.txt', 'fixed()')]
    c7 = [ev('src/gap.txt', 'gap evidence two')]
    c8 = [ev('src/app.txt', 'start_app()')]
    return {
        'release': {'repo': SLUG, 'commit': r, 'committed': '2026-01-10',
                    'pinned': '2026-01-10'},
        'stamps': [
            {'id': 'S-01', 'page': 'index.html', 'location': 'sidebar',
             'text': f'repo: {ref}<br>verified: 2026-01-10', 'commit': r8,
             'date': '2026-01-10', 'scope': 'the Known gaps callout'},
            {'id': 'S-02', 'page': 'index.html', 'location': 'Upgrade footer',
             'text': f'verified 2026-01-10 against {ref}', 'commit': r8,
             'date': '2026-01-10', 'scope': 'the Upgrade section'},
            {'id': 'S-03', 'page': 'index.html', 'location': 'Providers footer',
             'text': f'verified 2026-01-10 against {ref}', 'commit': r8,
             'date': '2026-01-10', 'scope': 'the Providers section'},
            {'id': 'S-04', 'page': 'gap-handoff.html', 'location': 'page footer',
             'text': f'known gaps · verified against {ref} · 10 january 2026',
             'commit': r8, 'date': '2026-01-10', 'scope': 'every GAP entry'},
        ],
        'claims': [
            {'id': 'C-001', 'page': 'index.html', 'location': 'sidebar',
             'claim': 'the gaps list is current', 'quote': 'Known gaps →',
             'evidence': c3 + c5 + c7 + c8, 'stamp': 'S-01',
             'note': 'Evidence is the union of the evidence of every claim whose stamp '
                     'is S-04, the gap-handoff.html footer stamp.'},
            {'id': 'C-002', 'page': 'index.html', 'location': 'Upgrade',
             'claim': 'the app starts', 'quote': 'the app starts with start_app',
             'evidence': [ev('src/app.txt', 'start_app()')], 'stamp': 'S-02',
             'result': 'changed', 'note': 'CHANGED: an earlier release reworded this.'},
            {'id': 'C-003', 'page': 'gap-handoff.html', 'location': 'gap one',
             'claim': 'gap one is open', 'quote': 'gap one is open', 'evidence': c3,
             'stamp': 'S-04', 'result': 'added',
             'note': 'ADDED: verified on 2026-01-10.'},
            {'id': 'C-004', 'page': 'index.html', 'location': 'Providers',
             'claim': 'run it twice', 'quote': 'run it twice now',
             'evidence': [ev('docs/run.md', 'run the thing')], 'stamp': 'S-03',
             'result': 'changed', 'note': 'CHANGED: the step said "run it once".'},
            {'id': 'C-005', 'page': 'gap-handoff.html', 'location': 'gap two',
             'claim': 'gap two is partly fixed', 'quote': 'gap two is partly fixed',
             'evidence': c5, 'stamp': 'S-04', 'result': 'open',
             'note': 'An unprefixed note that a restamp keeps.',
             'closed_by': {'commit': r, 'path': 'src/fix.txt'}},
            {'id': 'C-006', 'page': 'index.html', 'location': 'Providers',
             'claim': 'an unverifiable step', 'quote': 'this step is not verified',
             'evidence': [], 'stamp': 'S-03', 'result': 'unverified',
             'note': 'UNVERIFIED: the fixture has no evidence for it.',
             'marker': 'this step is not verified'},
            {'id': 'C-007', 'page': 'gap-handoff.html', 'location': 'gap three',
             'claim': 'gap three', 'quote': 'gap three: the evidence two',
             'evidence': c7, 'absent': [{'path': 'src/nope.txt'}], 'stamp': 'S-04',
             'result': 'open'},
            {'id': 'C-008', 'page': 'gap-handoff.html', 'location': 'gap four',
             'claim': 'gap four', 'quote': 'gap four is new', 'evidence': c8,
             'stamp': 'S-04', 'result': 'added',
             'note': 'ADDED: verified on 2026-01-12.'},
        ],
        'closed': [
            {'id': 'C-010', 'gap': 'GAP-901', 'claim': 'fixed',
             'closed_by': {'commit': r, 'path': 'src/fix.txt'},
             'evidence': [ev('src/fix.txt', 'fixed()')]},
        ],
    }


def dump(m):
    return json.dumps(m, indent=2, ensure_ascii=False) + '\n'


def write_pages(repo, r8, story):
    mod = bt(repo)
    for page, tpl in templates(r8, story).items():
        with open(os.path.join(repo, page), 'w', encoding='utf-8') as f:
            f.write(wrap(mod.encode(tpl), page))


def read_template(repo, page):
    mod = bt(repo)
    src = open(os.path.join(repo, page), encoding='utf-8').read()
    return json.loads(mod.TEMPLATE_RE.search(src).group(2))


def write_template(repo, page, tpl):
    mod = bt(repo)
    path = os.path.join(repo, page)
    src = open(path, encoding='utf-8').read()
    m = mod.TEMPLATE_RE.search(src)
    open(path, 'w', encoding='utf-8').write(src[:m.start(2)] + mod.encode(tpl) + src[m.end(2):])


def load(repo):
    return json.load(open(os.path.join(repo, 'docs', 'claims-manifest.json'), encoding='utf-8'))


def save(repo, m):
    open(os.path.join(repo, 'docs', 'claims-manifest.json'), 'w', encoding='utf-8').write(dump(m))


def fail(msg):
    print(msg)
    sys.exit(1)


def expected_manifest(before, t, t8):
    m = json.loads(json.dumps(before))
    old8 = m['release']['commit'][:8]
    m['release'].update(commit=t, committed='2026-01-20', pinned='2026-02-03')
    for st in m['stamps']:
        st['text'] = (st['text'].replace(f'{SLUG}@{old8}', f'{SLUG}@{t8}')
                      .replace('2026-01-10', '2026-02-03')
                      .replace('10 january 2026', '3 february 2026'))
        st['commit'] = t8
        st['date'] = '2026-02-03'
    for c in m['claims']:
        if c['id'] in ('C-002', 'C-003'):
            c['result'] = 'open'
            del c['note']
    return m


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == 'pages':                      # pages <repo> <r8> <0|1>
        write_pages(args[0], args[1], args[2] == '1')
    elif cmd == 'manifest':                 # manifest <repo> <r> <r8>
        save(args[0], manifest(args[1], args[2]))
    elif cmd == 'edit-manifest':            # edit-manifest <repo> <python body on m>
        m = load(args[0])
        exec(args[1])
        save(args[0], m)
    elif cmd == 'edit-template':            # edit-template <repo> <page> <old> <new>
        tpl = read_template(args[0], args[1])
        if args[2] not in tpl:
            fail('edit-template: anchor not found')
        write_template(args[0], args[1], tpl.replace(args[2], args[3], 1))
    elif cmd == 'unescape-slash':           # unescape-slash <repo> <page>
        path = os.path.join(args[0], args[1])
        src = open(path, encoding='utf-8').read()
        if '\\u002F' not in src:
            fail('no escaped slash')
        open(path, 'w', encoding='utf-8').write(src.replace('\\u002F', '/', 1))
        read_template(args[0], args[1])     # still parses
    elif cmd == 'snapshot':                 # snapshot <repo>
        for f in ('docs/claims-manifest.json', 'index.html', 'gap-handoff.html'):
            print(hashlib.sha256(open(os.path.join(args[0], f), 'rb').read()).hexdigest(), f)
    elif cmd == 'save-before':              # save-before <repo> <dir>
        for page in ('index.html', 'gap-handoff.html'):
            open(os.path.join(args[1], page + '.tpl'), 'w', encoding='utf-8').write(
                read_template(args[0], page))
        open(os.path.join(args[1], 'manifest.json'), 'w', encoding='utf-8').write(
            dump(load(args[0])))
    elif cmd == 'check-template':           # check-template <repo> <dir> <page> <r8> <t8>
        repo, d, page, r8, t8 = args
        old = open(os.path.join(d, page + '.tpl'), encoding='utf-8').read()
        want = (old.replace(f'{SLUG}@{r8}', f'{SLUG}@{t8}')
                .replace('2026-01-10', '2026-02-03')
                .replace('10 january 2026', '3 february 2026'))
        got = read_template(repo, page)
        if got == old:
            fail(f'{page} template unchanged')
        if got != want:
            fail(f'{page} template differs from the old one with only the stamps replaced')
        if page == 'gap-handoff.html' and '· 3 february 2026' not in got:
            fail('long-form date is not "3 february 2026"')
    elif cmd == 'check-manifest':           # check-manifest <repo> <dir> <t> <t8> <part>
        repo, d, t, t8, part = args
        before = json.load(open(os.path.join(d, 'manifest.json'), encoding='utf-8'))
        raw = open(os.path.join(repo, 'docs', 'claims-manifest.json'), encoding='utf-8').read()
        after = json.loads(raw)
        by_b = {c['id']: c for c in before['claims']}
        by_a = {c['id']: c for c in after['claims']}
        if part == 'release':
            if after['release'] != {'repo': SLUG, 'commit': t, 'committed': '2026-01-20',
                                    'pinned': '2026-02-03'}:
                fail(f'release is {after["release"]}')
        elif part == 'stamps':
            for st in after['stamps']:
                if st['commit'] != t8 or st['date'] != '2026-02-03' \
                        or f'{SLUG}@{t8}' not in st['text']:
                    fail(f'stamp {st["id"]} not restamped: {st}')
            if after['stamps'][3]['text'] != f'known gaps · verified against {SLUG}@{t8} · 3 february 2026':
                fail(f'S-04 text is {after["stamps"][3]["text"]}')
        elif part == 'reopened':
            for cid in ('C-002', 'C-003'):
                a, b = dict(by_a[cid]), dict(by_b[cid])
                if a.get('result') != 'open' or 'note' in a:
                    fail(f'{cid} is {a.get("result")} with note {a.get("note")!r}')
                a.pop('result'); b.pop('result'); b.pop('note')
                if a != b or list(by_a[cid]) != [k for k in by_b[cid] if k != 'note']:
                    fail(f'{cid} changed beyond result and note')
        elif part == 'carried':
            for cid in ('C-004', 'C-008'):
                if json.dumps(by_a[cid], ensure_ascii=False) != json.dumps(by_b[cid], ensure_ascii=False):
                    fail(f'{cid} not carried through byte-equal')
        elif part == 'kept':
            for cid in ('C-001', 'C-005', 'C-006', 'C-007'):
                if json.dumps(by_a[cid], ensure_ascii=False) != json.dumps(by_b[cid], ensure_ascii=False):
                    fail(f'{cid} changed')
            if by_a['C-005'].get('closed_by') != by_b['C-005']['closed_by'] \
                    or by_a['C-005'].get('note') != by_b['C-005']['note']:
                fail('C-005 note or closed_by changed')
            if after.get('closed') != before.get('closed'):
                fail('closed[] changed')
        elif part == 'whole':
            want = dump(expected_manifest(before, t, t8))
            if raw != want:
                fail('manifest is not byte-equal to the expected restamp')
    else:
        fail(f'unknown helper command {cmd}')


main()
PYEOF
helper() { python3 "$HELPER" "$@"; }

# =====================================================================================
# Fixture forqsite.help repo
# =====================================================================================
h() { git -C "$FH" "$@"; }
hcommit() { h add -A && at "$1" git -C "$FH" commit -q -m "$2" && h rev-parse HEAD; }
htag() { at "$2" git -C "$FH" tag -a -m "$1" "$1" "$3"; }

git -c init.defaultBranch=main init -q "$FH"
ident "$FH"
mkdir -p "$FH/scripts" "$FH/docs"
cp "$SRC_SCRIPTS/restamp.py" "$SRC_SCRIPTS/stale-claims.py" "$SRC_SCRIPTS/bundle-template.py" \
  "$FH/scripts/"
printf 'fixture forqsite.help\n' > "$FH/README"
A0="$(hcommit 2026-01-02 "scripts")"
htag rel-ffffffff 2026-01-03 "$A0"
htag rel-00000001 2026-01-04 "$A0"
helper pages "$FH" "$R8" 0
A1="$(hcommit 2026-01-11 "pages as released")"
htag "rel-$R8" 2026-01-12 "$A1"
helper pages "$FH" "$R8" 1
helper manifest "$FH" "$R" "$R8"
hcommit 2026-01-13 "story: rewrite a quote, add a gap" > /dev/null

# =====================================================================================
# git wrapper, first on PATH for restamp runs only: logs every subcommand
# =====================================================================================
REAL_GIT="$(command -v git)"
mkdir -p "$STUB_BIN"
: > "$GIT_LOG"
cat > "$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
args=("\$@")
i=0
while [ \$i -lt \${#args[@]} ]; do
  case "\${args[\$i]}" in
    -C|-c) i=\$((i + 2)) ;;
    -*) i=\$((i + 1)) ;;
    *) break ;;
  esac
done
printf '%s\n' "\${args[\$i]:-<none>}" >> "$GIT_LOG"
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$STUB_BIN/git"

# =====================================================================================
# Runner
# =====================================================================================
CASE=""
N_CASE=0
fresh() {
  N_CASE=$((N_CASE + 1))
  CASE="$WORK_DIR/case-$N_CASE"
  git clone -q "$FH" "$CASE"
  ident "$CASE"
}
ccommit() { git -C "$CASE" add -A && at 2026-01-14 git -C "$CASE" commit -q -m "$1"; }

OUT=""
STATUS=0
# run_restamp <label> <clone|unset> <args...>
run_restamp() {
  local label="$1" mode="$2"
  shift 2
  local envargs=(-u FORQSITE_CLONE -u XDG_CONFIG_HOME HOME="$EMPTY_HOME" PATH="$STUB_BIN:$PATH")
  if [ "$mode" = clone ]; then envargs+=(FORQSITE_CLONE="$FQ"); fi
  set +e
  OUT="$(cd "$WORK_DIR" && env "${envargs[@]}" python3 "$CASE/scripts/restamp.py" "$@" 2>&1)"
  STATUS=$?
  set -e
  { echo "--- $label ---"; printf '%s\n' "$OUT"; } >> "$ALL_OUTPUT"
}

state() { git -C "$CASE" status --porcelain; helper snapshot "$CASE"; }

# refuse <name> <want> <label> <mode> <args...>: asserts the exit code and that git
# status and the sha256 of the three files are unchanged by the run.
refuse() {
  local name="$1" want="$2" label="$3" mode="$4"
  shift 4
  local before after ok=0 detail=""
  before="$(state)"
  run_restamp "$label" "$mode" "$@"
  after="$(state)"
  if [ "$STATUS" -ne "$want" ]; then
    ok=1; detail="expected exit $want, got $STATUS: $(head -c 300 <<<"$OUT")"
  elif [ "$before" != "$after" ]; then
    ok=1; detail="git status or a file's sha256 changed"
  fi
  report "(c) $name exits $want and writes nothing" "$ok" "$detail"
}

check() {
  local name="$1" out
  shift
  if out="$(helper "$@" 2>&1)"; then report "$name" 0 ""; else report "$name" 1 "$out"; fi
}

# =====================================================================================
# (a) Clean restamp
# =====================================================================================
fresh
BEFORE_DIR="$WORK_DIR/before"
mkdir -p "$BEFORE_DIR"
helper save-before "$CASE" "$BEFORE_DIR"
run_restamp "a clean" clone --date 2026-02-03 "$T"
want="restamp: $SLUG $R8 -> $T8 on 2026-02-03: 8 claims: 4 open, 1 changed, 1 added, 1 unverified"
ok=0; detail=""
if [ "$STATUS" -ne 0 ]; then ok=1; detail="expected exit 0, got $STATUS: $OUT"
elif [ "$OUT" != "$want" ]; then ok=1; detail="got: $OUT"; fi
report "(a) clean restamp exits 0 with the exact summary line" "$ok" "$detail"

ok=0; detail=""
got="$(git -C "$CASE" status --porcelain)"
want_status=" M docs/claims-manifest.json"$'\n'" M gap-handoff.html"$'\n'" M index.html"
if [ "$got" != "$want_status" ]; then ok=1; detail="status: $(tr '\n' '|' <<<"$got")"; fi
report "(a) git status lists exactly the manifest and the two bundles" "$ok" "$detail"

for page in index.html gap-handoff.html; do
  ok=0; detail=""
  if ! python3 "$CASE/scripts/bundle-template.py" verify "$CASE/$page" > /dev/null 2>&1; then
    ok=1; detail="$page fails verify"
  fi
  report "(a) $page verifies after the restamp" "$ok" "$detail"
  check "(a) $page template changes only in <slug>@<R8> and the date, in its own form" \
    check-template "$CASE" "$BEFORE_DIR" "$page" "$R8" "$T8"
done
check "(a) release holds the target, its committer date and --date" \
  check-manifest "$CASE" "$BEFORE_DIR" "$T" "$T8" release
check "(a) every stamp holds the new commit, date and text" \
  check-manifest "$CASE" "$BEFORE_DIR" "$T" "$T8" stamps
check "(a) C-002 and C-003 re-derive to open with no note key, nothing else changed" \
  check-manifest "$CASE" "$BEFORE_DIR" "$T" "$T8" reopened
check "(a) post-tag changed and added claims are carried through byte-equal" \
  check-manifest "$CASE" "$BEFORE_DIR" "$T" "$T8" carried
check "(a) Known-gaps, unverified, unprefixed note, closed_by and closed[] unchanged" \
  check-manifest "$CASE" "$BEFORE_DIR" "$T" "$T8" kept
check "(a) the manifest equals the expected restamp byte for byte" \
  check-manifest "$CASE" "$BEFORE_DIR" "$T" "$T8" whole

# =====================================================================================
# (b) Dry run, with an untracked file present
# =====================================================================================
fresh
printf 'scratch\n' > "$CASE/untracked.txt"
before="$(state)"
run_restamp "b dry run" clone --dry-run --date 2026-02-03 "$T"
after="$(state)"
ok=0; detail=""
if [ "$STATUS" -ne 0 ]; then ok=1; detail="expected exit 0, got $STATUS: $OUT"
elif [ "$OUT" != "$want (dry run; nothing written)" ]; then ok=1; detail="got: $OUT"
elif [ "$before" != "$after" ]; then ok=1; detail="something was written"
elif [ "$(git -C "$CASE" status --porcelain)" != "?? untracked.txt" ]; then
  ok=1; detail="status: $(git -C "$CASE" status --porcelain | tr '\n' '|')"
fi
report "(b) dry run with an untracked file exits 0, prints the dry-run summary, writes nothing" "$ok" "$detail"

# =====================================================================================
# (c) Refusals
# =====================================================================================
fresh
printf 'changed\n' >> "$CASE/README"
refuse "an unstaged tracked change" 6 "c unstaged" clone --date 2026-02-03 "$T"

fresh
printf 'changed\n' >> "$CASE/README"
git -C "$CASE" add README
refuse "a staged tracked change" 6 "c staged" clone --date 2026-02-03 "$T"

fresh
refuse "target X (not a descendant of R)" 4 "c target X" clone --date 2026-02-03 "$X"
refuse "target R (the release itself)" 4 "c target R" clone --date 2026-02-03 "$R"
refuse "an unknown target" 4 "c unknown target" clone --date 2026-02-03 no-such-ref
refuse "a --date before T's commit date" 4 "c early date" clone --date 2026-01-15 "$T"

refuse "target S (a stale claim)" 3 "c target S" clone --date 2026-02-03 "$S"
ok=0; detail=""
if ! grep -qF -- '(--no-commits)' <<<"$OUT"; then ok=1; detail="no (--no-commits) header"
elif ! grep -qE '^C-007 stale ' <<<"$OUT"; then ok=1; detail="no C-007 stale line"; fi
report "(c) target S prints the checker's (--no-commits) report with the stale line" "$ok" "$detail"

fresh
for tg in $(git -C "$CASE" tag -l 'rel-*'); do git -C "$CASE" tag -d "$tg" > /dev/null; done
refuse "no rel- tag" 7 "c no tag" clone --date 2026-02-03 "$T"
ok=0; detail=""
if ! grep -qF -- "rel-$R8" <<<"$OUT"; then ok=1; detail="message does not name rel-$R8"; fi
report "(c) the no-tag refusal names the expected tag" "$ok" "$detail"

fresh
at 2026-01-14 git -C "$CASE" tag -a -m newer rel-00000000 HEAD
refuse "a newer rel-00000000" 7 "c newer tag" clone --date 2026-02-03 "$T"

fresh
at 2026-01-12 git -C "$CASE" tag -a -m tie rel-0000000b HEAD
refuse "two newest rel- tags sharing a creation time" 7 "c tie" clone --date 2026-02-03 "$T"

fresh
helper edit-manifest "$CASE" "next(c for c in m['claims'] if c['id'] == 'C-004')['result'] = 'open'"
ccommit "open with a new quote"
refuse "a new quote with result open" 8 "c new quote open" clone --date 2026-02-03 "$T"

fresh
helper edit-manifest "$CASE" "next(c for c in m['claims'] if c['id'] == 'C-004')['note'] = 'the step said run it once'"
ccommit "changed without CHANGED:"
refuse "a changed note without CHANGED:" 8 "c changed note" clone --date 2026-02-03 "$T"

fresh
helper edit-manifest "$CASE" "m['claims'][0]['evidence'].pop()"
ccommit "union missing a pair"
refuse "Known-gaps evidence missing a pair" 8 "c union missing" clone --date 2026-02-03 "$T"

fresh
helper edit-manifest "$CASE" "m['claims'][0]['evidence'].append(dict(m['claims'][0]['evidence'][0]))"
ccommit "union with a duplicate"
refuse "Known-gaps evidence with a duplicate pair" 8 "c union duplicate" clone --date 2026-02-03 "$T"

fresh
helper edit-template "$CASE" index.html '</body>' "<p>verified 2026-01-10 against $SLUG@$R8</p></body>"
ccommit "a stamp text once too often"
refuse "a stamp text occurring once too often" 9 "c extra stamp text" clone --date 2026-02-03 "$T"

fresh
helper edit-template "$CASE" gap-handoff.html '</body>' "<p>pinned at $SLUG@$R8</p></body>"
ccommit "slug outside a stamp"
refuse "<slug>@<R8> outside any stamp" 9 "c slug outside" clone --date 2026-02-03 "$T"

fresh
helper unescape-slash "$CASE" index.html
ccommit "one escaped slash unescaped"
refuse "a bundle that parses but fails verify" 9 "c corrupted bundle" clone --date 2026-02-03 "$T"

# The staging guard: bundle-template.py inject reads its template with universal
# newlines, so a template carrying CRLF injects and verifies, but does not re-extract to
# the intended template. Restamp must refuse after staging, before writing anything.
fresh
helper edit-template "$CASE" index.html '</body>' $'<p>a\r\nb</p></body>'
ccommit "a CRLF in the template"
refuse "a staged bundle that does not re-extract to the intended template" 9 "c staging" \
  clone --date 2026-02-03 "$T"

fresh
refuse "FORQSITE_CLONE unset" 2 "c unset" unset --date 2026-02-03 "$T"
refuse "no target" 64 "c no target" clone --date 2026-02-03
refuse "an unknown option" 64 "c unknown option" clone --bogus "$T"
refuse "--date 2026-2-3" 64 "c bad date" clone --date 2026-2-3 "$T"

# =====================================================================================
# (d) Hygiene
# =====================================================================================
ok=0; detail=""
for p in "$FQ" "$FH" "$WORK_DIR"; do
  if grep -qF -- "$p" "$ALL_OUTPUT"; then ok=1; detail="a fixture or work-directory path appears in output"; fi
done
report "(d) no fixture or work-directory path in any output" "$ok" "$detail"

ok=0; detail=""
ALLOWED=" rev-parse cat-file merge-base show status for-each-ref diff log ls-tree rev-list "
if [ ! -s "$GIT_LOG" ]; then
  ok=1; detail="the git wrapper logged nothing"
else
  while IFS= read -r sub; do
    case "$ALLOWED" in
      *" $sub "*) ;;
      *) ok=1; detail="ran git $sub" ;;
    esac
  done < "$GIT_LOG"
fi
report "(d) every git subcommand restamp and the checker ran is read-only" "$ok" "$detail"

# =====================================================================================
echo ""
echo "restamp-selftest: $PASS_COUNT passed, $FAILURES failed"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
exit 0
