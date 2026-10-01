#!/usr/bin/env python3
"""Pin a newer forqsite release commit in the claims manifest and both bundles.

docs/claims-manifest.json pins every published claim to one forqsite release commit
(`release.commit`), and every stamp on index.html and gap-handoff.html prints that
commit and a verification date. Once no claim is stale at a newer forqsite commit (the
target), this script moves the pin there: it rewrites the manifest's `release` object,
every stamp's text on both pages, and every claim's `result`, as one mechanical change.
It never commits, tags, pushes, fetches or deploys, and it rewrites no prose: a stale
claim, a closed gap or a note that needs new wording is a reviewed story, made before a
restamp. Its meaning, as ruled by the operator on 2026-09-30, is that every recorded
evidence check passed at the target commit, which is weaker than Phase 12's hand
verification.

Usage:
    FORQSITE_CLONE=<path to a forqsite clone> restamp.py [--dry-run]
                                                        [--date YYYY-MM-DD] <target>

    <target>           any commit-ish the clone resolves (a sha, a checkpoint tag, a
                       remote-tracking branch). No default. This script never fetches.
    --dry-run          run every check and every computation, including staging and
                       verifying both new bundles outside the repository, then print the
                       summary with " (dry run; nothing written)" appended. Nothing in
                       the repository is written.
    --date YYYY-MM-DD  the verification date printed in the stamps and recorded as
                       release.pinned. Defaults to today. It may not precede the target's
                       committer date or the current release.pinned.
    -h, --help         print this text and exit 0.
    --                 ends options.

    The clone is named only by the FORQSITE_CLONE environment variable, and no message
    this script prints contains its path, this repository's path or a forqsite commit
    subject. This repository is the git top level that contains this script, never the
    current directory. The manifest is docs/claims-manifest.json and the pages are
    index.html and gap-handoff.html at that top level.

Exit codes (checks run in this order; the first failure decides the code, and nothing is
written until every check has passed):
    64   usage: no target, an extra target, a target beginning with -, an unknown or
         repeated option, or a malformed --date
    2    configuration: FORQSITE_CLONE is unset, not a directory or not the top of a git
         repository; this script is not inside a work tree; the manifest is unreadable,
         does not re-serialise byte for byte, or lacks release.{repo,commit,committed,
         pinned}, stamps or claims
    6    this repository has tracked changes, staged or unstaged (untracked files do not
         block)
    4    resolution: the target or the release commit is not in the clone; the target is
         the release commit; the target does not descend from the release commit; --date
         precedes the target's committer date or release.pinned
    9    a bundle fails `bundle-template.py verify` before any edit (the corrupted-bundle
         guard); a stamp-occurrence or quote-occurrence count is wrong; or a staged bundle
         fails verify or does not re-extract to the intended template
    7    previous release: no tag matches ^rel-[0-9a-f]{8}$; the two newest such tags share
         a creation time; the newest is not rel-<release.commit[:8]>; or that tag's commit
         lacks either page
    3    stale-claims.py --no-commits exits 3 at the target; its report is printed
    5    a git call, the checker (any exit other than 0 or 3) or bundle-template.py failed
         unexpectedly; any filesystem step of the write phase failed; or any other
         unexpected exception (the top-level guard)
    8    the manifest is inconsistent: a stamp record, the results derivation or the
         Known-gaps assertion
    0    restamped (with --dry-run: it would restamp)

Invariants (what the proving pass should attack):

  Refuses. Every refusal above leaves the manifest and both bundles byte-identical,
    because no file in the repository is opened for writing until every check has passed
    and both new bundles are staged. The one exit that can follow a write is 5 for a
    failed write itself (see the last paragraph below). There is no --allow-stale: a
    stale claim is fixed by a reviewed story first. No refusal leaves a temporary file in
    the repository either: staging happens in a temporary directory outside it, removed
    on every path.

  Rewrites, and only these three files:
    docs/claims-manifest.json  release.commit (the full target sha), release.committed
                               (the target's committer date, %cs), release.pinned
                               (--date); each stamp's commit, date and text; and each
                               claim's result and note, as derived below. Nothing else:
                               not evidence, absent, counts, marker, closed_by, closed[],
                               the Known-gaps claim, nor any other key. It is written as
                               json.dumps(m, indent=2, ensure_ascii=False) + '\\n', the
                               exact form it was read in (exit 2 otherwise).
    index.html, gap-handoff.html  only through bundle-template.py inject, and inside the
                               extracted template only each stamp's text: <slug>@<old8>
                               becomes <slug>@<new8>, and the stamp's old date becomes
                               --date in the same form (ISO, or the long form
                               "3 february 2026": unpadded day, lowercase English month
                               from a fixed table, never the locale's strftime).
                               A stamp date is matched as a whole token, with no digit
                               immediately before or after it, both when counted and
                               when replaced (never str.count or str.replace): so
                               "1 january 2026" is not found inside "11 january 2026",
                               nor "2026-01-10" inside "12026-01-10", and such a stamp
                               is refused (exit 8) rather than rewritten into a date
                               the manifest does not record.

  Results, derived against the pages at the previous-release tag (never HEAD):
    unverified  kept as it is; its note must start UNVERIFIED:
    open        a quote found in that page at the tag; a CHANGED:, ADDED: or UNVERIFIED:
                note is dropped, and an unprefixed note is kept
    changed / added  any other quote must already carry that result and its matching
                CHANGED: / ADDED: note, written by the story that changed it; it is
                carried through unchanged
    The Known-gaps claim (the one claim without a result) is never modified, but its
    evidence must have no duplicate pair and equal, as a set of (path, symbol), the union
    of the evidence of every claim under the gap-handoff.html stamp its note names.

  Exact counts. On each page's extracted template, before the edit: <slug>@<old8>
    occurs exactly once per stamp record on that page; each distinct stamp text occurs
    exactly k times, where k is the number of that page's records carrying it (two
    stamps may share a text); each new text occurs 0 times. After the edit: each old
    text 0 times, each new text k times, <slug>@<old8> 0 times, <slug>@<new8> once per
    record; and every claim's quote occurs as many times as before. A plain replace that
    would also hit an unrecorded mention, or miss one, is therefore refused (exit 9).

  Write order. Every check and computation first. Then both new bundles are staged in a
    temporary directory outside the repository: copied, injected, verified, and
    re-extracted and compared with the intended template. Only then, unless --dry-run,
    are the two bundles written, then the manifest last. Each file is written to a
    temporary sibling (mkstemp, write, fsync, copymode) and renamed over the original,
    so each file is either wholly old or wholly new. Every one of those steps sits inside
    one handler: a failure removes the sibling if it was created and exits 5 naming the
    file by basename, with the recovery below. The temporary directory is removed on
    every path.

  No traceback and no path, ever. main() runs everything inside a top-level guard: the
    tool's own failures exit with their codes, and any other exception exits 5 with a
    fixed message naming only the exception's class, never its text, which can carry a
    path. A write failure is always reported by the write handler, never by this guard.

  Why it never leaves a half-restamped tree. Nothing is written until nothing can still
    refuse, and the staged bundles have already been proven to inject and verify, so no
    check can fail between the first write and the last. What remains is three renames,
    each atomic. Only a killed process or a failed write (exit 5) can stop between them,
    and even then: the manifest, written last, still names the old release, so it never
    vouches for pages that do not carry its stamps; a run requires a tree with no tracked
    changes, so the partial state is exactly `git status`'s diff, which `git checkout --
    .` undoes (a killed write may also leave an untracked .restamp-* file to delete); and
    a rerun refuses that state (exit 6) rather than building on it.

The previous release is the newest tag matching ^rel-[0-9a-f]{8}$ in this repository,
ordered by `git for-each-ref --sort=-creatordate` (creation time, never name). Tags are
annotated, so their creation time is the tagging time. The first one is bootstrapped by
hand on main after INFRA-020 merges, at cp-13's commit, whose pages are byte-identical to
the deployed cp-12 pages that pin 1fda3228:

    git tag -a -m "release nullvalues/forqsite@1fda3228 (bootstrap: the pages at cp-13)" rel-1fda3228 'cp-13^{commit}'
    git push origin rel-1fda3228

Git is invoked via PATH with every inherited GIT_* variable removed, with
GIT_NO_LAZY_FETCH=1, GIT_OPTIONAL_LOCKS=0, GIT_TERMINAL_PROMPT=0 and
GIT_LITERAL_PATHSPECS=1, with stderr captured, and with read-only subcommands only:
rev-parse, cat-file, merge-base, show, status, for-each-ref. bundle-template.py and
stale-claims.py are run with this Python from this script's own directory.
"""

import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

EXIT_OK = 0
EXIT_CONFIG = 2
EXIT_STALE = 3
EXIT_RESOLVE = 4
EXIT_GIT = 5
EXIT_DIRTY = 6
EXIT_PREVIOUS = 7
EXIT_MANIFEST = 8
EXIT_BUNDLE = 9
EXIT_USAGE = 64

PAGES = ('index.html', 'gap-handoff.html')
KNOWN_GAPS_PAGE = 'index.html'
FOOTER_PAGE = 'gap-handoff.html'
MANIFEST_REL = os.path.join('docs', 'claims-manifest.json')
MONTHS = ('january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
          'september', 'october', 'november', 'december')
RESULTS = ('open', 'changed', 'added', 'unverified')
PREFIXES = ('CHANGED:', 'ADDED:', 'UNVERIFIED:')
TAG_RE = re.compile(r'^rel-[0-9a-f]{8}$')
ISO_RE = re.compile(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
STAMP_ID_RE = re.compile(r'S-\d+')

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BUNDLE_TOOL = os.path.join(SCRIPT_DIR, 'bundle-template.py')
CHECKER = os.path.join(SCRIPT_DIR, 'stale-claims.py')

CLONE_NAME = 'the clone named by FORQSITE_CLONE'
RECOVERY = ('The tree had no tracked changes before this run, so `git checkout -- .` '
            'restores it.')
USAGE = ('usage: FORQSITE_CLONE=<path to a forqsite clone> '
         'restamp.py [--dry-run] [--date YYYY-MM-DD] <target>')


class Fail(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def die(code, message):
    print(f'restamp: error: {message}', file=sys.stderr)
    sys.exit(code)


def parse_date(text):
    """An ISO date, strictly YYYY-MM-DD, or None."""
    if not isinstance(text, str) or not ISO_RE.match(text):
        return None
    try:
        return datetime.date.fromisoformat(text)
    except ValueError:
        return None


def date_token(form):
    """A date form as a whole token: no digit immediately before or after it, so
    '1 january 2026' never matches inside '11 january 2026', nor '2026-01-10' inside
    '12026-01-10'."""
    return re.compile(r'(?<![0-9])' + re.escape(form) + r'(?![0-9])')


def long_form(d):
    return f'{d.day} {MONTHS[d.month - 1]} {d.year}'


def parse_args(argv):
    """Hand-parsed, as stale-claims.py does: argparse would exit 2 on a usage error, and
    2 is the configuration code here."""
    dry_run = False
    date = None
    positional = []
    options_done = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if not options_done and arg == '--':
            options_done = True
        elif not options_done and arg in ('-h', '--help'):
            print(__doc__)
            sys.exit(EXIT_OK)
        elif not options_done and arg == '--dry-run':
            if dry_run:
                die(EXIT_USAGE, f'--dry-run given twice\n{USAGE}')
            dry_run = True
        elif not options_done and (arg == '--date' or arg.startswith('--date=')):
            if date is not None:
                die(EXIT_USAGE, f'--date given twice\n{USAGE}')
            if arg == '--date':
                if i + 1 >= len(argv):
                    die(EXIT_USAGE, f'--date needs YYYY-MM-DD\n{USAGE}')
                value = argv[i + 1]
                i += 1
            else:
                value = arg[len('--date='):]
            date = parse_date(value)
            if date is None:
                die(EXIT_USAGE, f'--date must be a real date written YYYY-MM-DD\n{USAGE}')
        elif not options_done and arg.startswith('-'):
            die(EXIT_USAGE, f'unknown option {arg}\n{USAGE}')
        else:
            positional.append(arg)
        i += 1
    if len(positional) != 1:
        die(EXIT_USAGE, f'expected exactly one <target>\n{USAGE}')
    if not positional[0] or positional[0].startswith('-'):
        die(EXIT_USAGE, f'invalid <target>\n{USAGE}')
    return dry_run, date or datetime.date.today(), positional[0]


class Git:
    """Read-only git in one directory. stderr is always captured and never printed,
    because git's own diagnostics name the directory's path."""

    ALLOWED = {'rev-parse', 'cat-file', 'merge-base', 'show', 'status', 'for-each-ref'}

    def __init__(self, where, name):
        self.where = where
        self.name = name
        # Inherited GIT_* variables (GIT_DIR, GIT_CONFIG_*, GIT_EXTERNAL_DIFF, ...) would
        # redirect or reconfigure git, so none reaches it (CER-054).
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.env['GIT_NO_LAZY_FETCH'] = '1'
        self.env['GIT_OPTIONAL_LOCKS'] = '0'
        self.env['GIT_TERMINAL_PROMPT'] = '0'
        self.env['GIT_LITERAL_PATHSPECS'] = '1'

    def run(self, *args):
        if args[0] not in self.ALLOWED:
            raise AssertionError(f'git {args[0]} is not a read-only subcommand')
        try:
            proc = subprocess.run(['git', '-C', self.where, *args], env=self.env,
                                  stdin=subprocess.DEVNULL, capture_output=True)
        except OSError:
            raise Fail(EXIT_CONFIG, 'git could not be run (is it on PATH?)')
        return proc.returncode, proc.stdout

    def must(self, *args):
        code, out = self.run(*args)
        if code != 0:
            raise Fail(EXIT_GIT, f'git {args[0]} failed unexpectedly in {self.name}')
        return out

    def commit_of(self, rev):
        code, out = self.run('rev-parse', '--verify', '--quiet', f'{rev}^{{commit}}')
        if code != 0:
            return None
        return out.decode().strip()

    def is_blob(self, commit, path):
        code, out = self.run('cat-file', '-t', f'{commit}:{path}')
        return code == 0 and out.decode().strip() == 'blob'

    def show_blob(self, commit, path):
        return self.must('show', '--no-ext-diff', '--no-textconv', f'{commit}:{path}')


# =====================================================================================
# Checks that need no computation: configuration, tree, resolution
# =====================================================================================

def open_clone():
    clone = os.environ.get('FORQSITE_CLONE', '')
    if not clone:
        raise Fail(EXIT_CONFIG, 'FORQSITE_CLONE is not set; set it to a local forqsite '
                                'clone that contains the target commit')
    if not os.path.isdir(clone):
        raise Fail(EXIT_CONFIG, f'{CLONE_NAME} is not a directory')
    git = Git(clone, CLONE_NAME)
    code, out = git.run('rev-parse', '--is-bare-repository')
    if code != 0:
        raise Fail(EXIT_CONFIG, f'{CLONE_NAME} is not a git repository')
    if out.decode().strip() == 'true':
        return git
    code, out = git.run('rev-parse', '--show-prefix')
    if code != 0 or out.decode().strip():
        raise Fail(EXIT_CONFIG, f'{CLONE_NAME} is inside a git repository, not its top '
                                'level')
    return git


def open_repo():
    git = Git(SCRIPT_DIR, 'this repository')
    code, out = git.run('rev-parse', '--is-inside-work-tree')
    if code != 0 or out.decode().strip() != 'true':
        raise Fail(EXIT_CONFIG, 'restamp.py is not inside a git work tree')
    code, out = git.run('rev-parse', '--show-toplevel')
    top = out.decode().strip() if code == 0 else ''
    if not top or not os.path.isdir(top):
        raise Fail(EXIT_CONFIG, 'the top level of this repository could not be found')
    return Git(top, 'this repository'), top


def serialise(manifest):
    return json.dumps(manifest, indent=2, ensure_ascii=False) + '\n'


def load_manifest(path):
    try:
        with open(path, 'r', encoding='utf-8', newline='') as f:
            text = f.read()
        manifest = json.loads(text)
    except (OSError, ValueError):
        raise Fail(EXIT_CONFIG, 'the manifest (claims-manifest.json) could not be read as '
                                'JSON')
    if not isinstance(manifest, dict):
        raise Fail(EXIT_CONFIG, 'the manifest is not a JSON object')
    if serialise(manifest) != text:
        raise Fail(EXIT_CONFIG, 'the manifest does not re-serialise byte for byte as '
                                "json.dumps(m, indent=2, ensure_ascii=False) + '\\n'; "
                                'refusing to rewrite a file whose formatting would change')
    release = manifest.get('release')
    if not isinstance(release, dict):
        raise Fail(EXIT_CONFIG, 'the manifest lacks a release object')
    for key in ('repo', 'commit', 'committed', 'pinned'):
        if not isinstance(release.get(key), str) or not release[key]:
            raise Fail(EXIT_CONFIG, f'the manifest lacks release.{key}')
    if not re.fullmatch(r'[0-9a-f]{40}', release['commit']):
        raise Fail(EXIT_CONFIG, 'release.commit is not a full 40-hex sha')
    if parse_date(release['pinned']) is None:
        raise Fail(EXIT_CONFIG, 'release.pinned is not a YYYY-MM-DD date')
    if not isinstance(manifest.get('stamps'), list):
        raise Fail(EXIT_CONFIG, 'the manifest lacks a stamps array')
    if not isinstance(manifest.get('claims'), list):
        raise Fail(EXIT_CONFIG, 'the manifest lacks a claims array')
    return manifest


def check_clean(repo):
    out = repo.must('status', '--porcelain', '--untracked-files=no')
    if out.strip():
        raise Fail(EXIT_DIRTY, 'this repository has tracked changes (staged or unstaged); '
                               'restamp only a clean tree, so its whole diff is the '
                               'restamp')


def resolve(clone, manifest, target_arg, date):
    target = clone.commit_of(target_arg)
    if target is None:
        raise Fail(EXIT_RESOLVE, f'target {target_arg} is not in {CLONE_NAME}; fetch it '
                                 'there yourself (this script never fetches)')
    release_arg = manifest['release']['commit']
    release = clone.commit_of(release_arg)
    if release is None:
        raise Fail(EXIT_RESOLVE, f'release commit {release_arg[:8]} is not in '
                                 f'{CLONE_NAME}; fetch it there yourself')
    if target == release:
        raise Fail(EXIT_RESOLVE, f'target {target_arg} is the release commit '
                                 f'{release[:8]}; there is nothing to restamp')
    code, _ = clone.run('merge-base', '--is-ancestor', release, target)
    if code == 1:
        raise Fail(EXIT_RESOLVE, f'target {target_arg} does not descend from the release '
                                 f'commit {release[:8]}')
    if code != 0:
        raise Fail(EXIT_GIT, f'git merge-base failed unexpectedly in {CLONE_NAME}')
    committed_text = clone.must('show', '-s', '--no-ext-diff', '--no-textconv',
                                '--format=%cs', target).decode().strip()
    committed = parse_date(committed_text)
    if committed is None:
        raise Fail(EXIT_GIT, f'git show gave no committer date in {CLONE_NAME}')
    if date < committed:
        raise Fail(EXIT_RESOLVE, f'--date {date.isoformat()} precedes the target\'s '
                                 f'committer date {committed_text}')
    pinned = parse_date(manifest['release']['pinned'])
    if date < pinned:
        raise Fail(EXIT_RESOLVE, f'--date {date.isoformat()} precedes release.pinned '
                                 f'{pinned.isoformat()}')
    return target, committed_text


# =====================================================================================
# bundle-template.py and stale-claims.py, as subprocesses
# =====================================================================================

def tool(*args):
    """Run bundle-template.py; its output names absolute paths, so it is never printed."""
    try:
        proc = subprocess.run([sys.executable, BUNDLE_TOOL, *args],
                              stdin=subprocess.DEVNULL, capture_output=True)
    except OSError:
        raise Fail(EXIT_GIT, 'bundle-template.py could not be run')
    return proc.returncode


def verify(bundle):
    return tool('verify', bundle) == 0


def extract(bundle, out):
    if tool('extract', bundle, out) != 0:
        raise Fail(EXIT_GIT, 'bundle-template.py extract failed unexpectedly')
    with open(out, 'r', encoding='utf-8', newline='') as f:
        return f.read()


def run_checker(manifest_path, target):
    try:
        proc = subprocess.run([sys.executable, CHECKER, '--no-commits', '--manifest',
                               manifest_path, target],
                              stdin=subprocess.DEVNULL, capture_output=True)
    except OSError:
        raise Fail(EXIT_GIT, 'stale-claims.py could not be run')
    if proc.returncode == 3:
        sys.stdout.write(proc.stdout.decode('utf-8', errors='replace'))
        sys.stdout.flush()
        raise Fail(EXIT_STALE, 'stale-claims.py reports stale claims or reopened gaps at '
                               'the target; fix them in a reviewed story first')
    if proc.returncode != 0:
        raise Fail(EXIT_GIT, f'stale-claims.py failed unexpectedly (exit {proc.returncode})')


# =====================================================================================
# The previous release
# =====================================================================================

def previous_release(repo, old8):
    out = repo.must('for-each-ref', '--sort=-creatordate',
                    '--format=%(refname:strip=2) %(creatordate:raw)', 'refs/tags/rel-*')
    tags = []
    for line in out.decode('utf-8', errors='replace').splitlines():
        parts = line.split(' ')
        if len(parts) >= 2 and TAG_RE.match(parts[0]):
            tags.append((parts[0], parts[1]))
    wanted = f'rel-{old8}'
    if not tags:
        raise Fail(EXIT_PREVIOUS, f'no previous-release tag (rel-<8 hex>) in this '
                                  f'repository; expected {wanted} at the commit whose pages '
                                  'pin the current release (see this script\'s header for '
                                  'the bootstrap)')
    if len(tags) > 1 and tags[0][1] == tags[1][1]:
        raise Fail(EXIT_PREVIOUS, f'the two newest previous-release tags, {tags[0][0]} and '
                                  f'{tags[1][0]}, share a creation time; the previous '
                                  'release is ambiguous')
    if tags[0][0] != wanted:
        raise Fail(EXIT_PREVIOUS, f'the newest previous-release tag is {tags[0][0]}, not '
                                  f'{wanted}, which the manifest\'s release commit needs')
    commit = repo.commit_of(f'refs/tags/{wanted}')
    if commit is None:
        raise Fail(EXIT_PREVIOUS, f'tag {wanted} does not name a commit')
    for page in PAGES:
        if not repo.is_blob(commit, page):
            raise Fail(EXIT_PREVIOUS, f'tag {wanted}\'s commit has no {page}')
    return wanted, commit


# =====================================================================================
# Manifest consistency (exit 8) and the stamp edit (exit 9)
# =====================================================================================

def plan_stamps(manifest, slug, old8, new8, date):
    """Validate every stamp record and compute its new text. Exit 8 on a bad record."""
    planned = []
    old_ref, new_ref = f'{slug}@{old8}', f'{slug}@{new8}'
    for st in manifest['stamps']:
        sid = st.get('id', '?') if isinstance(st, dict) else '?'
        if not isinstance(st, dict):
            raise Fail(EXIT_MANIFEST, 'a stamp record is not an object')
        text, sdate = st.get('text'), parse_date(st.get('date'))
        if st.get('page') not in PAGES:
            raise Fail(EXIT_MANIFEST, f'stamp {sid} is not on {" or ".join(PAGES)}')
        if st.get('commit') != old8:
            raise Fail(EXIT_MANIFEST, f'stamp {sid} commit is not {old8}')
        if not isinstance(text, str) or text.count(old_ref) != 1:
            raise Fail(EXIT_MANIFEST, f'stamp {sid} text does not contain {old_ref} '
                                      'exactly once')
        if sdate is None:
            raise Fail(EXIT_MANIFEST, f'stamp {sid} date is not a YYYY-MM-DD date')
        iso_n = len(date_token(sdate.isoformat()).findall(text))
        long_n = len(date_token(long_form(sdate)).findall(text))
        if (iso_n, long_n) == (1, 0):
            old_date, new_date = sdate.isoformat(), date.isoformat()
        elif (iso_n, long_n) == (0, 1):
            old_date, new_date = long_form(sdate), long_form(date)
        else:
            raise Fail(EXIT_MANIFEST, f'stamp {sid} text does not contain its date exactly '
                                      'once, as a whole token, in exactly one form (ISO or '
                                      'long)')
        new_text = text.replace(old_ref, new_ref)
        hits = list(date_token(old_date).finditer(new_text))
        if len(hits) != 1:
            raise Fail(EXIT_MANIFEST, f'stamp {sid} date is not separable from its commit')
        new_text = new_text[:hits[0].start()] + new_date + new_text[hits[0].end():]
        planned.append((st, text, new_text))
    for page in PAGES:
        by_text = {}
        for st, text, new_text in planned:
            if st['page'] == page:
                by_text.setdefault(text, set()).add(new_text)
        for text, news in by_text.items():
            if len(news) != 1:
                raise Fail(EXIT_MANIFEST, f'two {page} stamps share a text but not a date')
    return planned


def edit_page(template, page, planned, slug, old8, new8):
    """The stamp edit on one page's template, with every occurrence count asserted.
    Exit 9 on any count that is not exactly as the manifest records."""
    old_ref, new_ref = f'{slug}@{old8}', f'{slug}@{new8}'
    records = [(text, new_text) for st, text, new_text in planned if st['page'] == page]
    groups = {}
    for text, new_text in records:
        groups.setdefault((text, new_text), 0)
        groups[(text, new_text)] += 1

    found = template.count(old_ref)
    if found != len(records):
        raise Fail(EXIT_BUNDLE, f'{page}: {old_ref} occurs {found} times, but the manifest '
                                f'records {len(records)} stamps there')
    for (text, new_text), k in groups.items():
        if template.count(text) != k:
            raise Fail(EXIT_BUNDLE, f'{page}: a stamp text occurs {template.count(text)} '
                                    f'times, but {k} stamp record(s) carry it')
        if template.count(new_text) != 0:
            raise Fail(EXIT_BUNDLE, f'{page}: a new stamp text already occurs before the '
                                    'edit')

    new = template
    for (text, new_text), k in groups.items():
        new = new.replace(text, new_text, k)

    for (text, new_text), k in groups.items():
        if new.count(text) != 0 or new.count(new_text) != k:
            raise Fail(EXIT_BUNDLE, f'{page}: after the edit a stamp text does not occur '
                                    'exactly as recorded')
    if new.count(old_ref) != 0:
        raise Fail(EXIT_BUNDLE, f'{page}: {old_ref} still occurs after the edit')
    if new.count(new_ref) != len(records):
        raise Fail(EXIT_BUNDLE, f'{page}: {new_ref} occurs {new.count(new_ref)} times after '
                                f'the edit, not once per stamp record ({len(records)})')
    return new


def derive_results(manifest, current, previous):
    """Results per § Restamps and closed records. Mutates claims in place; returns the
    Known-gaps claim. Exit 8 on any inconsistency."""
    claims = manifest['claims']
    for c in claims:
        if not isinstance(c, dict):
            raise Fail(EXIT_MANIFEST, 'a claim is not an object')
        cid = c.get('id', '?')
        if c.get('page') not in PAGES:
            raise Fail(EXIT_MANIFEST, f'claim {cid} is not on {" or ".join(PAGES)}')
        quote = c.get('quote')
        if not isinstance(quote, str) or not quote or quote not in current[c['page']]:
            raise Fail(EXIT_MANIFEST, f'claim {cid} quote does not occur in its page\'s '
                                      'current template')
        if 'note' in c and not isinstance(c['note'], str):
            raise Fail(EXIT_MANIFEST, f'claim {cid} note is not a string')

    known_gaps = [c for c in claims if 'result' not in c]
    if len(known_gaps) != 1:
        raise Fail(EXIT_MANIFEST, f'{len(known_gaps)} claims have no result; exactly one '
                                  '(the Known-gaps claim) must')
    kg = known_gaps[0]

    for c in claims:
        if c is kg:
            continue
        cid, result, note = c.get('id', '?'), c.get('result'), c.get('note', '')
        if result not in RESULTS:
            raise Fail(EXIT_MANIFEST, f'claim {cid} result is not one of {", ".join(RESULTS)}')
        if not (c.get('evidence') or c.get('absent') or c.get('counts')) \
                and result != 'unverified':
            raise Fail(EXIT_MANIFEST, f'claim {cid} records no evidence, absent or counts '
                                      'but is not unverified; a stamp must not vouch for a '
                                      'claim with nothing to check')
        if result == 'unverified':
            if not note.startswith('UNVERIFIED:'):
                raise Fail(EXIT_MANIFEST, f'claim {cid} is unverified but its note does not '
                                          'start UNVERIFIED:')
            continue
        if c['quote'] in previous[c['page']]:
            c['result'] = 'open'
            if note.startswith(PREFIXES):
                del c['note']
            continue
        if result == 'changed' and note.startswith('CHANGED:'):
            continue
        if result == 'added' and note.startswith('ADDED:'):
            continue
        raise Fail(EXIT_MANIFEST, f'claim {cid} quote is new since the previous release, '
                                  'but the claim is not changed with a CHANGED: note or '
                                  'added with an ADDED: note')
    return kg


def check_known_gaps(manifest, kg):
    kid = kg.get('id', '?')
    if kg.get('page') != KNOWN_GAPS_PAGE:
        raise Fail(EXIT_MANIFEST, f'the Known-gaps claim {kid} is not on {KNOWN_GAPS_PAGE}')
    ids = set(STAMP_ID_RE.findall(kg.get('note', '')))
    if len(ids) != 1:
        raise Fail(EXIT_MANIFEST, f'the Known-gaps claim {kid} note names {len(ids)} stamp '
                                  'ids, not exactly one')
    sid = ids.pop()
    pages = [st.get('page') for st in manifest['stamps'] if st.get('id') == sid]
    if pages != [FOOTER_PAGE]:
        raise Fail(EXIT_MANIFEST, f'the Known-gaps claim {kid} note names {sid}, which is '
                                  f'not one stamp on {FOOTER_PAGE}')

    def pairs(c):
        ev = c.get('evidence') or []
        if not isinstance(ev, list) or not all(isinstance(e, dict) for e in ev):
            raise Fail(EXIT_MANIFEST, f'claim {c.get("id", "?")} evidence is malformed')
        out = [(e.get('path'), e.get('symbol')) for e in ev]
        if not all(isinstance(p, str) and isinstance(s, str) for p, s in out):
            raise Fail(EXIT_MANIFEST, f'claim {c.get("id", "?")} evidence is malformed')
        return out

    own = pairs(kg)
    if len(set(own)) != len(own):
        raise Fail(EXIT_MANIFEST, f'the Known-gaps claim {kid} evidence has a duplicate pair')
    union = set()
    for c in manifest['claims']:
        if c.get('stamp') == sid and c is not kg:
            union.update(pairs(c))
    if set(own) != union:
        raise Fail(EXIT_MANIFEST, f'the Known-gaps claim {kid} evidence is not the union of '
                                  f'the evidence of every {sid} claim '
                                  f'({len(union - set(own))} missing, '
                                  f'{len(set(own) - union)} extra)')


# =====================================================================================
# Writing
# =====================================================================================

def replace_file(path, data):
    """Write data to a temporary sibling and rename it over path: the file is either
    wholly old or wholly new."""
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.restamp-')
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        shutil.copymode(path, tmp)
        os.replace(tmp, path)
    except OSError:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        raise Fail(EXIT_GIT, f'writing {os.path.basename(path)} failed. {RECOVERY}')


def run(dry_run, date, target_arg):
    clone = open_clone()
    repo, top = open_repo()
    manifest_path = os.path.join(top, MANIFEST_REL)
    manifest = load_manifest(manifest_path)
    check_clean(repo)
    target, committed = resolve(clone, manifest, target_arg, date)

    bundles = {page: os.path.join(top, page) for page in PAGES}
    for page, bundle in bundles.items():
        if not verify(bundle):
            raise Fail(EXIT_BUNDLE, f'{page} fails bundle-template.py verify before any '
                                    'edit; refusing to inject into a bundle whose encoding '
                                    'does not round-trip')

    slug = manifest['release']['repo']
    old8, new8 = manifest['release']['commit'][:8], target[:8]
    tag, tag_commit = previous_release(repo, old8)

    run_checker(manifest_path, target)

    work = tempfile.mkdtemp(prefix='restamp-')
    try:
        current, previous = {}, {}
        for page, bundle in bundles.items():
            current[page] = extract(bundle, os.path.join(work, f'current-{page}'))
            prev_bundle = os.path.join(work, f'previous-bundle-{page}')
            with open(prev_bundle, 'wb') as f:
                f.write(repo.show_blob(tag_commit, page))
            previous[page] = extract(prev_bundle, os.path.join(work, f'previous-{page}'))

        planned = plan_stamps(manifest, slug, old8, new8, date)
        kg = derive_results(manifest, current, previous)
        check_known_gaps(manifest, kg)

        new_templates = {page: edit_page(current[page], page, planned, slug, old8, new8)
                         for page in PAGES}
        for c in manifest['claims']:
            page = c['page']
            if new_templates[page].count(c['quote']) != current[page].count(c['quote']):
                raise Fail(EXIT_BUNDLE, f'claim {c.get("id", "?")} quote occurs a different '
                                        'number of times after the stamp edit')

        manifest['release']['commit'] = target
        manifest['release']['committed'] = committed
        manifest['release']['pinned'] = date.isoformat()
        for st, _text, new_text in planned:
            st['commit'] = new8
            st['date'] = date.isoformat()
            st['text'] = new_text

        staged = {}
        for page, bundle in bundles.items():
            stage = os.path.join(work, f'staged-{page}')
            shutil.copyfile(bundle, stage)
            tpl = os.path.join(work, f'new-{page}')
            with open(tpl, 'w', encoding='utf-8', newline='') as f:
                f.write(new_templates[page])
            if tool('inject', stage, tpl) != 0:
                raise Fail(EXIT_GIT, f'bundle-template.py inject failed unexpectedly on '
                                     f'the staged {page}')
            if not verify(stage):
                raise Fail(EXIT_BUNDLE, f'the staged {page} fails verify after inject')
            if extract(stage, os.path.join(work, f'check-{page}')) != new_templates[page]:
                raise Fail(EXIT_BUNDLE, f'the staged {page} does not re-extract to the '
                                        'intended template')
            with open(stage, 'rb') as f:
                staged[page] = f.read()

        counts = {r: 0 for r in RESULTS}
        for c in manifest['claims']:
            if c is not kg:
                counts[c['result']] += 1
        summary = (f'restamp: {slug} {old8} -> {new8} on {date.isoformat()}: '
                   f'{len(manifest["claims"])} claims: {counts["open"]} open, '
                   f'{counts["changed"]} changed, {counts["added"]} added, '
                   f'{counts["unverified"]} unverified')

        if dry_run:
            print(summary + ' (dry run; nothing written)')
            return EXIT_OK
        for page in PAGES:
            replace_file(bundles[page], staged[page])
        replace_file(manifest_path, serialise(manifest).encode('utf-8'))
        print(summary)
        return EXIT_OK
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main(argv):
    """The top-level guard: a Fail exits with its own code, SystemExit passes through,
    and anything else exits 5 with a fixed message naming only the exception's class.
    str() of an exception can carry a path, so it is never printed, and no traceback is."""
    try:
        try:
            sys.stdout.reconfigure(errors='replace')
        except AttributeError:
            pass
        dry_run, date, target = parse_args(argv)
        return run(dry_run, date, target)
    except Fail as e:
        die(e.code, e.message)
    except SystemExit:
        raise
    except BaseException as e:
        die(EXIT_GIT, f'unexpected internal failure ({type(e).__name__}). {RECOVERY}')


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
