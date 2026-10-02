#!/usr/bin/env bash
#
# make-provenance.sh — prints, to stdout, a single JSON object recording which commit
# of this repository produced the two published bundles (index.html, gap-handoff.html)
# at a given git ref, and the sha256 of each bundle's bytes at that ref. It does
# nothing else: it reads no configuration, contacts no host, and writes to no file.
# scripts/deploy.sh calls this script and performs the transport of its stdout to
# site-provenance.json in the configured remote directory (see that script's header
# for the deploy-side sequence and ordering).
#
# What it does:
#   - Resolves the git repository containing the current working directory.
#   - Refuses (exit 64), straight after argument parsing and before anything is
#     printed, a --commit that is not exactly 40 lowercase hex characters, then a --ref
#     outside the class REF_RE (below; deploy.sh holds the same class).
#   - Resolves the given ref (default HEAD) to the commit it names, exactly once, with
#     `git rev-parse -q --verify --end-of-options "<ref>^{commit}"`, after the REF_RE
#     check (INFRA-022, CER-063). An annotated tag is therefore recorded as the commit
#     it points to, never as the tag object's own sha. A ref that does not name a
#     commit (a missing ref, or a tag of a tree or blob) is refused (exit 5) before
#     anything is printed.
#   - Resolve-once invariant: every git read after that resolution — the tracked-at
#     check, the committer date and both `git show`s — names the resolved sha
#     (REPO_COMMIT), never the ref name again, so a ref that moves mid-run cannot mix
#     two commits into one sidecar. The ref name survives only in messages and as
#     repo_ref, recorded as given.
#   - --commit <sha> is the seam deploy.sh uses (INFRA-022): deploy.sh resolves the ref
#     once itself and passes that sha here, so this process never re-resolves the ref
#     name — a second resolution in a second process is exactly the window a moving
#     ref would exploit. With --commit, the given sha (checked against
#     ^[0-9a-f]{40}$) is resolved with `^{commit}` instead of the ref, refused (exit 5)
#     if it does not name a commit in this repository, and --ref is only recorded as
#     repo_ref.
#   - Refuses, before printing anything, if either bundle is not tracked at the commit.
#   - Reads the commit's committer date (UTC) and the current UTC time.
#   - Computes the sha256 of each bundle's bytes at the commit via
#     `git show <commit>:<bundle>`.
#   - Emits one JSON object with fixed key order (see docs/stories/INFRA/INFRA-008.md
#     § Decisions 1) using printf — no jq dependency, and none is needed because no
#     field ever needs JSON string escaping: every field in the fixed shape is a hex
#     string, an ISO timestamp, an integer, a fixed filename, or repo_ref, the --ref as
#     given. repo_ref needs none because the ref is refused unless it matches REF_RE,
#     whose characters (letters, digits, _ . / ~ ^ -) include no quote, no backslash and
#     no control character — nothing JSON would need to escape (CER-033).
#
# Usage:
#   make-provenance.sh [--ref <git-ref>] [--commit <sha>]
#
# Exit codes:
#   0   success — the JSON object was printed to stdout
#   5   the ref (or the --commit sha) does not name a commit (INFRA-022, CER-063), or a
#       bundle is not tracked at the given ref (named in the message)
#   64  usage error (unrecognised argument, --ref or --commit given with no value, a
#       --commit that is not exactly 40 lowercase hex characters, or a --ref
#       outside ^[A-Za-z0-9_][A-Za-z0-9._/~^-]*$ — letters, digits, _ . / ~ ^ -; may
#       not begin with . / ~ ^ or -) (CER-033)
#
# Notes:
#   - This script reads no configuration and contacts nothing. It is a pure function
#     of (repo, ref[, commit]), which is what makes it testable against a throwaway fixture repo
#     with no fixture remote at all — see scripts/provenance-selftest.sh.
#   - The commit subject is deliberately not carried in the output: it is free-form
#     text and the only candidate field that would need escaping. Omitting it keeps
#     every value in the fixed shape.

set -euo pipefail

BUNDLES=(index.html gap-handoff.html)
REF="HEAD"
COMMIT_GIVEN=""
COMMIT_GIVEN_SET=0
USAGE="usage: make-provenance.sh [--ref <git-ref>] [--commit <sha>]"
COMMIT_TAKES="make-provenance.sh: --commit takes one full commit sha, given once (exactly 40 lowercase hex characters)"

# --- Argument parsing --------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)
      if [ "$#" -lt 2 ]; then
        echo "make-provenance.sh: --ref requires an argument" >&2
        echo "$USAGE" >&2
        exit 64
      fi
      REF="$2"
      shift 2
      ;;
    --commit)
      if [ "$#" -lt 2 ] || [ "$COMMIT_GIVEN_SET" -eq 1 ]; then
        echo "$COMMIT_TAKES" >&2
        echo "$USAGE" >&2
        exit 64
      fi
      COMMIT_GIVEN="$2"
      COMMIT_GIVEN_SET=1
      shift 2
      ;;
    *)
      echo "make-provenance.sh: unrecognized argument: $1" >&2
      echo "$USAGE" >&2
      exit 64
      ;;
  esac
done

# --- --commit form (INFRA-022), straight after argument parsing ---------------------
# Only a full lowercase sha: never a ref name, so the seam cannot reintroduce a second
# resolution of a name. The refusal does not echo the value.
if [ "$COMMIT_GIVEN_SET" -eq 1 ] && ! [[ "$COMMIT_GIVEN" =~ ^[0-9a-f]{40}$ ]]; then
  echo "$COMMIT_TAKES" >&2
  echo "$USAGE" >&2
  exit 64
fi

# --- --ref class (CER-033), before anything is printed -------------------------------
# Branch, tag and sha forms plus ~/^ revision suffixes; nothing JSON would need to
# escape, and no leading "-". deploy.sh holds the same class. The refusal names the
# class, never the value.
REF_RE='^[A-Za-z0-9_][A-Za-z0-9._/~^-]*$'
if ! [[ "$REF" =~ $REF_RE ]]; then
  echo "make-provenance.sh: --ref is outside the accepted class (letters, digits, _ . / ~ ^ -; must begin with a letter, digit or _)" >&2
  echo "$USAGE" >&2
  exit 64
fi

# --- Repo resolution -----------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# --- Tracked-at-ref check, before anything is printed ---------------------------------
# Resolve once (INFRA-022, CER-063): the ref — or, under --commit, the sha deploy.sh
# already resolved — is peeled to a commit here and nowhere else. Every git read below
# names REPO_COMMIT, never $REF, so a ref moved mid-run cannot mix commits.
if [ "$COMMIT_GIVEN_SET" -eq 1 ]; then
  if ! REPO_COMMIT="$(git rev-parse -q --verify --end-of-options "${COMMIT_GIVEN}^{commit}")"; then
    echo "make-provenance.sh: --commit ${COMMIT_GIVEN} does not name a commit" >&2
    exit 5
  fi
else
  if ! REPO_COMMIT="$(git rev-parse -q --verify --end-of-options "${REF}^{commit}")"; then
    echo "make-provenance.sh: ref ${REF} does not name a commit" >&2
    exit 5
  fi
fi

for bundle in "${BUNDLES[@]}"; do
  if ! git cat-file -e "${REPO_COMMIT}:${bundle}" 2>/dev/null; then
    echo "make-provenance.sh: ${bundle} is not tracked at ref ${REF} (commit ${REPO_COMMIT})" >&2
    exit 5
  fi
done

# --- Fields ----------------------------------------------------------------------------
REPO_COMMIT_DATE="$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ "$REPO_COMMIT")"
DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

INDEX_SHA="$(git show "${REPO_COMMIT}:index.html" | sha256sum | cut -d' ' -f1)"
GAP_SHA="$(git show "${REPO_COMMIT}:gap-handoff.html" | sha256sum | cut -d' ' -f1)"

# --- Emit --------------------------------------------------------------------------------
printf '{\n'
printf '  "schema": 1,\n'
printf '  "repo_commit": "%s",\n' "$REPO_COMMIT"
printf '  "repo_ref": "%s",\n' "$REF"
printf '  "repo_commit_date": "%s",\n' "$REPO_COMMIT_DATE"
printf '  "deployed_at": "%s",\n' "$DEPLOYED_AT"
printf '  "bundles": {\n'
printf '    "index.html": "%s",\n' "$INDEX_SHA"
printf '    "gap-handoff.html": "%s"\n' "$GAP_SHA"
printf '  }\n'
printf '}\n'

exit 0
