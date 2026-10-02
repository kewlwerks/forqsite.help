#!/usr/bin/env bash
#
# release.sh — the attended release job (INFRA-021, Phase 14). Re-checks every claim in
# docs/claims-manifest.json at a forqsite commit (the target). When none is stale, it
# restamps both bundles, commits, tags rel-<forqsite short sha>, deploys, drift-checks, and
# only then pushes. When a claim is stale, it writes a local report and stops so the
# operator can review the claims as a story. It is run by hand on the operator's host.
#
# Usage:
#   FORQSITE_CLONE=<path to your forqsite clone> release.sh [--dry-run | --yes] <target>
#   FORQSITE_CLONE=<path to your forqsite clone> release.sh [--dry-run | --yes] --latest-checkpoint
#   release.sh -h | --help
#
#   <target>             a commit-ish the forqsite clone resolves (a sha, a checkpoint tag).
#   --latest-checkpoint  the newest clone tag matching ^cp-PM[0-9]+-main$, by version sort.
#   --dry-run            the default: every check runs, restamp.py runs with --dry-run, and
#                        nothing is committed, tagged, deployed or pushed. Saying it is
#                        only explicit.
#   --yes                commit, tag, deploy, drift-check and push.
#
# What it does:
#   - Works in this repository: the git top level containing this script. It cd's there,
#     and runs its siblings (deploy.sh, drift-check.sh, restamp.py, stale-claims.py,
#     read-deploy-env.sh, the selftests) from this script's own directory.
#   - Reads the forqsite clone named by FORQSITE_CLONE with `git -C`, every inherited GIT_*
#     variable removed and GIT_NO_LAZY_FETCH=1, using rev-parse and for-each-ref only. It
#     never fetches, in the clone or here.
#   - For this repository and its siblings it unsets only the GIT_* variables that point git
#     at another repository, and GIT_CONFIG, which would make git config read a different
#     file from the one the push uses; every other inherited variable, GIT_CONFIG_* and
#     GIT_SSH_COMMAND included, applies on purpose, because the push needs the operator's
#     ssh setup, so the read-only and never-fetches claims hold only for a benign
#     environment.
#   - A url.<base>.pushInsteadOf rule can still send the push somewhere other than where git
#     ls-remote reads, and the exit-2 pushurl check deliberately does not catch it: fetching
#     over https and pushing over ssh to the same repository must be expressed that way,
#     never as an explicit pushurl that differs from the url (which is refused), and that
#     configuration is the operator's to own.
#   - Checks the preconditions below in order; the first failure decides the exit code.
#     Nothing is written until the restamp, except the stale-path report.
#   - Reads origin's state from origin itself with `git ls-remote origin refs/heads/main
#     'refs/tags/rel-*'` on every run, dry runs included. The remote-tracking ref is never
#     trusted: it is only as fresh as the operator's last fetch.
#   - When main is ahead of origin, lists by subject, before any write, the unpushed
#     commits the push will carry, and continues.
#   - Runs every scripts/*-selftest.sh, then `stale-claims.py --no-commits <target sha>`.
#   - Checker exit 0 (the clean path): restamp.py, the selftests again, a commit of exactly
#     docs/claims-manifest.json, index.html and gap-handoff.html, an annotated tag
#     rel-<t8>, `deploy.sh --ref rel-<t8>`, `drift-check.sh --ref rel-<t8>`, and only after
#     both pass, `git push --atomic origin refs/heads/main:refs/heads/main
#     refs/tags/rel-<t8>:refs/tags/rel-<t8>`.
#     The commit message is fixed:
#         release: <slug>@<t8>, <N> claims: <u> untouched, <h> holds, <v> unverified
#
#         <restamp.py's success line, verbatim>
#         holds: <space-separated ids of the claims that hold, in manifest order, or none>
#     Its counts and ids come from the --no-commits report, which carries manifest text
#     only, so no forqsite commit subject can reach the message.
#   - Checker exit 3 (the stale path), with or without --yes: writes the full report (with
#     forqsite commit subjects) to the gitignored .release-report.txt at the repo root,
#     under umask 077, prints the --no-commits report, and exits 3.
#   - Never prints the clone's path, this repository's path, the ssh alias, the remote
#     directory or the site URL. Git's own stderr (which names remotes and paths) is
#     captured to a scratch directory outside the repository and never printed.
#
# Constants:
#   RELEASE_BRANCH=main   the only branch a release is made from and pushed to.
#
# Exit codes (in check order; the first failure decides):
#   64  usage: no target and no --latest-checkpoint, or both; a second target; an unknown
#       option; --yes with --dry-run; any option given more than once; a target outside
#       deploy.sh's REF_RE class (letters, digits, _ . / ~ ^ -; no leading - . / ~ ^)
#   2   configuration: FORQSITE_CLONE unset, not a directory, not a git repository or not
#       its top level; this script not in a git work tree; deploy.sh --dry-run exits 2
#       (deploy host or directory unset); FORQSITE_HELP_SITE_URL resolves empty; the
#       manifest's release.repo or release.commit unreadable; the checker exits 2; or
#       remote.origin.pushurl is set and any of its values differs from the first
#       remote.origin.url, the one git ls-remote reads (neither URL is printed)
#   7   the current branch is not main (a detached HEAD included)
#   6   tracked changes: git status --porcelain --untracked-files=no is non-empty
#       (untracked files do not block)
#   5   deploy.sh --dry-run exits non-zero other than 2; git ls-remote origin fails or
#       lists no main; or the checker exits anything but 0, 2, 3 or 4
#   8   behind origin: origin's main is not a local commit or not an ancestor of HEAD, or
#       origin has a rel- tag missing here or at a different object (fetch and merge by
#       hand; this job never fetches)
#   10  unfinished release: the newest local ^rel-[0-9a-f]{8}$ tag (by creation date) is
#       not on origin at the same object; or release.commit already equals the target but
#       rel-<t8> does not exist locally; or the target differs from release.commit but
#       rel-<t8> already exists here or on origin
#   4   --latest-checkpoint finds no matching clone tag; the target does not resolve in
#       the clone; or the checker exits 4
#   9   a selftest fails before the restamp (the failing names are printed)
#   3   the checker reports a stale claim or a reopened gap: review needed
#   11  restamp.py exits non-zero (its code is printed), or changes anything other than
#       the three files
#   12  a selftest fails after the restamp (or changes a tracked file)
#   13  git commit fails, or the commit holds anything but the three files
#   14  git tag fails
#   15  deploy.sh fails (its code is printed)
#   16  drift-check.sh fails (its code is printed)
#   17  git push fails
#   0   released; already released (release.commit is the target and rel-<t8> exists
#       locally); or, in a dry run, it would release
#
# Invariants (what the proving pass should attack):
#
#   Never pushes a release that has not deployed and passed the drift check. The only
#     `git push` in this script is the last step of the --yes clean path. It runs only
#     after deploy.sh has exited 0 and drift-check.sh --ref rel-<t8> (served bytes against
#     the release commit's bytes) has exited 0. deploy.sh's exit alone is not trusted.
#     Every earlier stop exits before the push, and no stop pushes anything.
#
#   Never rolls back on its own. It never runs deploy.sh --rollback. After exit 16 it
#     prints the ready-to-paste rollback command; running it stays the operator's call.
#
#   Read-only before the restamp. Every refusal up to and including 9 and 3 leaves HEAD,
#     the index, every tracked file, every local ref and every origin ref as they were,
#     and invokes no ssh: ls-remote downloads no objects and writes no refs; status runs
#     with GIT_OPTIONAL_LOCKS=0, so it does not refresh the index; deploy.sh runs only
#     with --dry-run, which makes no ssh call; the checker and restamp --dry-run write
#     nothing. Scratch output goes to a mktemp directory outside the repository, removed
#     on exit. The only file a refusal path writes is the stale path's
#     .release-report.txt, which is gitignored.
#
#   The dry run writes nothing in the repository, with one exception: on the stale path
#     it writes .release-report.txt exactly as --yes does (operator ruling 2026-10-01).
#
#   The stale path (exit 3) is identical with or without --yes, and touches nothing but
#     the report. The report's commit subjects can name a deployment, so it never reaches
#     stdout and is never committed; stdout carries only the --no-commits report and three
#     fixed lines, so it stays quotable.
#
#   No-op is not a cover for an unfinished release. An unpushed newest rel- tag is caught
#     (exit 10) before the "already released" test, because after a drift failure the
#     local commit already pins the target.
#
#   Pushes where it reads. When remote.origin.pushurl is set, git pushes to every pushurl
#     and never to the url, so the job refuses (exit 2), before origin is first read,
#     unless every pushurl equals the first remote.origin.url, the one git ls-remote
#     reads. With several remote.origin.url values and no pushurl, git pushes to every
#     url: the first, the one git ls-remote reads, is among them, so the release is still
#     seen there, but it also lands on the others. The push names both sides of each
#     refspec, so no remote.origin.push refspec can map it elsewhere.
#
# State each failure leaves, and its exact recovery (commands run from the repo root):
#   64 2 7 6 5 8 10 4 9 3   nothing written (3: only .release-report.txt). Fix the cause
#                           and run again. 8: fetch and merge by hand, then run again.
#                           10: printed with the tag's own recovery, below.
#   11  restamp.py writes nothing on a refusal. If a failed write left tracked changes
#       (restamp exit 5) or it changed an unexpected file, the job prints:
#           git restore --staged --worktree -- .
#       (the tree had no tracked changes before the run, so this restores it).
#   12, 13  nothing was committed; the restamped files are in the work tree (13: staged):
#           git restore --staged --worktree -- docs/claims-manifest.json index.html gap-handoff.html
#       A 13 whose commit was made but holds other files prints `git reset --keep <PRE>`.
#   14  the release commit exists, untagged and unpushed; nothing deployed. To abandon it:
#           git reset --keep <PRE>
#   15, 16  the commit and the annotated tag rel-<t8> exist locally; nothing pushed; the
#       site may serve the release (15: partly). To finish it:
#           scripts/deploy.sh --ref rel-<t8>
#           scripts/drift-check.sh --ref rel-<t8>
#           git push --atomic origin refs/heads/main:refs/heads/main refs/tags/rel-<t8>:refs/tags/rel-<t8>
#       To abandon it (the reset precedes the redeploy, because deploy.sh refuses bundles
#       that differ from its ref):
#           git tag -d rel-<t8>
#           git reset --keep <PRE>
#           scripts/deploy.sh
#           scripts/drift-check.sh
#       After 16, when the deploy printed its stamp S, also, instead of the redeploy:
#           scripts/deploy.sh --rollback <S>
#           scripts/drift-check.sh
#       with one more line when the deploy's backups line lacks any of index.html.bak-S,
#       gap-handoff.html.bak-S or site-provenance.json.bak-S: that set is incomplete and
#       deploy.sh --rollback refuses it (exit 6), so the abandon steps apply.
#   17  deployed and drift-checked, not pushed. To finish it:
#           git push --atomic origin refs/heads/main:refs/heads/main refs/tags/rel-<t8>:refs/tags/rel-<t8>
#       If origin has moved, resolve it by hand.
#   <PRE> is HEAD before the run, printed in full. A rerun after 14, 15 or 16 refuses
#   with 10, printing the same recovery, until the operator finishes or abandons the
#   release. A run killed between steps (no recovery printed) is caught the same way by
#   the next run: killed after the restamp and before the commit, it refuses with 6
#   (restore the three files as for 12); killed after the commit, with 10 (no tag yet:
#   the release commit pins the target without rel-<t8>; tag made: rel-<t8> is not on
#   origin), printing the recovery.

set -euo pipefail

RELEASE_BRANCH=main
REF_RE='^[A-Za-z0-9_][A-Za-z0-9._/~^-]*$'
REL_TAG_RE='^rel-[0-9a-f]{8}$'
CP_TAG_RE='^cp-PM[0-9]+-main$'
SHA_RE='^[0-9a-f]{40}([0-9a-f]{24})?$'
RELEASE_FILES=(docs/claims-manifest.json index.html gap-handoff.html)
REPORT=".release-report.txt"
USAGE="usage: release.sh [--dry-run | --yes] <target> | release.sh [--dry-run | --yes] --latest-checkpoint"
SELF="${BASH_SOURCE[0]}"

say() { printf 'release: %s\n' "$*"; }
fail() {
  local code="$1"
  shift
  printf 'release: error: %s\n' "$*" >&2
  exit "$code"
}
usage_error() {
  printf 'release.sh: %s\n%s\n' "$1" "$USAGE" >&2
  exit 64
}

# --- Usage (exit 64), before any git or ssh work ---------------------------------------
DRY_GIVEN=0
YES_GIVEN=0
LATEST=0
TARGET=""
TARGET_GIVEN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      awk 'NR == 1 { next } /^#/ { sub(/^#/, ""); print; next } { exit }' "$SELF"
      exit 0
      ;;
    --dry-run)
      [ "$DRY_GIVEN" -eq 0 ] || usage_error "--dry-run given more than once"
      DRY_GIVEN=1
      ;;
    --yes)
      [ "$YES_GIVEN" -eq 0 ] || usage_error "--yes given more than once"
      YES_GIVEN=1
      ;;
    --latest-checkpoint)
      [ "$LATEST" -eq 0 ] || usage_error "--latest-checkpoint given more than once"
      LATEST=1
      ;;
    -*)
      usage_error "unrecognized option (the options are --dry-run, --yes, --latest-checkpoint and --help)"
      ;;
    *)
      [ "$TARGET_GIVEN" -eq 0 ] || usage_error "more than one target given"
      TARGET="$1"
      TARGET_GIVEN=1
      ;;
  esac
  shift
done
if [ "$TARGET_GIVEN" -eq 0 ] && [ "$LATEST" -eq 0 ]; then
  usage_error "give a target or --latest-checkpoint"
fi
if [ "$TARGET_GIVEN" -eq 1 ] && [ "$LATEST" -eq 1 ]; then
  usage_error "give a target or --latest-checkpoint, not both"
fi
if [ "$YES_GIVEN" -eq 1 ] && [ "$DRY_GIVEN" -eq 1 ]; then
  usage_error "--yes and --dry-run contradict each other"
fi
if [ "$TARGET_GIVEN" -eq 1 ] && ! [[ "$TARGET" =~ $REF_RE ]]; then
  usage_error "the target is outside the accepted class (letters, digits, _ . / ~ ^ -; must begin with a letter, digit or _)"
fi
DRY_RUN=1
[ "$YES_GIVEN" -eq 0 ] || DRY_RUN=0

# --- This repository -------------------------------------------------------------------
# Variables that would point git at another repository are dropped: every sibling
# resolves the repository from the working directory, as this script does. GIT_CONFIG is
# dropped too: it makes git config read another file than the one the push uses.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX GIT_CONFIG
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
# A relative FORQSITE_CLONE means relative to where the operator ran this, not to the
# repository root this script changes into below.
if [ -n "${FORQSITE_CLONE:-}" ]; then
  case "$FORQSITE_CLONE" in
    /*) ;;
    *) FORQSITE_CLONE="$PWD/$FORQSITE_CLONE" ;;
  esac
  export FORQSITE_CLONE
fi
REPO="$(git -C "$SELF_DIR" rev-parse --show-toplevel 2>/dev/null)" \
  || fail 2 "release.sh is not inside a git work tree"
cd "$REPO"
# shellcheck source=read-deploy-env.sh
. "$SELF_DIR/read-deploy-env.sh"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# --- The forqsite clone: read-only, no inherited GIT_*, no lazy fetch ------------------
clone_git() {
  case "$1" in
    rev-parse|for-each-ref) ;;
    *) echo "release.sh: internal error: git $1 is not a read-only subcommand" >&2; exit 5 ;;
  esac
  (
    for v in $(compgen -e); do
      case "$v" in GIT_*) unset "$v" ;; esac
    done
    export GIT_NO_LAZY_FETCH=1
    exec git -C "$FORQSITE_CLONE" "$@"
  )
}

tracked_status() {
  GIT_OPTIONAL_LOCKS=0 git status --porcelain --untracked-files=no
}

# The step-6 recovery for a stop after the tag exists (15, 16, and an unfinished release).
print_finish_abandon() {
  local tag="$1" pre="$2"
  say "to finish it:"
  say "  scripts/deploy.sh --ref ${tag}"
  say "  scripts/drift-check.sh --ref ${tag}"
  say "  git push --atomic origin refs/heads/${RELEASE_BRANCH}:refs/heads/${RELEASE_BRANCH} refs/tags/${tag}:refs/tags/${tag}"
  say "to abandon it:"
  say "  git tag -d ${tag}"
  say "  git reset --keep ${pre}"
  say "  scripts/deploy.sh"
  say "  scripts/drift-check.sh"
}

restore_line() {
  say "  git restore --staged --worktree -- ${RELEASE_FILES[*]}"
}

# --- 2: FORQSITE_CLONE ---------------------------------------------------------------------
[ -n "${FORQSITE_CLONE:-}" ] \
  || fail 2 "FORQSITE_CLONE is not set; set it to a local forqsite clone that contains the target"
[ -d "$FORQSITE_CLONE" ] || fail 2 "the clone named by FORQSITE_CLONE is not a directory"
bare="$(clone_git rev-parse --is-bare-repository 2>/dev/null)" \
  || fail 2 "the clone named by FORQSITE_CLONE is not a git repository"
if [ "$bare" != "true" ]; then
  prefix="$(clone_git rev-parse --show-prefix 2>/dev/null)" \
    || fail 2 "the clone named by FORQSITE_CLONE is not a git repository"
  [ -z "$prefix" ] \
    || fail 2 "the clone named by FORQSITE_CLONE is inside a git repository, not its top level"
fi

# --- 7: on main ----------------------------------------------------------------------------
branch="$(git symbolic-ref -q --short HEAD 2>/dev/null || true)"
[ "$branch" = "$RELEASE_BRANCH" ] \
  || fail 7 "the current branch is not ${RELEASE_BRANCH} (a detached HEAD counts); a release is made only from ${RELEASE_BRANCH}"

# --- 6: no tracked changes -----------------------------------------------------------------
dirty="$(tracked_status 2>/dev/null)" || fail 6 "git status failed; the tree cannot be shown clean"
[ -z "$dirty" ] \
  || fail 6 "this repository has tracked changes (staged or unstaged); release only a clean tree (untracked files do not block)"

# --- 2 / 5: deploy configuration, by deploy.sh's own dry run; the site URL ------------------
rc=0
"$SELF_DIR/deploy.sh" --dry-run --ref HEAD > "$SCRATCH/deploy-dry.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  cat "$SCRATCH/deploy-dry.out" >&2
  [ "$rc" -ne 2 ] || fail 2 "deploy.sh --dry-run reports missing or invalid configuration (exit 2)"
  fail 5 "deploy.sh --dry-run --ref HEAD failed (exit ${rc})"
fi
SITE_URL="${FORQSITE_HELP_SITE_URL:-}"
if [ -z "$SITE_URL" ] && [ -f scripts/deploy.env ]; then
  # The environment wins (CER-035); the file is data, never executed (CER-024).
  read_deploy_env "scripts/deploy.env" "release.sh" || exit 2
  SITE_URL="${DEPLOY_ENV_SITE_URL:-}"
fi
[ -n "$SITE_URL" ] \
  || fail 2 "missing configuration: set FORQSITE_HELP_SITE_URL in the environment, or in scripts/deploy.env"

# --- 2: origin is pushed where it is read ---------------------------------------------------
# git ls-remote reads the first remote.origin.url. When remote.origin.pushurl is set, git
# pushes to every pushurl and never to the url, so one differing pushurl carries the release
# where ls-remote never reads. git config --get returns the last value, so both keys are
# read whole, NUL-separated. A missing key exits 1; neither URL nor git's output is printed.
mapfile -d '' ORIGIN_URLS < <(git config -z --get-all remote.origin.url 2>/dev/null || true)
mapfile -d '' ORIGIN_PUSHURLS < <(git config -z --get-all remote.origin.pushurl 2>/dev/null || true)
for pushurl in "${ORIGIN_PUSHURLS[@]}"; do
  [ "$pushurl" = "${ORIGIN_URLS[0]:-}" ] \
    || fail 2 "remote.origin.pushurl is set and differs from remote.origin.url: the push would land where git ls-remote never reads, and every later run would refuse with 10. Run git config --unset-all remote.origin.pushurl, or make the pushurl equal to the url"
done

# --- 5: origin, read from origin (never from the remote-tracking ref) ----------------------
rc=0
git ls-remote origin "refs/heads/${RELEASE_BRANCH}" 'refs/tags/rel-*' \
  > "$SCRATCH/ls-remote" 2> "$SCRATCH/ls-remote.err" || rc=$?
[ "$rc" -eq 0 ] \
  || fail 5 "git ls-remote origin failed (exit ${rc}); git's own message is withheld because it names the remote"
ORIGIN_MAIN=""
declare -A ORIGIN_TAG=()
while IFS=$'\t' read -r sha ref; do
  [[ "$sha" =~ $SHA_RE ]] || continue
  case "$ref" in
    "refs/heads/${RELEASE_BRANCH}") ORIGIN_MAIN="$sha" ;;
    refs/tags/*'^{}') ;;
    refs/tags/rel-*) ORIGIN_TAG["${ref#refs/tags/}"]="$sha" ;;
  esac
done < "$SCRATCH/ls-remote"
[ -n "$ORIGIN_MAIN" ] || fail 5 "origin lists no ${RELEASE_BRANCH} branch"

# --- 8: behind origin ----------------------------------------------------------------------
behind() {
  fail 8 "this repository is behind origin: $1. Fetch and merge by hand (git fetch origin, then git merge --ff-only origin/${RELEASE_BRANCH}), then run again; this job never fetches"
}
git cat-file -e "${ORIGIN_MAIN}^{commit}" 2>/dev/null \
  || behind "origin's ${RELEASE_BRANCH} is a commit this repository does not have"
git merge-base --is-ancestor "$ORIGIN_MAIN" HEAD 2>/dev/null \
  || behind "origin's ${RELEASE_BRANCH} is not an ancestor of HEAD"
for name in "${!ORIGIN_TAG[@]}"; do
  local_obj="$(git rev-parse -q --verify "refs/tags/${name}" 2>/dev/null || true)"
  [ "$local_obj" = "${ORIGIN_TAG[$name]}" ] \
    || behind "origin has tag ${name}, which is missing here or names a different object"
done

# --- 2a: ahead of origin (operator ruling 2026-10-01) --------------------------------------
ahead="$(git rev-list --count "${ORIGIN_MAIN}..HEAD")"
if [ "$ahead" -gt 0 ]; then
  git log --reverse --format='%H %s' "${ORIGIN_MAIN}..HEAD" > "$SCRATCH/ahead"
  say "${RELEASE_BRANCH} is ${ahead} commit(s) ahead of origin; the push will also carry:"
  while IFS= read -r line; do
    say "  ${line:0:8} ${line#* }"
  done < "$SCRATCH/ahead"
fi

# --- 10: an unfinished release -------------------------------------------------------------
# The newest by creation date. Tags created in the same second share that date, and the
# sort cannot order them, so every tag tied with the newest is checked.
git for-each-ref --sort=-creatordate \
  --format='%(refname:strip=2) %(objectname) %(creatordate:unix)' \
  'refs/tags/rel-*' > "$SCRATCH/rel-tags"
NEWEST_REL=""
NEWEST_DATE=""
while read -r name obj when; do
  [[ "$name" =~ $REL_TAG_RE ]] || continue
  if [ -z "$NEWEST_DATE" ]; then
    NEWEST_DATE="$when"
  elif [ "$when" != "$NEWEST_DATE" ]; then
    break
  fi
  if [ "${ORIGIN_TAG[$name]:-}" != "$obj" ]; then
    NEWEST_REL="$name"
    break
  fi
done < "$SCRATCH/rel-tags"
if [ -n "$NEWEST_REL" ]; then
  printf 'release: error: unfinished release: %s is not on origin (or differs there); finish or abandon it first\n' "$NEWEST_REL" >&2
  tag_commit="$(git rev-parse -q --verify "refs/tags/${NEWEST_REL}^{commit}" 2>/dev/null || true)"
  head_parent="$(git rev-parse -q --verify 'HEAD^' 2>/dev/null || true)"
  if [ -n "$tag_commit" ] && [ "$tag_commit" = "$(git rev-parse HEAD)" ] && [ -n "$head_parent" ]; then
    say "stopped: ${NEWEST_REL} is at HEAD and was never pushed"
    print_finish_abandon "$NEWEST_REL" "$head_parent"
  else
    say "stopped: ${NEWEST_REL} is not at HEAD; push it once its release is deployed and drift-checked, or delete it:"
    say "  git push --atomic origin refs/tags/${NEWEST_REL}:refs/tags/${NEWEST_REL}"
    say "  git tag -d ${NEWEST_REL}"
  fi
  exit 10
fi

# --- 4: the target, in the clone -----------------------------------------------------------
if [ "$LATEST" -eq 1 ]; then
  clone_git for-each-ref --sort=-version:refname --format='%(refname:strip=2)' \
    'refs/tags/cp-PM*-main' > "$SCRATCH/cp-tags" 2>/dev/null \
    || fail 5 "git for-each-ref failed in the clone named by FORQSITE_CLONE"
  TARGET=""
  while IFS= read -r name; do
    if [[ "$name" =~ $CP_TAG_RE ]]; then
      TARGET="$name"
      break
    fi
  done < "$SCRATCH/cp-tags"
  [ -n "$TARGET" ] \
    || fail 4 "no tag matching cp-PM<n>-main in the clone named by FORQSITE_CLONE; fetch its tags there yourself (this job never fetches)"
  T="$(clone_git rev-parse --verify --quiet "refs/tags/${TARGET}^{commit}" 2>/dev/null || true)"
else
  T="$(clone_git rev-parse --verify --quiet "${TARGET}^{commit}" 2>/dev/null || true)"
fi
[[ "$T" =~ $SHA_RE ]] \
  || fail 4 "target ${TARGET} does not resolve to a commit in the clone named by FORQSITE_CLONE; fetch it there yourself (this job never fetches)"
T8="${T:0:8}"
TAG="rel-${T8}"
say "target ${TARGET} (${T8})"

# --- The manifest's release ---------------------------------------------------------------
python3 - "docs/claims-manifest.json" > "$SCRATCH/release" 2>/dev/null <<'PY' \
  || fail 2 "docs/claims-manifest.json lacks a readable release.repo and release.commit"
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    r = json.load(f)['release']
print(r['repo'])
print(r['commit'])
PY
mapfile -t release_fields < "$SCRATCH/release"
SLUG="${release_fields[0]:-}"
REL_COMMIT="${release_fields[1]:-}"
[[ "$SLUG" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] \
  || fail 2 "the manifest's release.repo is not an owner/name slug"
[[ "$REL_COMMIT" =~ $SHA_RE ]] || fail 2 "the manifest's release.commit is not a full sha"

# --- 0 / 10: already released, or a release half-made --------------------------------------
if [ "$REL_COMMIT" = "$T" ]; then
  if git rev-parse -q --verify "refs/tags/${TAG}" > /dev/null 2>&1; then
    say "already released: release.commit is ${T8} and ${TAG} exists; nothing to do"
    exit 0
  fi
  printf 'release: error: unfinished release: release.commit already pins %s, but %s does not exist\n' "$T8" "$TAG" >&2
  say "stopped: a release commit for ${SLUG}@${T8} exists without its tag (a release that stopped with exit 14)"
  head_subject="$(git log -1 --format=%s HEAD)"
  head_parent="$(git rev-parse -q --verify 'HEAD^' 2>/dev/null || true)"
  if [[ "$head_subject" == "release: ${SLUG}@${T8}, "* ]] && [ -n "$head_parent" ]; then
    say "to abandon it:"
    say "  git reset --keep ${head_parent}"
  else
    say "find that commit (git log -- docs/claims-manifest.json); to abandon it, revert or reset it by hand"
  fi
  exit 10
fi
if git rev-parse -q --verify "refs/tags/${TAG}" > /dev/null 2>&1 || [ -n "${ORIGIN_TAG[$TAG]:-}" ]; then
  fail 10 "${TAG} already exists here or on origin, but release.commit does not pin ${T8}; resolve it by hand"
fi

# --- 9: the selftests ------------------------------------------------------------------------
run_selftests() {
  local phase="$1" t name failed=() tests=()
  shopt -s nullglob
  tests=("$SELF_DIR"/*-selftest.sh)
  shopt -u nullglob
  if [ "${#tests[@]}" -eq 0 ]; then
    say "no selftest found in scripts/"
    return 1
  fi
  for t in "${tests[@]}"; do
    name="$(basename "$t")"
    bash "$t" > "$SCRATCH/${phase}-${name}.out" 2>&1 < /dev/null || failed+=("$name")
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    for name in "${failed[@]}"; do say "selftest failed: ${name}"; done
    return 1
  fi
  say "selftests: ${#tests[@]} passed (${phase})"
}
run_selftests "before the restamp" || fail 9 "a selftest failed; nothing was written"

# --- 3 / 2 / 4 / 5: the checker --------------------------------------------------------------
rc=0
python3 "$SELF_DIR/stale-claims.py" --no-commits "$T" \
  > "$SCRATCH/check.out" 2> "$SCRATCH/check.err" < /dev/null || rc=$?
case "$rc" in
  0) ;;
  3)
    # The stale path. The full report names forqsite commit subjects, so it goes only to
    # a gitignored local file, written fresh (noclobber after the remove) under umask 077.
    rrc=0
    (
      umask 077
      rm -f -- "$REPORT"
      set -C
      python3 "$SELF_DIR/stale-claims.py" "$T" > "$REPORT" 2> "$SCRATCH/report.err" < /dev/null
    ) || rrc=$?
    if [ "$rrc" -ne 3 ]; then
      fail 5 "the full stale-claims report run exited ${rrc}, not 3 like the --no-commits run"
    fi
    cat "$SCRATCH/check.out"
    say "review needed: a claim is stale or a closed gap has reopened at the target; nothing was committed, tagged, deployed or pushed"
    say "full report (local only; never commit it): ${REPORT}"
    say "review them as a story, then run again"
    exit 3
    ;;
  2|4)
    cat "$SCRATCH/check.err" >&2
    fail "$rc" "stale-claims.py --no-commits exited ${rc}"
    ;;
  *)
    cat "$SCRATCH/check.err" >&2
    fail 5 "stale-claims.py --no-commits failed unexpectedly (exit ${rc})"
    ;;
esac

# Counts and holds ids, from manifest text only (the --no-commits report).
summary_re='^summary: ([0-9]+) claims: ([0-9]+) untouched, ([0-9]+) holds, ([0-9]+) stale, ([0-9]+) unverified;'
N_CLAIMS=""
HOLDS=()
while IFS= read -r line; do
  if [[ "$line" =~ $summary_re ]]; then
    N_CLAIMS="${BASH_REMATCH[1]}"
    N_UNTOUCHED="${BASH_REMATCH[2]}"
    N_HOLDS="${BASH_REMATCH[3]}"
    N_UNVERIFIED="${BASH_REMATCH[5]}"
  elif [[ "$line" =~ ^([^[:space:]]+)\ holds\ \  ]]; then
    HOLDS+=("${BASH_REMATCH[1]}")
  fi
done < "$SCRATCH/check.out"
[ -n "$N_CLAIMS" ] || fail 5 "the stale-claims report has no summary line"
HOLDS_TEXT="none"
[ "${#HOLDS[@]}" -eq 0 ] || HOLDS_TEXT="${HOLDS[*]}"
SUBJECT="release: ${SLUG}@${T8}, ${N_CLAIMS} claims: ${N_UNTOUCHED} untouched, ${N_HOLDS} holds, ${N_UNVERIFIED} unverified"

# --- 11 (dry run): restamp --dry-run, and stop ----------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  rc=0
  python3 "$SELF_DIR/restamp.py" --dry-run "$T" \
    > "$SCRATCH/restamp.out" 2> "$SCRATCH/restamp.err" < /dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    cat "$SCRATCH/restamp.out"
    cat "$SCRATCH/restamp.err" >&2
    fail 11 "restamp.py --dry-run exited ${rc}; nothing was written"
  fi
  cat "$SCRATCH/restamp.out"
  say "would commit: ${SUBJECT}"
  say "would then tag ${TAG} (annotated), deploy it (scripts/deploy.sh --ref ${TAG}), drift-check it (scripts/drift-check.sh --ref ${TAG}), and only after both pass push ${RELEASE_BRANCH} and ${TAG} to origin"
  say "dry run: nothing was written; run again with --yes"
  exit 0
fi

# =========================================================================================
# --yes: everything below writes. Nothing is pushed before the last check passes.
# =========================================================================================
PRE="$(git rev-parse HEAD)"

# --- 11: restamp -----------------------------------------------------------------------------
rc=0
python3 "$SELF_DIR/restamp.py" "$T" \
  > "$SCRATCH/restamp.out" 2> "$SCRATCH/restamp.err" < /dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
  cat "$SCRATCH/restamp.out"
  cat "$SCRATCH/restamp.err" >&2
  printf 'release: error: restamp.py exited %s\n' "$rc" >&2
  if [ -n "$(tracked_status 2>/dev/null || echo unknown)" ]; then
    say "stopped: restamp.py failed after writing; nothing was committed. The tree had no tracked changes before this run, so this restores it:"
    say "  git restore --staged --worktree -- ."
  else
    say "stopped: restamp.py wrote nothing; nothing to undo"
  fi
  exit 11
fi
expected_status="$(printf ' M %s\n' "${RELEASE_FILES[@]}" | sort)"
actual_status="$(tracked_status | sort)"
if [ "$actual_status" != "$expected_status" ]; then
  printf 'release: error: restamp.py changed something other than exactly %s\n' "${RELEASE_FILES[*]}" >&2
  say "stopped: nothing was committed. The tree had no tracked changes before this run, so this restores it:"
  say "  git restore --staged --worktree -- ."
  exit 11
fi
cat "$SCRATCH/restamp.out"
RESTAMP_LINE="$(head -n 1 "$SCRATCH/restamp.out")"

# --- 12: the selftests again ------------------------------------------------------------------
if ! run_selftests "after the restamp" || [ "$(tracked_status | sort)" != "$expected_status" ]; then
  printf 'release: error: a selftest failed after the restamp (or changed a tracked file)\n' >&2
  say "stopped: nothing was committed"
  restore_line
  exit 12
fi

# --- 13: commit exactly the three files -------------------------------------------------------
printf '%s\n\n%s\nholds: %s\n' "$SUBJECT" "$RESTAMP_LINE" "$HOLDS_TEXT" > "$SCRATCH/message"
rc=0
git add -- "${RELEASE_FILES[@]}" > "$SCRATCH/commit.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || git commit -q -F "$SCRATCH/message" >> "$SCRATCH/commit.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'release: error: git commit failed (exit %s); its own output is withheld because it can name local paths\n' "$rc" >&2
  if [ "$(git rev-parse HEAD)" = "$PRE" ]; then
    say "stopped: nothing was committed"
    restore_line
  else
    say "stopped: HEAD moved although git commit failed; to abandon it:"
    say "  git reset --keep ${PRE}"
  fi
  exit 13
fi
RELEASE_COMMIT="$(git rev-parse HEAD)"
committed="$(git diff --name-only "$PRE" "$RELEASE_COMMIT" | sort)"
if [ "$committed" != "$(printf '%s\n' "${RELEASE_FILES[@]}" | sort)" ]; then
  printf 'release: error: the release commit holds something other than exactly %s\n' "${RELEASE_FILES[*]}" >&2
  say "stopped: the commit exists, untagged and unpushed; to abandon it:"
  say "  git reset --keep ${PRE}"
  exit 13
fi

# --- 14: the annotated tag ---------------------------------------------------------------------
rc=0
git tag -a -m "release ${SLUG}@${T8}" "$TAG" "$RELEASE_COMMIT" > "$SCRATCH/tag.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'release: error: git tag failed (exit %s); its own output is withheld because it can name local paths\n' "$rc" >&2
  say "stopped: the release commit exists but ${TAG} could not be created; nothing was deployed or pushed"
  say "to abandon it:"
  say "  git reset --keep ${PRE}"
  exit 14
fi

# --- 15: deploy, shown ------------------------------------------------------------------------
set +e
"$SELF_DIR/deploy.sh" --ref "$TAG" 2>&1 < /dev/null | tee "$SCRATCH/deploy.out"
rc="${PIPESTATUS[0]}"
set -e
STAMP=""
BACKUPS_LINE=""
while IFS= read -r line; do
  if [[ "$line" =~ ^stamp\ +([0-9]{8}T[0-9]{6}Z)$ ]] && [ -z "$STAMP" ]; then
    STAMP="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^backups\ +(.*)$ ]] && [ -z "$BACKUPS_LINE" ]; then
    BACKUPS_LINE="${BASH_REMATCH[1]}"
  fi
done < "$SCRATCH/deploy.out"
if [ "$rc" -ne 0 ]; then
  printf 'release: error: deploy.sh failed (exit %s)\n' "$rc" >&2
  say "stopped: ${TAG} exists locally; the deploy failed (exit ${rc}), so the site may serve part of it; nothing was pushed"
  print_finish_abandon "$TAG" "$PRE"
  exit 15
fi

# --- 16: the drift check, shown -----------------------------------------------------------------
set +e
"$SELF_DIR/drift-check.sh" --ref "$TAG" 2>&1 < /dev/null | tee "$SCRATCH/drift.out"
rc="${PIPESTATUS[0]}"
set -e
if [ "$rc" -ne 0 ]; then
  printf 'release: error: drift-check.sh failed (exit %s)\n' "$rc" >&2
  say "stopped: ${TAG} is deployed but the drift check failed (exit ${rc}); nothing was pushed, and nothing was rolled back"
  print_finish_abandon "$TAG" "$PRE"
  if [ -n "$STAMP" ]; then
    say "or, to restore the files this deploy replaced (backup set ${STAMP}), instead of the redeploy:"
    say "  scripts/deploy.sh --rollback ${STAMP}"
    say "  scripts/drift-check.sh"
    for f in index.html gap-handoff.html site-provenance.json; do
      if ! [[ ", ${BACKUPS_LINE}, " == *", ${f}.bak-${STAMP}, "* ]]; then
        say "note: backup set ${STAMP} has no backup of ${f}, so deploy.sh --rollback will refuse it (exit 6) and the abandon steps apply"
        break
      fi
    done
  fi
  exit 16
fi

# --- 17: push, only now -----------------------------------------------------------------------
rc=0
git push --atomic origin "refs/heads/${RELEASE_BRANCH}:refs/heads/${RELEASE_BRANCH}" "refs/tags/${TAG}:refs/tags/${TAG}" \
  > "$SCRATCH/push.out" 2>&1 < /dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'release: error: git push failed (exit %s); its own output is withheld because it names the remote\n' "$rc" >&2
  say "stopped: ${TAG} is deployed and drift-checked, but origin does not have it"
  say "to finish it:"
  say "  git push --atomic origin refs/heads/${RELEASE_BRANCH}:refs/heads/${RELEASE_BRANCH} refs/tags/${TAG}:refs/tags/${TAG}"
  say "if origin has moved meanwhile, resolve it by hand (fetch, then rebase or merge) before pushing"
  exit 17
fi

say "released ${SLUG}@${T8} as ${TAG}: deployed, drift-checked, and pushed with ${RELEASE_BRANCH}"
exit 0
