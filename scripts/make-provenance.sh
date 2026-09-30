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
#     printed, a --ref outside the class REF_RE (below; deploy.sh holds the same class).
#   - Resolves the given ref (default HEAD) to its 40-char commit sha.
#   - Refuses, before printing anything, if either bundle is not tracked at the ref.
#   - Reads the ref's committer date (UTC) and the current UTC time.
#   - Computes the sha256 of each bundle's bytes at the ref via `git show <ref>:<bundle>`.
#   - Emits one JSON object with fixed key order (see docs/stories/INFRA/INFRA-008.md
#     § Decisions 1) using printf — no jq dependency, and none is needed because no
#     field ever needs JSON string escaping: every field in the fixed shape is a hex
#     string, an ISO timestamp, an integer, a fixed filename, or repo_ref, the --ref as
#     given. repo_ref needs none because the ref is refused unless it matches REF_RE,
#     whose characters (letters, digits, _ . / ~ ^ -) include no quote, no backslash and
#     no control character — nothing JSON would need to escape (CER-033).
#
# Usage:
#   make-provenance.sh [--ref <git-ref>]
#
# Exit codes:
#   0   success — the JSON object was printed to stdout
#   5   a bundle is not tracked at the given ref (named in the message)
#   64  usage error (unrecognised argument, --ref given with no value, or a --ref
#       outside ^[A-Za-z0-9_][A-Za-z0-9._/~^-]*$ — letters, digits, _ . / ~ ^ -; may
#       not begin with . / ~ ^ or -) (CER-033)
#
# Notes:
#   - This script reads no configuration and contacts nothing. It is a pure function
#     of (repo, ref), which is what makes it testable against a throwaway fixture repo
#     with no fixture remote at all — see scripts/provenance-selftest.sh.
#   - The commit subject is deliberately not carried in the output: it is free-form
#     text and the only candidate field that would need escaping. Omitting it keeps
#     every value in the fixed shape.

set -euo pipefail

BUNDLES=(index.html gap-handoff.html)
REF="HEAD"

# --- Argument parsing --------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)
      if [ "$#" -lt 2 ]; then
        echo "make-provenance.sh: --ref requires an argument" >&2
        echo "usage: make-provenance.sh [--ref <git-ref>]" >&2
        exit 64
      fi
      REF="$2"
      shift 2
      ;;
    *)
      echo "make-provenance.sh: unrecognized argument: $1" >&2
      echo "usage: make-provenance.sh [--ref <git-ref>]" >&2
      exit 64
      ;;
  esac
done

# --- --ref class (CER-033), before anything is printed -------------------------------
# Branch, tag and sha forms plus ~/^ revision suffixes; nothing JSON would need to
# escape, and no leading "-". deploy.sh holds the same class. The refusal names the
# class, never the value.
REF_RE='^[A-Za-z0-9_][A-Za-z0-9._/~^-]*$'
if ! [[ "$REF" =~ $REF_RE ]]; then
  echo "make-provenance.sh: --ref is outside the accepted class (letters, digits, _ . / ~ ^ -; must begin with a letter, digit or _)" >&2
  echo "usage: make-provenance.sh [--ref <git-ref>]" >&2
  exit 64
fi

# --- Repo resolution -----------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# --- Tracked-at-ref check, before anything is printed ---------------------------------
for bundle in "${BUNDLES[@]}"; do
  if ! git cat-file -e "${REF}:${bundle}" 2>/dev/null; then
    echo "make-provenance.sh: ${bundle} is not tracked at ref ${REF}" >&2
    exit 5
  fi
done

# --- Fields ----------------------------------------------------------------------------
REPO_COMMIT="$(git rev-parse "$REF")"
REPO_COMMIT_DATE="$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ "$REF")"
DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

INDEX_SHA="$(git show "${REF}:index.html" | sha256sum | cut -d' ' -f1)"
GAP_SHA="$(git show "${REF}:gap-handoff.html" | sha256sum | cut -d' ' -f1)"

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
