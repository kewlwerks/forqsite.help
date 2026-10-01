#!/usr/bin/env bash
#
# deploy.sh — deploy the two published bundles (index.html, gap-handoff.html) to the
# configured per-site directory, over the configured ssh alias, at a git ref.
#
# What it does:
#   - Resolves the git repository containing the current working directory.
#   - Reads deployment target configuration (ssh alias + remote directory) from the
#     environment, falling back to a gitignored scripts/deploy.env when unset. That file
#     is read as KEY=value data by read-deploy-env.sh (loaded from this script's own
#     directory), never executed (CER-024). The environment wins (CER-035): the file
#     fills only keys the environment leaves unset, and a key the environment sets is
#     used as set, whatever the file holds. Any line that is not a KEY=value line for a
#     known key is refused (exit 2) by line number, without printing its content.
#   - Refuses (exit 64), straight after argument parsing and before any git or ssh work,
#     a --ref outside the class REF_RE (below; make-provenance.sh holds the same class).
#   - Refuses to proceed, before any network contact, if either bundle is untracked at
#     the ref, or its working-tree or staged content differs from that ref ("dirty").
#   - Backs up each live bundle on the remote side to <name>.bak-<UTC stamp>, then
#     overwrites (never renames) each live bundle in place with the bytes of that
#     bundle at the given ref (default HEAD), then verifies each file's sha256 on the
#     far side against the same ref's bytes computed locally.
#   - After both bundles have been copied and hash-verified, generates a provenance
#     sidecar (scripts/make-provenance.sh --ref "$REF") and deploys it to
#     site-provenance.json using the same backup / overwrite-in-place / verify-sha256
#     sequence. The sidecar is written last, deliberately: it asserts "this commit is
#     deployed", and writing it before the bundles land would publish that claim even
#     if a later bundle copy then failed.
#   - Stages every remote write unpredictably (CER-023). Each file's bytes are streamed
#     into a stage created on the far side by `mktemp` in the remote directory (template
#     ./.<name>.deploy-XXXXXXXXXX: an unpredictable name, created exclusively), then
#     copied over the live file in place, and the stage is removed whether the steps
#     succeed or fail. A far side with no `mktemp` is a remote failure (exit 5). A file
#     that did not exist before is created mode 0644, so the web server's account can
#     read it; an existing file keeps its inode and its mode unchanged.
#   - Writes each backup with noclobber. <name>.bak-<stamp> is refused (exit 5) if that
#     name already exists in any form, including a dangling symlink; otherwise it is
#     written under `set -C`, so a name appearing between the check and the write makes
#     the write fail instead of following it. The far side prints a fixed token only
#     after that write succeeds, and the success block's `backups` line lists only the
#     backups whose token came back (CER-037): a file with no live copy to back up (a
#     first deploy, or a first sidecar) gets no backup and is not listed.
#   - Bounds retention (CER-027). Only after both bundles and the sidecar have verified,
#     and never on any failure path, it writes a .deploy-verified-<stamp> marker (with
#     noclobber) and prunes verified backup sets beyond BACKUP_KEEP (a constant, below).
#     The set this deploy just made is always kept. A set without a marker — the
#     backup set of a deploy that failed verification (restorable with --rollback,
#     below), a set a --rollback made, or a set older than this retention scheme — is
#     never pruned; remove such sets by hand when no longer wanted. Each set is pruned
#     by one ssh call that removes its three backups and then its marker one file at a
#     time, stopping at the first removal that fails (CER-030). If pruning fails, the
#     report names the stamps already pruned, the one that failed, and, file by file,
#     what was removed from the failed set and what remains of it.
#   - Rolls back (CER-031), with --rollback <stamp>: restores the three files that were
#     live just before the deploy that made <stamp>, from that deploy's backup set
#     (<name>.bak-<stamp>), overwriting each in place through the same verified copy
#     path a deploy uses, and verifying each by sha256 on the far side. It refuses
#     (exit 6, nothing written) a set that is missing or incomplete. The operator runs
#     it by hand; nothing runs it automatically. See "Rollback invariants" below.
#   - Precondition: the remote directory should be writable only by the deploy account.
#     The mktemp staging and noclobber backups narrow the symlink race another account
#     could run in that directory; they do not make a shared directory safe.
#   - Prints a pasteable success record. Never runs docker, docker compose, systemctl,
#     or any container/service restart — including for the one-time bind-mount this
#     script's sidecar requires. That mount (docker-compose.yml) and the container
#     recreate it needs are a one-time, documented, manual bootstrap: (a) run this
#     script once so site-provenance.json exists in the remote directory, (b) add the
#     mount, (c) recreate the container (`docker compose up -d`). Adding the mount
#     before step (a) makes Docker create a directory at that path instead of
#     bind-mounting a file, and the mount is then permanently wrong. Every deploy after
#     the one-time recreate is a plain copy, like the two bundles, and needs nothing
#     further.
#
# Usage:
#   deploy.sh [--ref <git-ref>] [--dry-run]
#   deploy.sh --rollback <stamp>
#
# Exit codes:
#   0  success
#   2  configuration missing or unreadable (FORQSITE_HELP_DEPLOY_HOST /
#      FORQSITE_HELP_DEPLOY_DIR unset, or scripts/deploy.env has a refused line), or
#      FORQSITE_HELP_DEPLOY_HOST does not match the ssh-alias pattern
#      ^[A-Za-z0-9._][A-Za-z0-9._-]*$ (letters, digits, ., _, -; may not begin with -)
#   3  dirty-tree refusal (untracked at the ref, or working tree / index differs)
#   4  hash verification failure (remote bytes do not match the ref's bytes; in a
#      rollback, a fetched backup or a restored live file does not match the sha256 the
#      inventory reported for that backup)
#   5  transport/remote failure (ssh or a remote command failed; the remote has no
#      mktemp or sha256sum; a backup name already exists — which two deploys, or a
#      deploy and a rollback, that run in the same second into one directory cause,
#      since the stamp has one-second resolution; or, after every file verified, the
#      marker or prune step failed — the message then says the files verified, names
#      any stamps pruned before the failure, and names each file removed from and each
#      file remaining in the set that failed)
#   6  rollback refused: the backup set for that stamp is missing or incomplete; nothing was written
#   64  usage error (unrecognised argument, --ref given with no value, or a --ref
#       outside ^[A-Za-z0-9_][A-Za-z0-9._/~^-]*$ — letters, digits, _ . / ~ ^ -; may
#       not begin with . / ~ ^ or -) (CER-015, CER-033); --rollback given with no
#       value, a --rollback stamp outside ^[0-9]{8}T[0-9]{6}Z$, or --rollback together
#       with --ref or --dry-run
#
# Notes:
#   - nginx.conf is also bind-mounted into the container, but unlike the two bundles a
#     change to it needs a container action (e.g. a config reload) to take effect. That
#     is deliberately outside what this script does; this script only ever touches the
#     two bundle files.
#   - The remote bind mount follows the file's inode, not its name. Each bundle must be
#     overwritten in place (copied over the existing file), never replaced by renaming a
#     new file over it — a rename would leave the container serving the old, now-unlinked
#     inode while the deploy appeared to succeed.
#   - Transport errors never print the configured target (CER-028, INFRA-014). Every
#     ssh call is routed through run_ssh(), which captures ssh's own stderr and the
#     remote shell's stderr to a scratch file — never printed, whole or in part — and
#     a failure prints a fixed reason label instead (e.g. "the connection was
#     refused"). Interactive prompts (host-key questions, passwords,
#     keyboard-interactive) are unaffected: OpenSSH's read_passphrase() writes every
#     one of them to the controlling tty, not to stderr, even when stdin is a pipe.
#     The accepted cost is that server banners and the "Permanently added ... to the
#     list of known hosts" notice are no longer shown, on success or failure alike.
#     BatchMode=yes, -q and LogLevel=QUIET were all rejected: BatchMode disables every
#     prompt (breaking interactive authentication), and -q/LogLevel=QUIET suppress the
#     very messages the reason labels are derived from. No ssh option is added.
#
# Rollback invariants (--rollback <stamp>, CER-031):
#   Meaning. `--rollback S` restores the files that were live just before the deploy
#     that made stamp S: index.html, gap-handoff.html and site-provenance.json, from
#     index.html.bak-S, gap-handoff.html.bak-S and site-provenance.json.bak-S. It runs
#     the same configuration and alias checks as a deploy, skips the dirty check (no
#     ref is involved), and takes a fresh stamp F of its own.
#   Order. Three phases, each finished before the next begins:
#     A. Read only. (1) One ssh call inventories the set: the far-side sha256 of each
#        of the three backups that is a regular file and not a symlink. Its output is
#        untrusted: only a line naming one of the three exact backup names with a
#        64-hex hash is accepted (the first such line per name). (2) If any of the
#        three is absent, exit 6, naming the absent backups (never the directory). A
#        set with no sidecar backup is refused too: restoring its bundles under today's
#        sidecar would publish a provenance claim for a commit no longer served. A
#        verified marker is not required, since an unmarked set is exactly what a
#        failed deploy leaves. (3) Each backup's bytes are fetched into a file in the
#        local ssh scratch directory (never a shell variable, which would drop trailing
#        newlines) and hashed locally; any mismatch with the inventory is exit 4.
#     B. Back up. Each live file is backed up as <name>.bak-F by the deploy's own backup
#        step (the shared backup_live helper), index.html, gap-handoff.html, then
#        site-provenance.json. No live file has been written yet, so a failure here
#        (exit 5, e.g. F's backup name already exists) leaves every live file as it was.
#     C. Restore, in the deploy's order — the two bundles first, the sidecar last. For
#        each file: stream the fetched bytes through remote_copy_cmd (an in-place `cp`
#        over the live file, never `mv`: the bind mount pins the inode), then hash the
#        live file on the far side; it must equal the inventory value, or exit 4.
#   Verified. A file counts as restored only when the far side's sha256 of the live file
#     equals the inventory's sha256 of its backup — never on the copy's exit status
#     alone. The served-bytes check stays with drift-check.sh, which the success block
#     tells the operator to run next.
#   Partial failure. The rollback stops at the first failure and names the file that
#     failed and the files already restored (each of which verified). Phase A failures
#     write nothing at all. A phase B or C failure has, by then, written a backup of
#     every live file that existed as <name>.bak-F, so the pre-rollback state is itself
#     restorable: `deploy.sh --rollback F` (when all three live files existed).
#   Why it never half-restores a set. Nothing is written until the whole set is known
#     to be present (phase A2) and every backup's bytes are in hand and verified (A3),
#     so a missing, symlinked or unreadable backup, or one whose bytes do not match,
#     stops the run before the first write. The only failures left once writing starts
#     are transport or far-side write failures during phase C, and for those the run
#     stops at once, names what is restored and what is not, and leaves the reverse
#     set (F) to undo it. The sidecar is restored last, so a run that stops early never
#     publishes the restored set's provenance claim over bundles it did not restore.
#   No retention. A rollback writes no verified marker and prunes nothing; the set F it
#     writes is never pruned automatically. The operator removes it by hand.

set -euo pipefail

BUNDLES=(index.html gap-handoff.html)
# Verified backup sets kept on the far side, counting the set this deploy makes.
# A stated constant, not configuration.
BACKUP_KEEP=5
REF="HEAD"
REF_GIVEN=0
DRY_RUN=0
ROLLBACK_STAMP=""
ROLLBACK_GIVEN=0
USAGE="usage: deploy.sh [--ref <git-ref>] [--dry-run] | deploy.sh --rollback <stamp>"
# A backup stamp (and a rollback's argument): UTC, one-second resolution.
STAMP_RE='^[0-9]{8}T[0-9]{6}Z$'

# Reserved remote exit code (INFRA-014). Distinct from 1 (a step's own generic
# remote failure), 5 (transport/remote failure) and 255 (ssh itself failed before
# the remote command ran). Every remote command's `cd` into the configured
# directory exits this code on failure, with its own stderr silenced, so a missing
# or unenterable directory is detected by exit code, never by parsing the remote
# shell's own wording — that wording varies by shell and locale.
REMOTE_DIR_MISSING_EXIT=42

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)
      if [ "$#" -lt 2 ]; then
        echo "deploy.sh: --ref requires an argument" >&2
        echo "$USAGE" >&2
        exit 64
      fi
      REF="$2"
      REF_GIVEN=1
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --rollback)
      if [ "$#" -lt 2 ]; then
        echo "deploy.sh: --rollback requires a backup stamp (YYYYMMDDTHHMMSSZ)" >&2
        echo "$USAGE" >&2
        exit 64
      fi
      ROLLBACK_STAMP="$2"
      ROLLBACK_GIVEN=1
      shift 2
      ;;
    *)
      echo "deploy.sh: unrecognized argument: $1" >&2
      echo "$USAGE" >&2
      exit 64
      ;;
  esac
done

# --- --rollback usage (CER-031) ----------------------------------------------------------
# Refused here, before any git or ssh work. A rollback restores a backup set, so it takes
# no ref; and a dry run makes no ssh call, so it could not check the set it would restore
# (operator ruling 2026-10-01: refused rather than half-implemented). The stamp refusal
# names the class, never the value.
if [ "$ROLLBACK_GIVEN" -eq 1 ]; then
  if ! [[ "$ROLLBACK_STAMP" =~ $STAMP_RE ]]; then
    echo "deploy.sh: --rollback takes a backup stamp of the form YYYYMMDDTHHMMSSZ (UTC, as in <name>.bak-<stamp>)" >&2
    echo "$USAGE" >&2
    exit 64
  fi
  if [ "$REF_GIVEN" -eq 1 ]; then
    echo "deploy.sh: --rollback restores a backup set and takes no --ref" >&2
    echo "$USAGE" >&2
    exit 64
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "deploy.sh: --rollback cannot be combined with --dry-run (a dry run makes no ssh call, so it could not check the backup set)" >&2
    echo "$USAGE" >&2
    exit 64
  fi
fi

# --- --ref class (CER-033) ------------------------------------------------------------
# Branch, tag and sha forms plus ~/^ revision suffixes; nothing JSON would need to
# escape, and no leading "-" (which git would read as an option). make-provenance.sh
# holds the same class, since it publishes the ref in the sidecar. Checked here, before
# any git or ssh work, so a bad ref can never pass the dirty check, copy both bundles,
# and only then fail in the sidecar step. The refusal names the class, never the value.
REF_RE='^[A-Za-z0-9_][A-Za-z0-9._/~^-]*$'
if ! [[ "$REF" =~ $REF_RE ]]; then
  echo "deploy.sh: --ref is outside the accepted class (letters, digits, _ . / ~ ^ -; must begin with a letter, digit or _)" >&2
  echo "$USAGE" >&2
  exit 64
fi

# --- This script's own location, for invoking its sibling make-provenance.sh -------
# Resolved from this script's own path, not from the deployed repo's root below: the
# two are the same in normal use, but a caller may run this script with its cwd set
# to a different repository (e.g. a fixture repo in provenance-selftest.sh), and the
# sibling generator to invoke is always the one next to this script.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAKE_PROVENANCE_SH="$SELF_DIR/make-provenance.sh"
# The config reader comes from this script's own directory, never the deployed repo's
# (CER-024): the repo below may be one the operator does not control.
# shellcheck source=read-deploy-env.sh
. "$SELF_DIR/read-deploy-env.sh"

# --- Repo resolution -----------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# --- Configuration ---------------------------------------------------------------
HOST="${FORQSITE_HELP_DEPLOY_HOST:-}"
DIR="${FORQSITE_HELP_DEPLOY_DIR:-}"

if [ -z "$HOST" ] || [ -z "$DIR" ]; then
  if [ -f "scripts/deploy.env" ]; then
    # Parsed as KEY=value data, never executed (CER-024). The environment wins
    # (CER-035): a file value fills a key only when the environment left it unset.
    read_deploy_env "scripts/deploy.env" "deploy.sh" || exit 2
    HOST="${HOST:-$DEPLOY_ENV_HOST}"
    DIR="${DIR:-$DEPLOY_ENV_DIR}"
  fi
fi

if [ -z "$HOST" ] || [ -z "$DIR" ]; then
  echo "deploy.sh: missing configuration — set FORQSITE_HELP_DEPLOY_HOST and FORQSITE_HELP_DEPLOY_DIR" >&2
  echo "deploy.sh: in the environment, or in scripts/deploy.env" >&2
  exit 2
fi

# --- Alias validation --------------------------------------------------------------
# FORQSITE_HELP_DEPLOY_HOST is passed to ssh as its first (non-option) argument. A
# value beginning with "-" would be parsed by ssh as an option (e.g.
# -oProxyCommand=...) instead of an alias, causing local command execution before any
# connection is made (CER-019). Restrict to a conservative ssh-alias character set
# that cannot begin with "-". Never echo the value itself (§ Name the class, not the
# instance) — only the variable name is named in the refusal message.
if ! [[ "$HOST" =~ ^[A-Za-z0-9._][A-Za-z0-9._-]*$ ]]; then
  echo "deploy.sh: FORQSITE_HELP_DEPLOY_HOST is not a valid ssh alias (letters, digits, ., _, -; may not begin with -)" >&2
  exit 2
fi

# --- POSIX single-quote helper -------------------------------------------------------
# Wraps a value in single quotes for splicing into a remote command string, rendering
# each embedded "'" as "'\''". Unlike bash's %q format specifier (CER-025), this
# produces quoting that is safe under any POSIX sh, not just bash — the far account's
# login shell is not guaranteed to be bash.
sq() {
  local s=${1//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

# --- ssh wrapper (CER-028, INFRA-014) -------------------------------------------------
# The single call site through which every ssh invocation runs. Only fd 2 is
# redirected, to $SSH_ERR_FILE (a scratch file created after the dry-run exit below,
# removed by an EXIT trap). ssh's own stdout and this process's stdin are untouched,
# so `remote_out="$(run_ssh ...)"` and the piped-stdin copy steps behave exactly as an
# unredirected call below would, and interactive prompts are unaffected (see header
# note). Returns ssh's own exit status.
run_ssh() {
  ssh "$HOST" "$1" 2>"$SSH_ERR_FILE"
}

# --- Failure classifier (CER-028, INFRA-014) ------------------------------------------
# Reads $SSH_ERR_FILE — the scratch file the most recent run_ssh call captured — and
# the exit status passed as $1, and prints exactly one fixed reason label. Never
# prints any part of the captured file: every check below is a grep -q whose result,
# never its output, drives the case. Labels are fixed strings; nothing captured is
# ever interpolated into them.
ssh_reason_label() {
  local status="$1"
  if [ "$status" -eq 255 ]; then
    # ssh itself failed before the remote command ran.
    if grep -q 'Could not resolve hostname' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "the host would not resolve"
    elif grep -q 'Connection refused' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "the connection was refused"
    elif grep -q 'timed out' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "the connection timed out"
    elif grep -q 'Host key verification failed' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "host key verification failed"
    elif grep -q 'Permission denied (' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "authentication was refused"
    elif grep -q 'connect to host' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "could not connect to the host"
    else
      echo "ssh failed before the remote command ran (exit 255); ssh's own diagnostic text is withheld because it names the configured target — run ssh -v <alias> by hand to see it"
    fi
  elif [ "$status" -eq "$REMOTE_DIR_MISSING_EXIT" ]; then
    echo "the remote directory is missing or cannot be entered"
  else
    # Any other status: the remote command itself failed. Match this script's own
    # fixed remote refusal texts to their labels.
    if grep -q 'remote has no mktemp' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "the remote has no mktemp"
    elif grep -q 'remote has no sha256sum' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "the remote has no sha256sum"
    elif grep -q 'backup name already exists' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "the backup name already exists"
    elif grep -q 'verified marker name already exists' "$SSH_ERR_FILE" 2>/dev/null; then
      echo "the marker name already exists"
    else
      echo "the remote command failed (exit ${status}); its own diagnostic text is withheld because it may name the configured target — run ssh -v <alias> by hand to see it"
    fi
  fi
}

# --- Remote command builders ---------------------------------------------------------
# Backup: refuse if the backup name exists in any form (a dangling symlink included),
# otherwise write it under noclobber so a name planted between the check and the write
# makes the write fail rather than follow it. BACKUP_WRITTEN_TOKEN is printed on stdout
# only after the `cat > <bak>` write has succeeded (CER-037): it is the far side's
# confirmation that the backup exists, and the only evidence backup_live() records.
BACKUP_WRITTEN_TOKEN="deploy.sh:backup-written"
remote_backup_cmd() {
  local name="$1" bak="$1.bak-$STAMP"
  printf '%s' "cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
if [ -f $(sq "$name") ]; then
  if [ -e $(sq "$bak") ] || [ -L $(sq "$bak") ]; then
    echo $(sq "deploy.sh: backup name already exists for ${name}") >&2
    exit 5
  fi
  set -C
  cat $(sq "$name") > $(sq "$bak") || exit 1
  echo $(sq "$BACKUP_WRITTEN_TOKEN")
fi"
}

# Copy: stream stdin into a stage made by the far side's mktemp (unpredictable name,
# created exclusively), copy the stage over the live file in place (never mv — the bind
# mount follows the inode), and remove the stage on every exit path. A file created for
# the first time gets mode 0644 rather than the stage's 0600; an existing file keeps
# its inode and mode, so the live file is never chmod-ed unconditionally.
remote_copy_cmd() {
  local name="$1"
  printf '%s' "cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
if ! command -v mktemp >/dev/null 2>&1; then echo 'deploy.sh: remote has no mktemp' >&2; exit 5; fi
stage=\$(mktemp $(sq "./.${name}.deploy-XXXXXXXXXX")) || exit 1
trap 'rm -f -- \"\$stage\"' EXIT
trap 'exit 1' HUP INT TERM
if [ -e $(sq "$name") ] || [ -L $(sq "$name") ]; then created=0; else created=1; fi
cat > \"\$stage\" && cp -- \"\$stage\" $(sq "$name") && if [ \"\$created\" -eq 1 ]; then chmod 0644 $(sq "$name"); fi"
}

# --- Backup step, shared by the deploy and the rollback (CER-037) -------------------------
# Backs up the live <name> as <name>.bak-$STAMP on the far side. Appends the backup's
# name to BACKUPS_WRITTEN only when the far side printed BACKUP_WRITTEN_TOKEN, i.e. only
# when it confirmed the write; a live file that does not exist is not backed up and not
# recorded. On failure, prints the step's two standard lines and returns 5 (the caller
# exits, after adding any context of its own).
BACKUPS_WRITTEN=()
backup_live() {
  local name="$1" out status=0
  out="$(run_ssh "$(remote_backup_cmd "$name")")" || status=$?
  if [ "$status" -ne 0 ]; then
    echo "deploy.sh: remote backup step failed for ${name}" >&2
    echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
    return 5
  fi
  if printf '%s\n' "$out" | grep -qxF -- "$BACKUP_WRITTEN_TOKEN"; then
    BACKUPS_WRITTEN+=("${name}.bak-${STAMP}")
  fi
  return 0
}

# The success block's backups line: only the backups the far side confirmed (CER-037).
print_backups_line() {
  if [ "${#BACKUPS_WRITTEN[@]}" -gt 0 ]; then
    local joined
    joined="$(printf '%s, ' "${BACKUPS_WRITTEN[@]}")"
    echo "backups   ${joined%, }"
  else
    echo "backups   none — the far side confirmed no backup written (no live file existed to back up)"
  fi
}

# --- Dirty check (before any network contact) -------------------------------------
# Skipped by a rollback, which involves no ref.
dirty_found=0
[ "$ROLLBACK_GIVEN" -eq 1 ] && BUNDLES_TO_CHECK=() || BUNDLES_TO_CHECK=("${BUNDLES[@]}")
for bundle in "${BUNDLES_TO_CHECK[@]}"; do
  if ! git cat-file -e "${REF}:${bundle}" 2>/dev/null; then
    echo "deploy.sh: ${bundle} is not tracked at ref ${REF} (untracked)" >&2
    dirty_found=1
    continue
  fi
  if ! git diff --quiet "${REF}" -- "${bundle}"; then
    echo "deploy.sh: ${bundle} is dirty (unstaged working-tree changes differ from ref ${REF})" >&2
    dirty_found=1
  fi
  if ! git diff --quiet --cached "${REF}" -- "${bundle}"; then
    echo "deploy.sh: ${bundle} is dirty (staged changes differ from ref ${REF})" >&2
    dirty_found=1
  fi
done

if [ "$dirty_found" -ne 0 ]; then
  exit 3
fi

# --- Stamp -------------------------------------------------------------------------
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "deploy.sh: dry run — all local checks passed, no ssh will be invoked"
  echo "deploy.sh: would deploy ref ${REF} (resolved $(git rev-parse "${REF}")) with stamp ${STAMP}"
  for bundle in "${BUNDLES[@]}"; do
    sha="$(git show "${REF}:${bundle}" | sha256sum | cut -d' ' -f1)"
    echo "deploy.sh: would back up and overwrite ${bundle} (sha256 ${sha}) on the configured target"
  done
  echo "deploy.sh: would generate and deploy site-provenance.json (after both bundles verify):"
  "$MAKE_PROVENANCE_SH" --ref "$REF"
  echo "deploy.sh: would mark stamp ${STAMP} verified and prune verified backup sets beyond ${BACKUP_KEEP} (never this deploy's set, never a set without a marker)"
  exit 0
fi

# --- ssh error-capture scratch (CER-028, INFRA-014) ---------------------------------
# Created only past the dry-run exit above, since a dry run never invokes ssh.
# Removed by this EXIT trap so no captured text — which may name the configured
# alias, host or directory — ever outlives this process.
SSH_SCRATCH_DIR="$(mktemp -d)"
trap 'rm -rf "$SSH_SCRATCH_DIR"' EXIT
SSH_ERR_FILE="$SSH_SCRATCH_DIR/ssh-stderr"

# --- Rollback (CER-031): --rollback <stamp> ------------------------------------------------
# See "Rollback invariants" in the header. Phases A (read only), B (back up every live
# file) and C (restore, bundles first, sidecar last), each finished before the next starts.
# This block always exits; nothing below it runs in a rollback. It writes no verified
# marker and prunes nothing (operator ruling 2026-10-01: sets a rollback makes are never
# pruned automatically).
if [ "$ROLLBACK_GIVEN" -eq 1 ]; then
  RB="$ROLLBACK_STAMP"
  # Restore order: the two bundles, then the sidecar, as in a deploy.
  RB_FILES=(index.html gap-handoff.html site-provenance.json)
  declare -A RB_SHA      # inventory sha256 of <name>.bak-$RB, per live name
  declare -A RB_FETCHED  # local scratch file holding that backup's bytes
  RB_RESTORED=()

  # Every message names files and stamps only, never the alias or the directory.
  rollback_stop() {
    local code="$1" failed="$2" what="$3" restored="none"
    if [ "${#RB_RESTORED[@]}" -gt 0 ]; then restored="${RB_RESTORED[*]}"; fi
    echo "deploy.sh: rollback to backup set ${RB} stopped at ${failed}: ${what}" >&2
    echo "deploy.sh: already restored (each verified): ${restored}" >&2
    if [ "${#BACKUPS_WRITTEN[@]}" -gt 0 ]; then
      echo "deploy.sh: this run backed up the files it was replacing as: ${BACKUPS_WRITTEN[*]} (unmarked, never pruned automatically; restorable with --rollback ${STAMP} when all three are present)" >&2
    fi
    echo "deploy.sh: run the drift check before relying on what is served" >&2
    exit "$code"
  }

  # --- Phase A1: inventory, one ssh call -------------------------------------------------
  # Reports "<sha256>  <name>" for each of the three backups that is a regular file and
  # not a symlink. A backup that cannot be read fails the call (exit 5), rather than being
  # reported absent.
  inv_list=""
  for n in "${RB_FILES[@]}"; do inv_list+=" $(sq "${n}.bak-${RB}")"; done
  inventory_cmd="cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
if ! command -v sha256sum >/dev/null 2>&1; then echo deploy.sh: remote has no sha256sum >&2; exit 5; fi
for b in${inv_list}; do
  if [ -f \"\$b\" ] && ! [ -L \"\$b\" ]; then sha256sum \"\$b\" || exit 1; fi
done"
  status=0
  inventory_out="$(run_ssh "$inventory_cmd")" || status=$?
  if [ "$status" -ne 0 ]; then
    echo "deploy.sh: rollback inventory of backup set ${RB} failed; nothing was written" >&2
    echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
    exit 5
  fi
  # The far side's output is untrusted: accept only "<64 hex>  <exact backup name>" for
  # one of the three names; the first accepted line per name wins.
  while IFS= read -r line; do
    h="${line%%  *}"
    bname="${line#*  }"
    [ "$bname" != "$line" ] || continue
    [[ "$h" =~ ^[0-9a-f]{64}$ ]] || continue
    for n in "${RB_FILES[@]}"; do
      if [ "$bname" = "${n}.bak-${RB}" ] && [ -z "${RB_SHA[$n]:-}" ]; then
        RB_SHA["$n"]="$h"
      fi
    done
  done <<< "$inventory_out"

  # --- Phase A2: refuse a missing or incomplete set (exit 6), before any write -------------
  absent=()
  for n in "${RB_FILES[@]}"; do
    [ -n "${RB_SHA[$n]:-}" ] || absent+=("${n}.bak-${RB}")
  done
  if [ "${#absent[@]}" -gt 0 ]; then
    if [ "${#absent[@]}" -eq "${#RB_FILES[@]}" ]; then
      echo "deploy.sh: rollback refused: there is no backup set for stamp ${RB} (absent: ${absent[*]}); nothing was written" >&2
    else
      echo "deploy.sh: rollback refused: the backup set for stamp ${RB} is incomplete (absent, or not a regular file: ${absent[*]}); nothing was written" >&2
    fi
    echo "deploy.sh: a set is restored whole or not at all; a set with no sidecar backup is refused too, since restoring its bundles under today's sidecar would publish a provenance claim for a commit no longer served" >&2
    exit 6
  fi

  # --- Phase A3: fetch every backup's bytes into the scratch directory, and verify ------
  # Bytes go to a file, never a shell variable (which would drop trailing newlines).
  for n in "${RB_FILES[@]}"; do
    b="${n}.bak-${RB}"
    f="$SSH_SCRATCH_DIR/fetched-${n}"
    fetch_cmd="cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
if [ -f $(sq "$b") ] && ! [ -L $(sq "$b") ]; then exec cat $(sq "$b"); fi
exit 1"
    status=0
    run_ssh "$fetch_cmd" > "$f" || status=$?
    if [ "$status" -ne 0 ]; then
      echo "deploy.sh: rollback could not fetch ${b}; nothing was written" >&2
      echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
      exit 5
    fi
    if [ "$(sha256sum < "$f" | cut -d' ' -f1)" != "${RB_SHA[$n]}" ]; then
      echo "deploy.sh: rollback: the fetched bytes of ${b} do not match its inventory sha256; nothing was written" >&2
      exit 4
    fi
    RB_FETCHED["$n"]="$f"
  done

  # --- Phase B: back up every live file under this run's fresh stamp ---------------------
  # No live file has been written yet. Afterwards, every live file that existed has its
  # pre-rollback bytes in <name>.bak-$STAMP, so this rollback is itself reversible.
  for n in "${RB_FILES[@]}"; do
    backup_live "$n" || rollback_stop 5 "$n" "its backup as ${n}.bak-${STAMP} failed; no live file has been written"
  done

  # --- Phase C: restore in place and verify, bundles first, sidecar last -----------------
  for n in "${RB_FILES[@]}"; do
    status=0
    run_ssh "$(remote_copy_cmd "$n")" < "${RB_FETCHED[$n]}" || status=$?
    if [ "$status" -ne 0 ]; then
      rollback_stop 5 "$n" "the in-place copy failed (reason: $(ssh_reason_label "$status")); ${n} may be partly written"
    fi
    verify_cmd="cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
if ! command -v sha256sum >/dev/null 2>&1; then echo deploy.sh: remote has no sha256sum >&2; exit 5; fi; sha256sum $(sq "$n")"
    status=0
    remote_out="$(run_ssh "$verify_cmd")" || status=$?
    if [ "$status" -ne 0 ]; then
      rollback_stop 5 "$n" "the far-side hash of the live file failed (reason: $(ssh_reason_label "$status")); ${n} is unverified"
    fi
    live_sha="$(printf '%s\n' "$remote_out" | head -n 1 | cut -d' ' -f1)"
    if [ "$live_sha" != "${RB_SHA[$n]}" ]; then
      rollback_stop 4 "$n" "hash mismatch: the live ${n} does not match ${n}.bak-${RB}"
    fi
    RB_RESTORED+=("$n")
  done

  # --- Success record ---------------------------------------------------------------------
  echo "rolled back  to backup set ${RB}   (the files live just before the deploy that made ${RB})"
  echo "stamp     ${STAMP}"
  echo "index.html         ${RB_SHA[index.html]}  verified"
  echo "gap-handoff.html   ${RB_SHA[gap-handoff.html]}  verified"
  echo "site-provenance.json   ${RB_SHA[site-provenance.json]}  verified"
  print_backups_line
  echo "pruned    none"
  echo "target    the configured per-site directory, via the configured ssh alias"
  echo "next      run the drift check (scripts/drift-check.sh) to confirm the bytes a request"
  echo "          returns; this rollback wrote no verified marker, and its own backup set"
  echo "          (stamp ${STAMP}) is never pruned automatically — remove it by hand"
  exit 0
fi

# --- Per-bundle deploy: one ssh invocation per step ---------------------------------
declare -A REMOTE_SHA
declare -A LOCAL_SHA

for bundle in "${BUNDLES[@]}"; do
  LOCAL_SHA["$bundle"]="$(git show "${REF}:${bundle}" | sha256sum | cut -d' ' -f1)"
  # Step 1: backup the live file on the far side, if present.
  backup_live "$bundle" || exit 5

  # Step 2: stream the ref's bytes to a mktemp stage on the far side, then overwrite
  # the live file in place (never rename over it — see header note on bind-mount
  # inode following).
  status=0
  git show "${REF}:${bundle}" | run_ssh "$(remote_copy_cmd "$bundle")" || status=$?
  if [ "$status" -ne 0 ]; then
    echo "deploy.sh: remote copy step failed for ${bundle}" >&2
    echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
    exit 5
  fi

  # Step 3: hash the remote file and compare against the ref's bytes, hashed locally.
  verify_cmd="cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
if ! command -v sha256sum >/dev/null 2>&1; then echo deploy.sh: remote has no sha256sum >&2; exit 5; fi; sha256sum $(sq "$bundle")"
  status=0
  remote_out="$(run_ssh "$verify_cmd")" || status=$?
  if [ "$status" -ne 0 ]; then
    echo "deploy.sh: remote verify step failed for ${bundle}" >&2
    echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
    exit 5
  fi
  REMOTE_SHA["$bundle"]="$(printf '%s\n' "$remote_out" | cut -d' ' -f1)"
done

# --- Verify --------------------------------------------------------------------------
mismatch=0
for bundle in "${BUNDLES[@]}"; do
  if [ "${REMOTE_SHA[$bundle]}" != "${LOCAL_SHA[$bundle]}" ]; then
    echo "deploy.sh: hash mismatch for ${bundle}" >&2
    mismatch=1
  fi
done

if [ "$mismatch" -ne 0 ]; then
  exit 4
fi

# --- Provenance sidecar: generated and deployed only after both bundles above have
# copied and hash-verified successfully. Written last, deliberately (see header) —
# it asserts "this commit is deployed", and a failure here must never leave a stale
# or partial sidecar published as if it were current.
SIDECAR_NAME="site-provenance.json"
SIDECAR_CONTENT="$("$MAKE_PROVENANCE_SH" --ref "$REF")"
SIDECAR_LOCAL_SHA="$(printf '%s' "$SIDECAR_CONTENT" | sha256sum | cut -d' ' -f1)"

# Step 1: backup the live sidecar on the far side, if present.
backup_live "$SIDECAR_NAME" || exit 5

# Step 2: stream the generated bytes to a mktemp stage on the far side, then overwrite
# the live file in place (never rename over it — see header note on bind-mount inode
# following).
status=0
printf '%s' "$SIDECAR_CONTENT" | run_ssh "$(remote_copy_cmd "$SIDECAR_NAME")" || status=$?
if [ "$status" -ne 0 ]; then
  echo "deploy.sh: remote copy step failed for ${SIDECAR_NAME}" >&2
  echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
  exit 5
fi

# Step 3: hash the remote file and compare against the locally-computed hash of the
# generated bytes.
sidecar_verify_cmd="cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
if ! command -v sha256sum >/dev/null 2>&1; then echo deploy.sh: remote has no sha256sum >&2; exit 5; fi; sha256sum $(sq "$SIDECAR_NAME")"
status=0
sidecar_remote_out="$(run_ssh "$sidecar_verify_cmd")" || status=$?
if [ "$status" -ne 0 ]; then
  echo "deploy.sh: remote verify step failed for ${SIDECAR_NAME}" >&2
  echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
  exit 5
fi
SIDECAR_REMOTE_SHA="$(printf '%s\n' "$sidecar_remote_out" | cut -d' ' -f1)"

if [ "$SIDECAR_REMOTE_SHA" != "$SIDECAR_LOCAL_SHA" ]; then
  echo "deploy.sh: hash mismatch for ${SIDECAR_NAME}" >&2
  exit 4
fi

# --- Retention (CER-027): only reached once both bundles and the sidecar verified ----
# Mark this deploy's backup set verified, then prune verified sets beyond BACKUP_KEEP.
# A set without a marker (a failed deploy's rollback copy, or a set older than this
# scheme) is never a candidate. The current stamp is dropped before counting, so it is
# kept even when other stamps sort after it (clock skew).
MARKER_PREFIX=".deploy-verified-"
marker_name="${MARKER_PREFIX}${STAMP}"
marker_cmd="cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
if [ -e $(sq "$marker_name") ] || [ -L $(sq "$marker_name") ]; then echo 'deploy.sh: verified marker name already exists' >&2; exit 5; fi
set -C
: > $(sq "$marker_name")"
status=0
run_ssh "$marker_cmd" || status=$?
if [ "$status" -ne 0 ]; then
  echo "deploy.sh: every file verified, but the verified marker for stamp ${STAMP} could not be written; no backups were pruned" >&2
  echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
  exit 5
fi

list_cmd="cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
for f in ${MARKER_PREFIX}*; do if [ -e \"\$f\" ] || [ -L \"\$f\" ]; then printf '%s\\n' \"\$f\"; fi; done"
status=0
marker_listing="$(run_ssh "$list_cmd")" || status=$?
if [ "$status" -ne 0 ]; then
  echo "deploy.sh: every file verified, but listing verified markers failed; no backups were pruned" >&2
  echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
  exit 5
fi

# The listing is untrusted: keep only names whose stamp has the exact stamp shape.
verified_stamps=()
while IFS= read -r line; do
  s="${line#"$MARKER_PREFIX"}"
  [ "$s" != "$line" ] || continue
  [[ "$s" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || continue
  [ "$s" != "$STAMP" ] || continue
  verified_stamps+=("$s")
done <<< "$marker_listing"

# Newest BACKUP_KEEP - 1 other verified stamps are kept; the rest are pruned, oldest
# first.
PRUNE_STAMPS=()
if [ "${#verified_stamps[@]}" -gt 0 ]; then
  mapfile -t sorted_desc < <(printf '%s\n' "${verified_stamps[@]}" | sort -u -r)
  if [ "${#sorted_desc[@]}" -gt $((BACKUP_KEEP - 1)) ]; then
    mapfile -t PRUNE_STAMPS < <(printf '%s\n' "${sorted_desc[@]:$((BACKUP_KEEP - 1))}" | sort)
  fi
fi

PRUNED=()
for s in "${PRUNE_STAMPS[@]}"; do
  # One ssh call per set (CER-030). It removes the set's files one at a time, in this
  # order — the three backups, then the marker — and stops at the first removal that
  # fails, so a set whose backups could not all be removed keeps its marker and a later
  # deploy retries it. It prints one line per file present: "removed <name>" once that
  # file is gone, "remains <name>" for the file that failed and every file after it. A
  # file already absent gets no line.
  set_names=("index.html.bak-${s}" "gap-handoff.html.bak-${s}" "site-provenance.json.bak-${s}" "${MARKER_PREFIX}${s}")
  prune_cmd="cd $(sq "$DIR") 2>/dev/null || exit ${REMOTE_DIR_MISSING_EXIT}
failed=0
for n in $(sq "${set_names[0]}") $(sq "${set_names[1]}") $(sq "${set_names[2]}") $(sq "${set_names[3]}"); do
  if [ -e \"\$n\" ] || [ -L \"\$n\" ]; then
    if [ \"\$failed\" -eq 0 ] && rm -f -- \"\$n\" && ! [ -e \"\$n\" ] && ! [ -L \"\$n\" ]; then
      printf 'removed %s\\n' \"\$n\"
    else
      failed=1
      printf 'remains %s\\n' \"\$n\"
    fi
  fi
done
exit \"\$failed\""
  status=0
  prune_out="$(run_ssh "$prune_cmd")" || status=$?
  if [ "$status" -ne 0 ]; then
    # The far side's report is untrusted: accept only lines naming one of this set's
    # four names.
    set_removed=()
    set_remains=()
    reported=0
    while IFS= read -r line; do
      verb="${line%% *}"
      fname="${line#* }"
      [ "$fname" != "$line" ] || continue
      known=0
      for n in "${set_names[@]}"; do [ "$fname" = "$n" ] && known=1; done
      [ "$known" -eq 1 ] || continue
      case "$verb" in
        removed) set_removed+=("$fname"); reported=1 ;;
        remains) set_remains+=("$fname"); reported=1 ;;
      esac
    done <<< "$prune_out"
    echo "deploy.sh: every file verified, but pruning failed at backup set ${s} (that set may be partly removed; while its marker remains, a later deploy retries it)" >&2
    echo "deploy.sh: reason: $(ssh_reason_label "$status")" >&2
    if [ "${#PRUNED[@]}" -gt 0 ]; then
      echo "deploy.sh: pruned before the failure: ${PRUNED[*]}" >&2
    elif [ "${#set_removed[@]}" -gt 0 ]; then
      echo "deploy.sh: pruned before the failure: no whole set (files were removed from set ${s}; see below)" >&2
    else
      echo "deploy.sh: pruned before the failure: none — no backups were pruned" >&2
    fi
    not_attempted=("${PRUNE_STAMPS[@]:$(( ${#PRUNED[@]} + 1 ))}")
    if [ "${#not_attempted[@]}" -gt 0 ]; then
      echo "deploy.sh: not attempted after the failure: ${not_attempted[*]}" >&2
    fi
    if [ "${#set_removed[@]}" -gt 0 ]; then
      echo "deploy.sh: in backup set ${s}, removed: ${set_removed[*]}" >&2
    else
      echo "deploy.sh: in backup set ${s}, removed: none" >&2
    fi
    if [ "${#set_remains[@]}" -gt 0 ]; then
      echo "deploy.sh: in backup set ${s}, remains: ${set_remains[*]}" >&2
    elif [ "$reported" -eq 0 ]; then
      echo "deploy.sh: in backup set ${s}, remains: none reported (the far side reported no file of this set, so it may be untouched)" >&2
    else
      echo "deploy.sh: in backup set ${s}, remains: none" >&2
    fi
    exit 5
  fi
  PRUNED+=("$s")
done

# --- Success record --------------------------------------------------------------------
RESOLVED_REF="$(git rev-parse "${REF}")"

echo "deployed  ${RESOLVED_REF}   (${REF})"
echo "stamp     ${STAMP}"
echo "index.html         ${LOCAL_SHA[index.html]}  verified"
echo "gap-handoff.html   ${LOCAL_SHA[gap-handoff.html]}  verified"
echo "site-provenance.json   ${SIDECAR_LOCAL_SHA}  verified"
print_backups_line
if [ "${#PRUNED[@]}" -gt 0 ]; then
  echo "pruned    ${PRUNED[*]}"
else
  echo "pruned    none"
fi
echo "target    the configured per-site directory, via the configured ssh alias"
echo "next      run the drift check to confirm the bytes a request returns (INFRA-007); on a"
echo "          host that has never served site-provenance.json, first add its bind-mount to"
echo "          docker-compose.yml and recreate the container (docker compose up -d) — this"
echo "          deploy alone does not add the mount or touch the container"

exit 0
