#!/usr/bin/env python3
"""List the manifest claims whose forqsite evidence no longer holds at a newer commit.

docs/claims-manifest.json pins every published claim to one forqsite release commit
(`release.commit`). At release time, this script re-checks every claim, and every
`closed[]` record, at a newer forqsite commit (the target), and reports which ones went
stale. It reports and never edits: it writes nothing to the manifest, the pages or the
clone, and it never fetches. Rewriting a stale claim takes judgment, and is a reviewed
story (INFRA-016).

Usage:
    FORQSITE_CLONE=<path to a forqsite clone> stale-claims.py [--manifest FILE] <target>

    <target>          any commit-ish the clone resolves (a sha, a tag such as a
                      checkpoint tag, a remote-tracking branch). No default. If the clone
                      does not contain it, fetch it yourself first: this script never
                      fetches.
    --manifest FILE   the claims manifest. Defaults to docs/claims-manifest.json, resolved
                      from this script's own location, not the current directory.

    The clone is named only by the FORQSITE_CLONE environment variable. There is no flag
    for it, so a local path never lands in shell-quoted documentation, and no message
    this script prints contains it.

Checks, run at <target> for every record whatever its touched state:
    evidence {path, symbol}   passes when path is a blob at <target> and symbol matches it
    absent   {path, symbol}   passes when path is a blob at <target> and symbol does not
                              match it (a missing path fails)
    absent   {path}           passes when path does not exist at <target>
    counts   {path, suffix, n} passes when exactly n names in
                              `git ls-tree --name-only <target> <path>/` end in suffix
                              (one level, not recursive)

    Matching normalises whitespace on purpose (CER-011): runs of whitespace collapse to
    one space in both the symbol and the file, and the symbol must be a substring. A
    reindent or reflow therefore does not fail a claim whose meaning is unchanged, and an
    `absent` literal cannot hide behind a line break. A check that passes only after
    normalisation is reported as `whitespace-only match: <path>`. A renamed path fails as
    usual, because the page cites the old path; its failure line adds `renamed to <new>`.
    The script reads no page, so page-side rendering (CER-012) does not arise.

    A named path is touched when `git diff --quiet <release> <target> -- <path>` reports a
    difference: the net difference between the two commits, so a change that was later
    reverted is not a touch.

Verdicts:
    claims[], in this precedence:
      stale       a check fails
      unverified  the claim's result is `unverified`, or it records no checks at all
      holds       every check passes and a named path is touched
      untouched   every check passes and no named path is touched
    closed[] (decision 2 of INFRA-016):
      reopened    a check fails, or the record has no checks (nothing shows the fix holds)
      closed      every check passes

    For a stale or reopened record, the report lists the commits in <release>..<target>
    that touched that record's own paths, newest first. Every unverified claim is printed
    with its note and marker on every run.

Report (stdout): a header line, then one block per record in manifest order (claims,
then closed records) whose first line begins `<id> <verdict>`, then a summary line.

Exit codes:
    0   nothing is stale or reopened (unverified claims do not fail the run)
    2   configuration: FORQSITE_CLONE is unset, or is not the top of a git repository;
        or the manifest is unreadable, or lacks `release.commit` or `claims`
    3   at least one record is stale or reopened
    4   resolution: the target or the release commit is not in the clone, or the release
        commit is not an ancestor of the target
    5   a read-only git command failed unexpectedly while checking
    64  usage: no target, an extra argument, or an unknown option

Git is invoked as `git -C <clone> <subcommand>` via PATH, with read-only subcommands only:
rev-parse, cat-file, merge-base, diff, log, show, ls-tree, rev-list.
"""

import json
import os
import re
import subprocess
import sys

EXIT_OK = 0
EXIT_CONFIG = 2
EXIT_STALE = 3
EXIT_RESOLVE = 4
EXIT_GIT = 5
EXIT_USAGE = 64

CLONE_NAME = 'the clone named by FORQSITE_CLONE'
DEFAULT_MANIFEST = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'docs', 'claims-manifest.json')

USAGE = ('usage: FORQSITE_CLONE=<path to a forqsite clone> '
         'stale-claims.py [--manifest FILE] <target>')


class Fail(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def die(code, message):
    print(f'stale-claims: error: {message}', file=sys.stderr)
    sys.exit(code)


def parse_args(argv):
    """Hand-parsed, as bundle-template.py does: argparse would exit 2 on a usage error,
    and 2 is the configuration code here."""
    manifest = None
    positional = []
    i = 0
    options_done = False
    while i < len(argv):
        arg = argv[i]
        if not options_done and arg == '--':
            options_done = True
        elif not options_done and arg in ('-h', '--help'):
            print(__doc__)
            sys.exit(EXIT_OK)
        elif not options_done and arg == '--manifest':
            if i + 1 >= len(argv):
                die(EXIT_USAGE, f'--manifest needs a FILE\n{USAGE}')
            manifest = argv[i + 1]
            i += 1
        elif not options_done and arg.startswith('--manifest='):
            manifest = arg[len('--manifest='):]
        elif not options_done and arg.startswith('-'):
            die(EXIT_USAGE, f'unknown option {arg}\n{USAGE}')
        else:
            positional.append(arg)
        i += 1
    if len(positional) != 1:
        die(EXIT_USAGE, f'expected exactly one <target>\n{USAGE}')
    if positional[0].startswith('-') or not positional[0]:
        die(EXIT_USAGE, f'invalid <target>\n{USAGE}')
    return manifest or DEFAULT_MANIFEST, positional[0]


class Git:
    """Read-only access to the clone. stderr is always captured, never passed through,
    because git's own diagnostics name the clone's path."""

    ALLOWED = {'rev-parse', 'cat-file', 'merge-base', 'diff', 'log', 'show', 'ls-tree',
               'rev-list'}

    def __init__(self, clone):
        self.clone = clone
        self.env = dict(os.environ)
        self.env['GIT_LITERAL_PATHSPECS'] = '1'  # a path is a path, never a glob
        self.env['GIT_OPTIONAL_LOCKS'] = '0'     # never refresh the index
        self.env['GIT_TERMINAL_PROMPT'] = '0'
        self._blobs = {}

    def run(self, *args):
        if args[0] not in self.ALLOWED:
            raise AssertionError(f'git {args[0]} is not a read-only subcommand')
        try:
            proc = subprocess.run(['git', '-C', self.clone, *args], env=self.env,
                                  stdin=subprocess.DEVNULL, capture_output=True)
        except OSError:
            raise Fail(EXIT_CONFIG, 'git could not be run (is it on PATH?)')
        return proc.returncode, proc.stdout

    def must(self, *args):
        code, out = self.run(*args)
        if code != 0:
            raise Fail(EXIT_GIT, f'git {args[0]} failed unexpectedly in {CLONE_NAME}')
        return out

    def commit_of(self, rev):
        code, out = self.run('rev-parse', '--verify', '--quiet', f'{rev}^{{commit}}')
        if code != 0:
            return None
        return out.decode().strip()

    def blob(self, commit, path):
        """The decoded text of path at commit, or None when it is not a blob there."""
        key = (commit, path)
        if key not in self._blobs:
            code, out = self.run('cat-file', '-t', f'{commit}:{path}')
            if code != 0 or out.decode().strip() != 'blob':
                self._blobs[key] = None
            else:
                data = self.must('show', f'{commit}:{path}')
                self._blobs[key] = data.decode('utf-8', errors='replace')
        return self._blobs[key]

    def exists(self, commit, path):
        code, _ = self.run('cat-file', '-e', f'{commit}:{path}')
        return code == 0

    def count(self, commit, path, suffix):
        out = self.must('ls-tree', '-z', '--name-only', commit, f'{path}/')
        names = [n for n in out.decode('utf-8', errors='replace').split('\0') if n]
        return sum(1 for n in names if n.endswith(suffix))

    def touched(self, release, target, path):
        code, _ = self.run('diff', '--quiet', release, target, '--', path)
        if code not in (0, 1):
            raise Fail(EXIT_GIT, f'git diff failed unexpectedly in {CLONE_NAME}')
        return code == 1

    def renames(self, release, target):
        out = self.must('diff', '-z', '-M', '--name-status', '--diff-filter=R',
                        release, target)
        fields = out.decode('utf-8', errors='replace').split('\0')
        result = {}
        i = 0
        while i + 2 < len(fields):
            if fields[i].startswith('R'):
                result[fields[i + 1]] = fields[i + 2]
                i += 3
            else:
                i += 1
        return result

    def commits(self, release, target, paths):
        out = self.must('log', '--format=%h %s', f'{release}..{target}', '--', *paths)
        return [line for line in out.decode('utf-8', errors='replace').splitlines() if line]


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


def matches(symbol, text):
    """(normalised match, literal match)."""
    return norm(symbol) in norm(text), symbol in text


def check_record(git, rec, target, renames):
    """Run every check in rec at target. Returns (failures, notes, paths, n_checks)."""
    failures, notes, paths = [], [], []

    def missing(kind, path):
        line = f'{kind} {path}: path missing at target'
        if path in renames:
            line += f', renamed to {renames[path]}'
        return line

    evidence = rec.get('evidence') or []
    absent = rec.get('absent') or []
    counts = rec.get('counts') or []

    for ev in evidence:
        path, symbol = ev.get('path', ''), ev.get('symbol', '')
        paths.append(path)
        text = git.blob(target, path)
        if text is None:
            failures.append(missing('evidence', path))
            continue
        normalised, literal = matches(symbol, text)
        if not normalised:
            failures.append(f'evidence {path}: "{norm(symbol)}" not found')
        elif not literal:
            notes.append(f'whitespace-only match: {path}')

    for ab in absent:
        path = ab.get('path', '')
        paths.append(path)
        if 'symbol' in ab:
            text = git.blob(target, path)
            if text is None:
                failures.append(missing('absent', path))
            elif matches(ab['symbol'], text)[0]:
                failures.append(f'absent {path}: "{norm(ab["symbol"])}" now present')
        elif git.exists(target, path):
            failures.append(f'absent {path}: path now exists')

    for ct in counts:
        path, suffix, n = ct.get('path', ''), ct.get('suffix', ''), ct.get('n')
        paths.append(f'{path}/')
        found = git.count(target, path, suffix)
        if found != n:
            failures.append(f'counts {path}/*{suffix}: expected {n}, found {found}')

    unique = list(dict.fromkeys(paths))
    return failures, list(dict.fromkeys(notes)), unique, len(evidence) + len(absent) + len(counts)


def load_manifest(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)
    except (OSError, ValueError):
        raise Fail(EXIT_CONFIG, f'the manifest ({os.path.basename(path)}) could not be '
                                'read as JSON')
    if not isinstance(manifest, dict):
        raise Fail(EXIT_CONFIG, 'the manifest is not a JSON object')
    release = manifest.get('release')
    if not isinstance(release, dict) or not isinstance(release.get('commit'), str) \
            or not release['commit']:
        raise Fail(EXIT_CONFIG, 'the manifest lacks release.commit')
    if not isinstance(manifest.get('claims'), list):
        raise Fail(EXIT_CONFIG, 'the manifest lacks a claims array')
    closed = manifest.get('closed', [])
    if not isinstance(closed, list):
        raise Fail(EXIT_CONFIG, 'the manifest\'s closed field is not an array')
    return manifest


def open_clone():
    clone = os.environ.get('FORQSITE_CLONE', '')
    if not clone:
        raise Fail(EXIT_CONFIG, 'FORQSITE_CLONE is not set; set it to a local forqsite '
                                'clone that contains the target commit')
    if not os.path.isdir(clone):
        raise Fail(EXIT_CONFIG, f'{CLONE_NAME} is not a directory')
    git = Git(clone)
    code, out = git.run('rev-parse', '--is-bare-repository')
    if code != 0:
        raise Fail(EXIT_CONFIG, f'{CLONE_NAME} is not a git repository')
    if out.decode().strip() == 'true':
        return git
    # Pathspecs and ls-tree paths are relative to the working directory, so a
    # subdirectory of a work tree would silently check the wrong paths.
    code, out = git.run('rev-parse', '--show-prefix')
    if code != 0 or out.decode().strip():
        raise Fail(EXIT_CONFIG, f'{CLONE_NAME} is inside a git repository, not its top '
                                'level')
    return git


def run(manifest_path, target_arg):
    git = open_clone()
    manifest = load_manifest(manifest_path)
    release_arg = manifest['release']['commit']
    repo = manifest['release'].get('repo', '(unnamed repo)')

    target = git.commit_of(target_arg)
    if target is None:
        raise Fail(EXIT_RESOLVE, f'target {target_arg} is not in {CLONE_NAME}; fetch it '
                                 'there yourself (this script never fetches)')
    release = git.commit_of(release_arg)
    if release is None:
        raise Fail(EXIT_RESOLVE, f'release commit {release_arg[:8]} is not in '
                                 f'{CLONE_NAME}; fetch it there yourself')
    code, _ = git.run('merge-base', '--is-ancestor', release, target)
    if code == 1:
        raise Fail(EXIT_RESOLVE, f'release commit {release[:8]} is not an ancestor of '
                                 f'target {target_arg}; the range would be empty or '
                                 'backwards')
    if code != 0:
        raise Fail(EXIT_GIT, f'git merge-base failed unexpectedly in {CLONE_NAME}')

    n_commits = int(git.must('rev-list', '--count', f'{release}..{target}').decode().strip())
    renames = git.renames(release, target)

    lines = [f'stale-claims: {repo} {release[:8]} -> {target_arg} ({target[:8]}), '
             f'{n_commits} commits']
    tally = {'untouched': 0, 'holds': 0, 'stale': 0, 'unverified': 0}
    closed_tally = {'closed': 0, 'reopened': 0}
    failing = False

    def block(rec, verdict, head, failures, notes, paths):
        first = f'{rec.get("id", "?")} {verdict}  {head}'
        if notes:
            first += '  ' + '; '.join(notes)
        lines.append(first)
        for f in failures:
            lines.append(f'  fail: {f}')
        if verdict in ('stale', 'reopened'):
            commits = git.commits(release, target, paths) if paths else []
            if commits:
                lines.extend(f'  commit: {c}' for c in commits)
            else:
                lines.append('  commit: (none in range touched these paths)')

    for rec in manifest['claims']:
        failures, notes, paths, n_checks = check_record(git, rec, target, renames)
        touched = [p for p in paths if git.touched(release, target, p)]
        reasons = []
        if rec.get('result') == 'unverified':
            reasons.append('result is unverified')
        if n_checks == 0:
            reasons.append('no checks recorded')
        if failures:
            verdict = 'stale'
        elif reasons:
            verdict = 'unverified'
        elif touched:
            verdict = 'holds'
        else:
            verdict = 'untouched'
        tally[verdict] += 1
        failing = failing or verdict == 'stale'
        head = f'touched: {", ".join(touched)}' if touched else 'untouched'
        block(rec, verdict, head, failures, notes, paths)
        if verdict == 'unverified':
            lines.extend(f'  reason: {r}' for r in reasons)
        if verdict == 'unverified' or rec.get('result') == 'unverified':
            lines.append(f'  note: {rec.get("note", "(none)")}')
            lines.append(f'  marker: {rec.get("marker", "(none)")}')

    for rec in manifest.get('closed', []):
        failures, notes, paths, n_checks = check_record(git, rec, target, renames)
        verdict = 'reopened' if failures or n_checks == 0 else 'closed'
        closed_tally[verdict] += 1
        failing = failing or verdict == 'reopened'
        block(rec, verdict, f'gap {rec.get("gap", "(none)")}', failures, notes, paths)
        if n_checks == 0:
            lines.append('  reason: no checks recorded')

    n_claims = len(manifest['claims'])
    n_closed = len(manifest.get('closed', []))
    summary = (f'summary: {n_claims} claims: {tally["untouched"]} untouched, '
               f'{tally["holds"]} holds, {tally["stale"]} stale, '
               f'{tally["unverified"]} unverified; {n_closed} closed records')
    if n_closed:
        summary += f': {closed_tally["closed"]} closed, {closed_tally["reopened"]} reopened'
    lines.append(summary)
    print('\n'.join(lines))
    return EXIT_STALE if failing else EXIT_OK


def main(argv):
    try:
        sys.stdout.reconfigure(errors='replace')
    except AttributeError:
        pass
    manifest_path, target = parse_args(argv)
    try:
        return run(manifest_path, target)
    except Fail as e:
        die(e.code, e.message)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
