---
id: INFRA-018
rail: INFRA
title: Rollback and a truthful backup report for deploy.sh
status: planned
phase: "14"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/deploy.sh

touches:
  - scripts/deploy-selftest.sh
  - docs/architecture.md
  - docs/checkpoints.md
  - docs/cer/backlog.md

narrative_roles: []
---

## Context

Closes CER-031, CER-037 and CER-030.
- Add `deploy.sh --rollback <stamp>`. It restores each served file from its `.bak-<stamp>` by
  overwriting in place, through the existing verified copy path (bind mounts pin inodes). It then
  re-verifies sha256 values, restores the provenance sidecar, and prints the usual success block
  (CER-031).
- The success block's backups line lists only backups the remote step confirmed it wrote. A
  first deploy into an empty target lists none (CER-037).
- The prune report is exact per file, not per set (CER-030).

Selftests cover a first deploy into an empty target and a rollback. `docs/architecture.md` and
the manual rollback procedure in `docs/checkpoints.md` stop calling the `.bak` set a rollback
until this mode exists. Builds after INFRA-017, since both edit `deploy.sh`.

Operator ruling 2026-09-30: `release.sh` never rolls back on its own. The operator runs this
mode by hand.

Phase 14 plan: approved by the operator on 2026-09-30, synthesized from two independent planner drafts (docs/phases/phase-14.md).

**Operator rulings (2026-10-01)**

The operator confirmed all four design choices:
1. A backup set with no sidecar backup is refused with exit 6, never restored bundles-only.
2. `docs/checkpoints.md` gains the short rollback procedure.
3. Backup sets that a rollback creates are never pruned automatically; the operator removes
   them by hand.
4. `--rollback --dry-run` is refused with exit 64.

The operator also directed that, after the build and before review, a separate proving agent
tries to break the rollback.

**Amended 2026-10-01 after the proving pass.** The proving pass found three things, and this
amendment handles each.
- **MEDIUM.** A 0-byte or partial backup was accepted, restored and reported as verified. The
  reproduction: take a complete set, run `: > index.html.bak-S`, then `--rollback S`. The live
  `index.html` became empty and the run exited 0. The cause is that the backup step's
  `cat <name> > <bak>` leaves a partial file when the write fails (ENOSPC, for example), so the
  set still looks complete. The amendment makes two fixes:
  - the backup step writes atomically;
  - the inventory counts an empty backup as missing.
- **LOW.** A repeated `--ref` or `--rollback` was accepted, and the last value won. A repeated
  option is now a usage error.
- **LOW, documented, no change.** A file that was absent at deploy time has no backup in that
  deploy's set, so that set is incomplete and `--rollback` refuses it. This behaviour is kept
  and stated in Ensures and Out of scope.

Each fix gets a selftest case with its own token. The pinned pre-story commit is unchanged.

## Requires

INFRA-017 is complete and merged. This story builds on its `deploy.sh`: usage exits 64, `REF_RE`,
and the environment wins over `deploy.env`. The pre-story commit used by the Tests block is
`38d307597b3f7ee5e23a69e26538de48927ba24e`, which was main when this spec was written.
`scripts/deploy.sh` is byte-identical there to INFRA-017's merge.

## Ensures

The fixes below hold, each proven by selftest cases whose report names end in one of these
tokens: `INFRA-018/CER-0NN`, `INFRA-018/ATOMIC`, `INFRA-018/EMPTY` or `INFRA-018/REPEAT`.
Every such case passes on the fixed tree and fails when `deploy.sh` is reverted to the
pre-story commit. The fixes are:
- `deploy.sh --rollback <stamp>` restores all three files from a complete set, in place and
  sha256-verified. It refuses a missing or incomplete set with exit `6` and writes nothing.
  - A set is incomplete when any of its three backups is absent, is not a regular file, or is
    empty (0 bytes).
  - A set whose deploy found a file absent therefore has no backup of that file, and it too is
    refused.
- A backup write that fails leaves no `<name>.bak-<stamp>` name and no temporary file behind.
- The `backups` line names only the backups the far side confirmed it wrote.
- A prune failure names each removed file and each remaining file of the failed set.
- Any option given more than once exits `64` before any ssh call.

The header, `docs/architecture.md`, the `docs/checkpoints.md` preamble and the three backlog rows
state the new behaviour, and every existing selftest still passes.

## Instructions

1. **Arguments.**
   - Add `--rollback <stamp>`.
   - Each of these exits `64` before any git or ssh work:
     - `--rollback` with no value;
     - a stamp outside `^[0-9]{8}T[0-9]{6}Z$`;
     - `--rollback` together with `--ref` or `--dry-run`;
     - any of `--ref`, `--rollback` or `--dry-run` given more than once. The message says
       "given more than once" and names the option. Never let the last value win (amended
       2026-10-01).
   - None of those refusals says "unrecognized argument", because that text is kept for unknown
     flags.
   - The usage block in the header gains the line `#   deploy.sh --rollback <stamp>`, written
     exactly so.

2. **Rollback, CER-031.**
   - A rollback runs the same configuration and alias checks as a deploy. It skips the dirty
     check, because no ref is involved.
   - `--rollback S` means "restore the files that were live just before the deploy that made
     stamp S".
   - **Inventory.** First, one ssh call reports the far-side sha256 of each of
     `index.html.bak-S`, `gap-handoff.html.bak-S` and `site-provenance.json.bak-S`. A backup
     counts only if it is a regular file, is not a symlink, and is non-empty (`[ -s ]`).
     - Served bundles and the sidecar are never legitimately empty, so an empty backup can only
       be the remains of a failed write. It must never be restored (amended 2026-10-01).
     - deploy.sh accepts only lines whose name is one of those three exact names and whose hash
       is 64 hex characters, because the far side's output is untrusted.
   - **Refusal.** If any of the three backups does not count, the rollback exits `6` before any
     write and names those backups. It must never name the directory.
     - This includes the set left by a deploy that found a live file absent, because that set
       has no backup of the file. Keep this behaviour (proving pass, 2026-10-01).
     - This includes a set with no sidecar backup. The first deploy that wrote a sidecar leaves
       exactly that kind of set, and restoring its bundles under today's sidecar would publish a
       provenance claim for a commit that is no longer served.
     - A verified marker is not required, because an unmarked set is exactly the copy a failed
       deploy leaves behind.
   - **Restore.** Then, for each file in turn (the two bundles first, the sidecar last, as in a
     deploy):
     - Fetch the backup's bytes into a file in the ssh scratch directory. Never hold them in a
       shell variable, which drops trailing newlines. Their local sha256 must equal the
       inventory value, or the rollback exits `4`.
     - Back up the live file under this run's own fresh stamp, using the deploy's backup step.
       The rollback is then itself reversible.
     - Stream the fetched file through `remote_copy_cmd`. Never use `mv`: bind mounts pin inodes.
     - Hash the live file on the far side. It must equal the inventory value, or the rollback
       exits `4`.
   - **Failure.** The rollback stops at the first failure. The message names the file that
     failed and the files already restored.
   - **No retention.** A rollback writes no verified marker and prunes nothing.
   - **Success block.** On success it prints the usual success block, with these changes:
     - the first line starts `rolled back` and names S;
     - `stamp` is the fresh stamp;
     - there is a line for each of the three files, showing its sha256 and `verified`;
     - the truthful `backups` line (step 3);
     - `pruned    none`;
     - the `next` line says to run the drift check.

3. **Backups line, CER-037, and an atomic backup step (amended 2026-10-01).**
   - **Atomic write.** `remote_backup_cmd` never writes to `<name>.bak-<stamp>` directly:
     - It copies the live file into a temporary file made by the far side's `mktemp`, in the
       same directory (for example `./.<name>.backup-XXXXXXXXXX`).
     - It removes that temporary file on every exit path, as `remote_copy_cmd` does.
     - Only after the copy succeeds does it publish the temporary file under the backup name,
       with `ln -- <tmp> <bak>`. A hard link fails if the name already exists in any form, a
       dangling symlink included, so it keeps INFRA-012's noclobber guarantee. A plain `mv`
       would replace a name planted there.
     - On failure, no `.bak-<stamp>` name exists. The backup file then has `mktemp`'s mode,
       0600, which is fine because backups are never served.
   - **Token.** `remote_backup_cmd` prints a fixed token on stdout only after the publish
     succeeds. deploy.sh records a backup's name only when that token comes back.
   - Factor this into one helper that both the deploy steps and the rollback use.
   - The `backups` line lists the recorded names. With none recorded, it reads
     `backups   none` followed by a short reason.

4. **Prune report, CER-030.**
   - Each set's removal is still one ssh call. It removes, one at a time and in this order, the
     three backups and then the marker. It stops at the first `rm` that fails, and prints one
     line per file: `removed <name>` or `remains <name>`. Files that are already absent get no
     line.
   - deploy.sh accepts only lines naming one of that set's four names.
   - On failure, keep the existing lines, and add these two:
     - `deploy.sh: in backup set <S>, removed: <names|none>`
     - `deploy.sh: in backup set <S>, remains: <names|none>`
   - Print "none — no backups were pruned" only when no file at all was removed.
   - The marker is still removed last, so a later deploy retries a set that is only partly
     removed.
   - In the exit-5 row, name the cause of an existing backup name: two deploys that run in the
     same second.

5. **Header.**
   - Add a rollback bullet to the "What it does" list.
   - Add the row `#   6  rollback refused: the backup set for that stamp is missing or incomplete;
     nothing was written`.
   - Make the retention bullet's "rollback copy" wording point at `--rollback`.

6. **Selftests** (`deploy-selftest.sh`, appended as cases 17 to 22, and listed in its header).
   - Each report name ends with its token. No other case carries an `INFRA-018/` token.
   - Each case must report `FAIL`, not abort the script, when run against the pre-story
     `deploy.sh`.
   - Use a fresh target per case, never the target of an earlier run in the same second.
   - **17, CER-037:**
     - (a) A deploy into an empty directory gives exit 0. No `*.bak-*` file exists, and the
       `backups` line contains no `.bak-`.
     - (b) A deploy into a target with both bundles and no sidecar gives exit 0. The `backups`
       line names `index.html.bak-<stamp>` and `gap-handoff.html.bak-<stamp>`, and no
       `site-provenance.json.bak-`.
   - **18, CER-031.** Seed a set at a fixed past stamp with `seed_set`, whose bytes end in a
     newline.
     - (a) A rollback over live files gives exit 0. Each live file then equals its backup, keeps
       its inode, and has its old bytes in `<name>.bak-<fresh stamp>`. The `backups` line names
       all three, no marker is written for the fresh stamp, and no stage file is left.
     - (b) A stamp with no set, (c) a set with no sidecar backup, and (d) a set whose
       `gap-handoff.html.bak-` is a symlink to the sentinel each give exit 6.
       - Take a snapshot of the target before and after: every name, inode and sha256. The two
         snapshots are identical and the sentinel is intact.
       - (c) and (d) name the backup concerned, and no case names the directory.
     - (e) With `CORRUPT_FLAG` set, a rollback in `FIXTURE_TARGET` gives exit 4 and names
       `index.html`.
     - (f) Each of the four usage forms from step 1 gives exit 64. No ssh runs, and the output
       does not say "unrecognized argument".
   - **19, CER-030.** Seed `BACKUP_KEEP` verified sets, so exactly the oldest is pruned. Replace
     that set's `gap-handoff.html.bak-` with a non-empty directory.
     - The deploy exits 5 and never says "no backups were pruned".
     - The `removed:` line names that set's `index.html.bak-` and not its `gap-handoff.html.bak-`.
     - The `remains:` line names its `gap-handoff.html.bak-`.
     - Its `index.html.bak-` is gone and its marker is still present.
   - **20, ATOMIC.** In a fresh target, make the live `index.html` unreadable (`chmod 000`), so
     the far side's read fails after the write target is opened. Then deploy.
     - Expect exit 5. No entry whose name contains `index.html.ba` exists in `ls -A`, which
       covers both a backup name and a temporary file.
     - Restore the mode afterwards.
     - If `cat` can read the file anyway (when running as root, for example), report the case
       as `FAIL` with a precondition message, so that it cannot pass vacuously.
   - **21, EMPTY.** Seed a complete set, run `: > index.html.bak-<S>`, then roll back to `<S>`.
     Expect the 18(b) to 18(d) refusal contract: exit 6, identical snapshots, the refusal names
     `index.html.bak-<S>`, and it does not name the directory.
   - **22, REPEAT.** Run `--ref HEAD --ref HEAD`, `--dry-run --dry-run` and
     `--rollback <S> --rollback <S>`, each in a fresh target.
     - Each gives exit 64 with no ssh run.
     - The output says "more than once".

7. **Docs.**
   - In `docs/architecture.md` § Deploy, add one sentence to the `deploy.sh` bullet stating
     three things:
     - what `deploy.sh --rollback <stamp>` restores;
     - that it overwrites in place and re-verifies;
     - that it refuses a set that is "missing or incomplete".
   - `docs/checkpoints.md` has no rollback procedure today. In its preamble, after the
     drift-check paragraph and before the first `---`, add a short procedure:
     - run `scripts/deploy.sh --rollback <stamp>` by hand;
     - then run `scripts/drift-check.sh`;
     - never `mv` a backup over a live file.
   - `docs/cer/backlog.md`: append `**RESOLVED Phase 14 — INFRA-018.**` to the Finding cell of
     each of the three rows, leaving the rows in place.

Ideology notes:
- *Name the class, not the instance.* Every new message names files and stamps, never the
  alias or the directory. Selftest cases (b) to (d) assert this.
- *Assert the invariant, not a proxy for it.* A restore is judged by the far-side sha256 against
  the inventory, not by the exit status of the copy. The served-bytes check stays with
  `drift-check.sh`.

Spec-preflight flags three constants, and all three are intended:
- `BACKUP_KEEP` is defined in `deploy.sh`.
- `CORRUPT_FLAG` and `FIXTURE_TARGET` are existing variables in `deploy-selftest.sh`.

The scanner misses shell definitions.

Proportionality: this spec is longer than the baseline. It carries three independent fixes
plus the proving pass's amendments, and one of the fixes is a new mode with a refusal
contract. Each fix needs cases that fail
without it.

## Tests

Run from the repository root.

```bash
for t in scripts/*-selftest.sh; do bash "$t" && continue; exit 1; done
```

```bash
set -u
F=0; fail() { echo "FAIL: $*"; F=$((F + 1)); }
out="$(bash scripts/deploy-selftest.sh 2>&1)"
# Each case fails without its fix: a throwaway copy of scripts/ with deploy.sh reverted
# to the pre-story commit, running this story's selftest. The copy is deleted.
PRE=38d307597b3f7ee5e23a69e26538de48927ba24e
t="$(mktemp -d)"; mkdir "$t/scripts"; cp scripts/*.sh scripts/*.py "$t/scripts/"; git -C "$t" init -q
git show "$PRE:scripts/deploy.sh" > "$t/scripts/deploy.sh"
mut="$(bash "$t/scripts/deploy-selftest.sh" 2>&1)"; rm -rf "$t"
for pair in CER-037:2 CER-031:9 CER-030:1 ATOMIC:1 EMPTY:1 REPEAT:3; do
  c="${pair%%:*}"; min="${pair##*:}"
  n="$(printf '%s\n' "$out" | grep -c "^PASS: .*INFRA-018/$c\$")"
  m="$(printf '%s\n' "$mut" | grep -c "^FAIL: .*INFRA-018/$c ")"
  [ "$n" -ge "$min" ] || fail "fewer than $min passing INFRA-018/$c cases ($n)"
  [ "$m" -eq "$n" ] || fail "$m of $n INFRA-018/$c cases fail with deploy.sh reverted"
done
printf '%s\n' "$out" | grep -q '^FAIL: ' && fail "deploy-selftest has a failing case"

# Content-level checks (comment prefixes and line wraps normalised).
norm() { sed 's/^[[:space:]]*#[[:space:]]*//' "$1" | tr '\n' ' ' | tr -s ' '; }
grep -Eq '^#   6  ' scripts/deploy.sh || fail "deploy.sh exit-code table has no 6 row"
grep -Eq '^#   deploy\.sh --rollback <stamp>$' scripts/deploy.sh || fail "deploy.sh usage block has no --rollback line"
norm scripts/deploy.sh | grep -qF 'same second' || fail "deploy.sh exit-5 row does not name the same-second cause"
arch="$(tr -s ' \n' ' ' < docs/architecture.md)"
printf '%s' "$arch" | grep -qF 'deploy.sh --rollback <stamp>' || fail "architecture.md does not describe --rollback"
printf '%s' "$arch" | grep -qF 'missing or incomplete' || fail "architecture.md does not state the refusal"
top="$(sed '/^---$/q' docs/checkpoints.md | tr -s ' \n' ' ')"
printf '%s' "$top" | grep -qF 'deploy.sh --rollback <stamp>' || fail "checkpoints.md preamble has no rollback procedure"
for c in 030 031 037; do
  grep -E "^\| CER-$c \|" docs/cer/backlog.md | grep -qF 'RESOLVED Phase 14 — INFRA-018' || fail "CER-$c not resolved"
done
[ "$F" -eq 0 ] && echo "INFRA-018 checks: all passed" || { echo "INFRA-018 checks: $F failed"; exit 1; }
```

Acceptance: the suite is green, and the second block prints `INFRA-018 checks: all passed`.

Verification when this spec was written:
- **Against main.** Every check in the second block failed (12 failures), except two:
  - the `m -eq n` equalities, which hold at 0 = 0 and are gated by the count check beside
    them;
  - the no-failing-case regression guard.
- **Against a throwaway implementation.** The whole block passed, and so did every selftest.
  That implementation has since been deleted.
- **Re-run when amended (2026-10-01).** I ran the block again:
  - against main at `0509c0a`, where `deploy.sh` is unchanged since the pinned commit: 15
    failures, including all six count checks;
  - against a prototype built on the INFRA-018 build branch with the amendments applied:
    all passed, and so did every selftest.

  The new ATOMIC, EMPTY and REPEAT cases also fail against the build branch's unamended
  `deploy.sh`, which is the proving pass's defect.

## Out of scope

- Automatic rollback from `release.sh` or on a drift failure. By the operator ruling of
  2026-09-30, the operator runs `--rollback` by hand.
- Restoring a set that is incomplete, including a set whose only gap is a missing sidecar
  backup. It is refused with exit 6, and such a set is restored by hand if it is ever wanted.
- Rolling back to the state before a deploy that found a live file absent. That deploy's set
  has no backup of the file, so it is incomplete and refused with exit 6. This is
  deliberate: rollback restores whole sets and never deletes a live file (proving pass,
  2026-10-01).
- Restoring an empty (0-byte) backup. It is treated as missing, because served files are
  never legitimately empty.
- `--rollback --dry-run`. It is refused with exit 64 rather than half-implemented, since a dry
  run makes no ssh call and so could not check the set.
- Pruning or marking the backup sets a rollback writes. They are unmarked, so retention never
  touches them, and the operator removes them by hand.
- Restoring `nginx.conf`, or any container action.
- Changes to `drift-check.sh`, `make-provenance.sh` or the other selftests.
