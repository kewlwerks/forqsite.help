---
id: INFRA-024
rail: INFRA
title: release.sh pushes exactly the commit and tag it deployed
status: planned
phase: "14-post1"
story_class: code
auth_gated: false
schema_introduces: false
primary_files:
  - scripts/release.sh
touches:
  - scripts/release-selftest.sh
  - docs/architecture.md
  - docs/cer/backlog.md
narrative_roles: []
---

## Context

This closes the CP-14-post1 security audit's MEDIUM finding and its LOW companion. The
operator added this story to Phase 14-post1 on 2026-10-01, before the checkpoint, because the
project fixes MEDIUM findings before a phase ends.

**The MEDIUM finding.** INFRA-023 made `release.sh` push with explicit `src:dst` refspecs. That
fixed *where* the push goes, but not *what* it pushes. `refs/heads/main:refs/heads/main`
sends whatever `main` points to at push time. A commit that lands on `main` while the deploy
and drift check run would be pushed without appearing in the "the push will also carry"
listing, which is built before any write. The provenance and the tag would still name the
release commit.

**The LOW finding.** `rel-<t8>` is resolved separately by `deploy.sh`, by `drift-check.sh` and
by the push. Nothing compares any of those resolutions with `RELEASE_COMMIT`. If the tag were
moved while the job ran, origin could end up with a `rel-<t8>` that differs from the commit in
the live sidecar.

**Intended shape** (operator-approved 2026-10-01; the spec-writer settles the details):
- Capture `RELEASE_COMMIT` and the tag object's sha right after `git tag`.
- Push `${RELEASE_COMMIT}:refs/heads/<branch>` and `<tag object sha>:refs/tags/<tag>`, keeping
  `--atomic`. This applies to the job's own push and to every printed recovery push.
- Before pushing, check that `deploy.sh`'s `deployed <sha>` and `drift-check.sh`'s `ref <sha>`
  both equal `RELEASE_COMMIT`. On a mismatch, stop with a distinct, documented exit, push
  nothing, and print recovery steps.
- Add selftest cases for both:
  - a commit added to `main` during the deploy window is NOT pushed;
  - a tag moved mid-run is caught before the push.
- Update the header invariants and `docs/architecture.md`.

Out of scope: the `pushInsteadOf` gap. It is stated and ruled (INFRA-023).

**Settled details (spec-writer, 2026-10-01).**
- `RELEASE_COMMIT` stays where it is (`git rev-parse HEAD` straight after the commit), because
  the three-file check and `git tag` already use it. The new `TAG_OBJECT` is read right after
  `git tag` succeeds.
- **One new exit, 18.** It is used at three points, and nothing is pushed at any of them.
- **Printed pushes carry shas, not names.** Names do not help with the hijack case: since
  INFRA-023 both sides of every refspec are explicit, so no `remote.origin.push` can remap
  either form. Names fail the moved-ref case. A recovery line is often run minutes or days
  after the stop. By then `main` may have new commits, or someone may have re-pointed the tag.
  A named line would push whatever those refs name at that time, which is the MEDIUM finding
  again. A sha line pushes only what was deployed and drift-checked.
- **The cost of sha lines.** Suppose the operator abandons the release and then runs the
  finish line anyway. The sha line would still re-create `rel-<t8>` on origin, where a named
  line would fail. That is not silent: the next run refuses with 8 ("origin has tag …, which
  is missing here"). See the open questions below.

**Open questions for the operator.** The spec is buildable as written; these confirm defaults.
1. When `main` moves during the run, the release exits 0, pushes only the release commit, and
   prints a note. It does not exit 18. Is that the right default?
2. A sha finish line run after an abandon re-creates `rel-<t8>` on origin, and the next run
   catches it with 8. Is that acceptable?
3. A `post-commit` hook could add an empty commit before `RELEASE_COMMIT` is read. That commit
   would pass the three-file check and be released in place of the real release commit. A
   check that `RELEASE_COMMIT^` is `PRE` would close this. Should it be filed as a CER?

## Requires

- INFRA-023 is complete (`ce946fa`) and INFRA-022 is complete. main is at `af62731`.
- git 2.28 or later, because one selftest case uses the `reference-transaction` hook. The
  prototype ran on git 2.43.

## Ensures

- The job's push, and every push line it prints, sends the release commit and the tag object
  `git tag` made, both by full sha, to fully qualified destinations.
- `release.sh` exits 18 and pushes nothing in each of these cases:
  - right after `git tag`, `rel-<t8>` is not an annotated tag of the release commit;
  - `deploy.sh`'s `deployed` line is missing, repeated, or names another commit;
  - `drift-check.sh`'s `ref` line is missing, repeated, or names another commit.
- A commit that lands on `main` during the deploy stays local. Origin's `main` becomes the
  release commit, and the run exits 0 with a note.
- The INFRA-021 and INFRA-023 cases that passed at `af62731` still pass.
- `release.sh` and `release-selftest.sh` outside the new sections are byte-identical to
  `af62731`, except for the swaps listed in the Tests block.

## Instructions

1. **Capture and check the tag (`release.sh`).** Add three sections. Each one's first line
   begins `# --- 18: `. Each section is cut at the next `# --- ` header, so it must sit
   directly before the header named here:
   - **Section 1** goes directly before `# --- 15: deploy, shown`. It defines `reported_sha`
     and `stop_moved`. It sets `TAG_OBJECT` from `git rev-parse -q --verify "refs/tags/${TAG}"`.
     If that object is not of type `tag`, or does not peel (`^{commit}`) to `RELEASE_COMMIT`,
     it exits 18. Before exiting, it prints the abandon steps `git tag -d <tag>` and
     `git reset --keep <PRE>`. Nothing has been deployed at that point.
   - **Section 2** goes directly before `# --- 16: the drift check, shown`. It runs
     `reported_sha deployed "$SCRATCH/deploy.out"` and calls `stop_moved` unless the result
     equals `RELEASE_COMMIT`.
   - **Section 3** goes directly before `# --- 17: push, only now`. It does the same with
     `reported_sha ref "$SCRATCH/drift.out"`.
   - **How `reported_sha` parses.** It reads `^<label> +([0-9a-f]+) ` and prints the sha only
     when exactly one line matches. That covers deploy.sh's
     `deployed  <sha>   (<ref>)` and drift-check.sh's `ref                <sha>  <short> "<subj>"`.
     A missing line or a repeated line is a mismatch, so the check fails closed.

   The prototype's sections, which pass the Tests block. Equivalent code passes too, but the
   message texts in single quotes below are what the selftest asserts:

   ```bash
   # --- 18: the tag the job made names the release commit ---------------------------------
   # From here on every push sends RELEASE_COMMIT and TAG_OBJECT by sha, never what main or
   # rel-<t8> names by then (INFRA-024). reported_sha prints the sha on a sibling's one
   # "<label> <sha> " line, or nothing when that line is missing or repeated.
   reported_sha() {
     local re="^$1 +([0-9a-f]+) " line sha="" n=0
     while IFS= read -r line; do
       if [[ "$line" =~ $re ]]; then
         n=$((n + 1))
         sha="${BASH_REMATCH[1]}"
       fi
     done < "$2"
     if [ "$n" -eq 1 ]; then printf '%s\n' "$sha"; fi
   }
   # stop_moved <what> <sha>: exit 18 after the deploy, with the tag's way back and recovery.
   stop_moved() {
     printf 'release: error: %s names %s, not the release commit %s\n' "$1" "${2:-no single commit}" "$RELEASE_COMMIT" >&2
     say "stopped: ${TAG} moved during the run, so the site may serve another commit; nothing was pushed"
     say "to put ${TAG} back where this run made it:"
     say "  git update-ref refs/tags/${TAG} ${TAG_OBJECT}"
     say "then finish or abandon it:"
     print_finish_abandon "$TAG" "$PRE" "$RELEASE_COMMIT" "$TAG_OBJECT"
     exit 18
   }
   TAG_OBJECT="$(git rev-parse -q --verify "refs/tags/${TAG}" 2>/dev/null || true)"
   if [ "$(git cat-file -t "${TAG_OBJECT:-0}" 2>/dev/null || true)" != "tag" ] \
     || [ "$(git rev-parse -q --verify "${TAG_OBJECT}^{commit}" 2>/dev/null || true)" != "$RELEASE_COMMIT" ]; then
     printf 'release: error: right after git tag, %s is not an annotated tag of the release commit %s\n' "$TAG" "$RELEASE_COMMIT" >&2
     say "stopped: ${TAG} moved as it was made; nothing was deployed or pushed"
     say "to abandon it:"
     say "  git tag -d ${TAG}"
     say "  git reset --keep ${PRE}"
     exit 18
   fi

   # --- 18: deploy.sh deployed the release commit -------------------------------------------
   DEPLOYED_SHA="$(reported_sha deployed "$SCRATCH/deploy.out")"
   [ "$DEPLOYED_SHA" = "$RELEASE_COMMIT" ] || stop_moved "deploy.sh's deployed line" "$DEPLOYED_SHA"

   # --- 18: drift-check.sh checked the release commit -----------------------------------------
   CHECKED_SHA="$(reported_sha ref "$SCRATCH/drift.out")"
   [ "$CHECKED_SHA" = "$RELEASE_COMMIT" ] || stop_moved "drift-check.sh's ref line" "$CHECKED_SHA"
   ```

2. **The push and the printed pushes (`release.sh`).** Outside the three sections, make
   exactly the `code_swaps` listed in the Tests block, and nothing else:
   - **`print_finish_abandon` signature.** It takes `commit` and `tagobj`. Its "to finish it"
     line says that both sibling lines must name the commit. Its push line becomes
     `git push --atomic origin ${commit}:refs/heads/${RELEASE_BRANCH} ${tagobj}:refs/tags/${tag}`.
   - **The callers.** The 15 and 16 calls pass `"$RELEASE_COMMIT" "$TAG_OBJECT"`.
   - **The exit-10 tag-at-HEAD call.** It passes `"$tag_commit" "$NEWEST_OBJ"`. `NEWEST_OBJ`
     is the newest tag's `objectname`, kept beside `NEWEST_REL`.
   - **The exit-10 tag-only line.** It becomes `git push --atomic origin ${NEWEST_OBJ}:refs/tags/${NEWEST_REL}`.
   - **The push itself.** It becomes
     `git push --atomic origin "${RELEASE_COMMIT}:refs/heads/${RELEASE_BRANCH}" "${TAG_OBJECT}:refs/tags/${TAG}" \`.
   - **The exit-17 line.** It prints the same two sha refspecs.
   - **After the "released …" line.** When `refs/heads/main` is no longer `RELEASE_COMMIT`,
     print the `note: main moved during the run; …` line, then exit 0.

   **The rerun after 18.** A rerun after any 18 refuses with 10, because `rel-<t8>` is not on
   origin. Its lines are computed from what HEAD and the tag name at the rerun. If the tag
   still points elsewhere, which is the not-at-HEAD branch, the rerun prints that tag's
   object. This is why the 18 stop prints the `git update-ref` line, and why the header tells
   the operator to run it first. No change to the exit-10 logic beyond the swaps above.

3. **Header (`release.sh`).**
   - **Exit-code table.** Insert the row-18 text from the Tests block (`row18`), exactly,
     after row 16. Change nothing else in the table.
   - **"What it does" push text.** It becomes:
     "both pass and each names the release commit, `git push --atomic origin
     <RC>:refs/heads/main <TAGOBJ>:refs/tags/rel-<t8>`, where <RC> is the release commit
     and <TAGOBJ> the tag object git tag made, both by sha."
   - **New invariant.** After "Pushes where it reads.", add a paragraph headed
     `Pushes exactly what it deployed.` with the two sentences the Tests block asserts.
   - **Recovery section.** Its 15/16 and 17 push lines become
     `git push --atomic origin <RC>:refs/heads/main <TAGOBJ>:refs/tags/rel-<t8>`. Add an `18`
     entry with two cases:
     - stopped right after `git tag`: abandon with `git tag -d rel-<t8>` and
       `git reset --keep <PRE>`;
     - stopped after the deploy or the drift check: run
       `git update-ref refs/tags/rel-<t8> <TAGOBJ>`, then finish or abandon as for 15 and 16.

     Define `<RC>` and `<TAGOBJ>` beside `<PRE>`. Extend the rerun sentence to 14, 15, 16
     or 18, with the update-ref caveat.
   - **No old push text.** `--help` must no longer contain `refs/heads/main:refs/heads/main`.

4. **Selftest (`release-selftest.sh`).** Outside the new section, make exactly the
   `test_swaps` in the Tests block:
   - `SSH_HOOK="$WORK_DIR/ssh-hook"`;
   - the stub ssh runs `$SSH_HOOK` once, inside the deploy, after deploy.sh has resolved its
     ref, and discards the hook's output;
   - `new_case` removes the hook;
   - the two INFRA-021 `has` checks on the printed push line (DRIFT, PUSH) now expect the sha
     form. Their case names do not change.

   The free header comment may name the new token. Add a section titled
   `# EXACT (INFRA-024): …` in the `# ====` banner style, directly before the HYGIENE banner.
   Its cases report under token `INFRA-024/EXACT`, with names that match the Tests block's
   patterns:
   - **normal path.** Exit 0. Origin's main is the release commit. Origin's `rel-<T1_8>` is
     the local tag object. No moved note.
   - **main moved in the deploy window.** The ssh hook runs
     `git -C $C commit --allow-empty`. Expect exit 0. Origin's main is `rel-<T1_8>^{commit}`,
     which is local `main^`. The mid-run commit is absent from origin
     (`cat-file -e` fails there). The note is printed.
   - **tag re-pointed in the deploy window.** The ssh hook saves the tag object, then runs
     `git tag -f -a` to point `rel-<T1_8>` at a `commit-tree` child with the same tree. Expect:
     - exit 18;
     - origin unchanged, and no `push` in the git log;
     - stderr has `drift-check.sh's ref line names`;
     - stdout has the exact `git update-ref` line and the exact sha push line.

     Then:
     - **The rerun.** Expect 10 with nothing touched, and the tag-only push line naming the
       moved object.
     - **The recovery.** After `sleep 1`, run the printed `git update-ref`,
       `scripts/deploy.sh --ref`, `scripts/drift-check.sh --ref` and `git push` lines
       verbatim with `bash -c` in `$C`. Send their output to a file of their own. Expect all
       to exit 0, origin's main to be the release commit, and origin's tag to be the saved
       object.
   - **tag re-pointed before the deploy resolves it.** Commit a wrapper over
     `scripts/deploy.sh` that moves the real script to `deploy-real.sh` and acts only on
     `--ref rel-*`, selected by `EXACT_WRAP=move-before`. Expect:
     - exit 18;
     - stderr has `deploy.sh's deployed line names`;
     - stdout has no `^result ` line, which shows the drift check never ran;
     - origin unchanged.
   - **repeated deployed line.** The same wrapper with `EXACT_WRAP=dup` prints the deployed
     line a second time. Expect exit 18, stderr has
     `deploy.sh's deployed line names no single commit`, and origin unchanged.
   - **tag re-pointed after the drift check.** A wrapper over `drift-check.sh`, with
     `EXACT_WRAP=move-after`. Expect exit 0, origin's `rel-<T1_8>` peels to the release
     commit, and the local tag does not.
   - **tag re-pointed as `git tag` writes it.** A `.git/hooks/reference-transaction` hook in
     `$C`. On `committed`, for `refs/tags/rel-<T1_8>` only, it runs `update-ref` to point the
     tag at `rel-<R8>`'s object. An environment guard stops the hook from recursing. Expect:
     - exit 18;
     - no ssh, and origin unchanged;
     - stderr has `right after git tag`;
     - stdout has `release:   git tag -d rel-<T1_8>` and `release:   git reset --keep <PRE>`.
   - **the exit-17 line run later.** A rejecting `pre-receive` gives exit 17. Then add an empty
     commit on main and re-point the tag at it. Remove the hook and run the printed push line
     verbatim. Expect exit 0, origin's main is the release commit, and origin's tag is the
     object made.

5. **Docs.**
   - **`docs/architecture.md`, Release job paragraph.** After "is the last step." add:
     "It sends the release commit and the tag object, both by sha, so nothing that lands on
     `main` or moves the tag mid-run is carried, and it runs only once the deploy and the
     drift check each report the release commit."
   - **`docs/cer/backlog.md`.** Append a `CER-066` row after `CER-050`, at the end of the
     Do Now table:
     - the finding: the MEDIUM and the LOW above;
     - closed with `**RESOLVED Phase 14-post1 — INFRA-024:** <one clause>`;
     - Source `security-auditor (CP-14-post1)`, date `2026-10-01`, phase `14-post1`.

**Mutations for the reviewer.** The prototype turned each of these red:

| Mutation | Red cases |
| --- | --- |
| Push main by name (`refs/heads/main:…`) | main-moved |
| Push the tag by name | tag re-pointed after the drift check |
| Drop section 3 | the drift-window case, its rerun and its recovery |
| Drop section 2 | the before-deploy case and the repeated-line case |
| Drop the peel check in section 1 | the `git tag` case (it exits 15) |
| `reported_sha` accepts more than one line | the repeated-line case |
| `print_finish_abandon` push by names | INFRA-021/DRIFT and the drift-window case |
| Exit-17 line by names | INFRA-021/PUSH and the exit-17-later case |
| Exit-10 tag-only line by name | the rerun case |
| Drop the moved note | main-moved |

With main's `release.sh`, 11 cases fail. The normal path passes, as it should.

**Ideology.**
- *Assert the invariant.* The checks compare the commit each sibling reports it acted on with
  the release commit. A missing or repeated line fails closed.
- *Name the class.* Only shas are printed, and no path or URL. HYGIENE stays green.

**Length.** Like INFRA-023, this spec runs past the baseline. The exact swaps, the messages
the selftest asserts and the Tests block are load-bearing. Preflight may flag `T1`, `R8`, `C`,
`O`, `SSH_HOOK`, `EXACT_WRAP`, `RC`, `TAGOBJ` and `PRE`. They are selftest, environment and
placeholder names. It does flag `TAG_OBJECT`, `DEPLOYED_SHA`, `CHECKED_SHA`,
`RELEASE_COMMIT`, `SCRATCH`, `IFS` and `BASH_REMATCH`. These are shell variables:
`RELEASE_COMMIT` and `SCRATCH` already exist in `release.sh`, `IFS` and `BASH_REMATCH` are
bash's own, and this story creates the other three.

## Tests

Run from the repo root at the story's tip, as a non-root user. No real host is contacted.
`PRE` is main's HEAD `af62731`, which is INFRA-023 merged plus the INFRA-024 plan commit.

On 2026-10-01 the spec-writer ran the block twice:
- **Against a clone of `PRE`:** it failed at check 1 (no INFRA-024 case), and check 3 failed
  on its first assertion.
- **Against a prototype clone with Instructions 1 to 5 applied:** it printed `docs ok` and
  `ALL-OK`, with the selftest at 99 passed, 0 failed.

No check scans whole `git diff` lines. Check 4 uses `--word-diff`.

```bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PRE=af6273128c7336065b2da7a0aa987d3e453ab93e
[ "$(id -u)" -ne 0 ] || { echo "FAIL: run as a non-root user (PARTIAL needs an unwritable docs/)"; exit 1; }
S=$(mktemp -d); trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "${S:?}"' EXIT

# 1. the selftest is green, and every INFRA-024 case passes
bash scripts/release-selftest.sh > "$S/new.out" 2>&1 || true
tail -1 "$S/new.out" | grep -qE '^release-selftest: [0-9]+ passed, 0 failed$' || { echo "FAIL: release-selftest not green"; exit 1; }
for want in 'normal path \(exit 0\)' 'commit added to main in the deploy window is not pushed' \
  "re-pointed in the deploy window is caught by the drift check's ref line \(exit 18" \
  'rerun after exit 18 refuses as unfinished \(exit 10' 'rerun after exit 18 prints the tag-only push by sha' \
  'printed exit-18 update-ref and finish lines' "re-pointed before the deploy resolves it is caught by the deploy's deployed line \(exit 18" \
  'repeated deployed line is no single commit \(exit 18' 're-pointed after the drift check passed' \
  're-pointed as git tag writes it \(exit 18' 'printed exit-17 push line, run after main and rel-<T1_8> moved'; do
  grep -qE "^PASS: .*${want}[^—]* — INFRA-024/EXACT$" "$S/new.out" || { echo "FAIL: no passing case matching: $want"; exit 1; }
done

# 2. every INFRA-021 and INFRA-023 case that passed at PRE still passes (PRE's own selftest, from an archive)
mkdir "$S/pre"; git archive "$PRE" | tar -x -C "$S/pre"; git -C "$S/pre" init -q
(cd "$S/pre" && bash scripts/release-selftest.sh) > "$S/pre.out" 2>&1 || true
grep -E '^PASS: .* — INFRA-02[13]/' "$S/pre.out" | sort > "$S/pre.pass"
grep -E '^PASS: .* — INFRA-02[13]/' "$S/new.out" | sort > "$S/new.pass"
[ -s "$S/pre.pass" ] || { echo "FAIL: PRE's selftest produced no passes"; exit 1; }
if [ -n "$(comm -23 "$S/pre.pass" "$S/new.pass")" ]; then echo "FAIL: cases lost:"; comm -23 "$S/pre.pass" "$S/new.pass"; exit 1; fi

# 3. code: PRE plus three "# --- 18:" sections and the exact swaps; the selftest: PRE plus
#    the EXACT section and the exact swaps; the exit-code table; the header; docs; backlog
git show "$PRE:scripts/release.sh" > "$S/release.pre"
git show "$PRE:scripts/release-selftest.sh" > "$S/selftest.pre"
bash scripts/release.sh --help > "$S/help"
python3 - "$S/release.pre" "$S/selftest.pre" "$S/help" <<'PY'
import re, sys
norm = lambda s: re.sub(r'\s+', ' ', s)
body = lambda s: s[s.index('\nset -euo pipefail\n'):]
def swapped(text, swaps):
    for old, rep, n in swaps:
        assert text.count(old) == n, ('swap anchor', old[:70])
        text = text.replace(old, rep)
    return text

# release.sh
new = open('scripts/release.sh').read(); pre = open(sys.argv[1]).read()
assert new.count('\n# --- 18: ') == 3, 'exactly three "# --- 18:" sections'
cut = new
for must, follows in (('TAG_OBJECT="$(git rev-parse -q --verify "refs/tags/${TAG}"', '# --- 15: deploy, shown'),
                      ('reported_sha deployed "$SCRATCH/deploy.out"', '# --- 16: the drift check, shown'),
                      ('reported_sha ref "$SCRATCH/drift.out"', '# --- 17: push, only now')):
    a = cut.index('\n# --- 18: ') + 1
    b = cut.index('\n# --- ', a) + 1
    assert cut[b:].startswith(follows), ('an 18 section is not directly before', follows)
    assert must in cut[a:b], ('18 section lacks', must)
    cut = cut[:a] + cut[b:]
code_swaps = [
    ('  local tag="$1" pre="$2"\n  say "to finish it:"\n',
     '  local tag="$1" pre="$2" commit="$3" tagobj="$4"\n'
     '  say "to finish it (deploy.sh\'s deployed line and drift-check.sh\'s ref line must both name ${commit}):"\n', 1),
    ('  say "  git push --atomic origin refs/heads/${RELEASE_BRANCH}:refs/heads/${RELEASE_BRANCH} refs/tags/${tag}:refs/tags/${tag}"\n',
     '  say "  git push --atomic origin ${commit}:refs/heads/${RELEASE_BRANCH} ${tagobj}:refs/tags/${tag}"\n', 1),
    ('NEWEST_REL=""\n', 'NEWEST_REL=""\nNEWEST_OBJ=""\n', 1),
    ('    NEWEST_REL="$name"\n', '    NEWEST_REL="$name"\n    NEWEST_OBJ="$obj"\n', 1),
    ('    print_finish_abandon "$NEWEST_REL" "$head_parent"\n',
     '    print_finish_abandon "$NEWEST_REL" "$head_parent" "$tag_commit" "$NEWEST_OBJ"\n', 1),
    ('    say "  git push --atomic origin refs/tags/${NEWEST_REL}:refs/tags/${NEWEST_REL}"\n',
     '    say "  git push --atomic origin ${NEWEST_OBJ}:refs/tags/${NEWEST_REL}"\n', 1),
    ('  print_finish_abandon "$TAG" "$PRE"\n',
     '  print_finish_abandon "$TAG" "$PRE" "$RELEASE_COMMIT" "$TAG_OBJECT"\n', 2),
    ('git push --atomic origin "refs/heads/${RELEASE_BRANCH}:refs/heads/${RELEASE_BRANCH}" "refs/tags/${TAG}:refs/tags/${TAG}" \\\n',
     'git push --atomic origin "${RELEASE_COMMIT}:refs/heads/${RELEASE_BRANCH}" "${TAG_OBJECT}:refs/tags/${TAG}" \\\n', 1),
    ('  say "  git push --atomic origin refs/heads/${RELEASE_BRANCH}:refs/heads/${RELEASE_BRANCH} refs/tags/${TAG}:refs/tags/${TAG}"\n',
     '  say "  git push --atomic origin ${RELEASE_COMMIT}:refs/heads/${RELEASE_BRANCH} ${TAG_OBJECT}:refs/tags/${TAG}"\n', 1),
    ('say "released ${SLUG}@${T8} as ${TAG}: deployed, drift-checked, and pushed with ${RELEASE_BRANCH}"\nexit 0\n',
     'say "released ${SLUG}@${T8} as ${TAG}: deployed, drift-checked, and pushed with ${RELEASE_BRANCH}"\n'
     'if [ "$(git rev-parse -q --verify "refs/heads/${RELEASE_BRANCH}" 2>/dev/null || true)" != "$RELEASE_COMMIT" ]; then\n'
     '  say "note: ${RELEASE_BRANCH} moved during the run; origin\'s ${RELEASE_BRANCH} is the release commit ${RELEASE_COMMIT}, and what came after it stays local"\n'
     'fi\nexit 0\n', 1),
]
assert body(cut) == swapped(body(pre), code_swaps), 'release.sh code outside the 18 sections differs from PRE plus the swaps'

# the exit-code table: PRE's, plus row 18 after row 16
table = lambda s: s[s.index('\n# Exit codes'):s.index('\n# Invariants')]
row16 = "#   16  drift-check.sh fails (its code is printed)\n"
row18 = ("#   18  the release names another commit (checked after 14, after 15 and after 16 pass, so\n"
         "#       it can precede 15, 16 and 17): right after git tag, rel-<t8> is not an annotated\n"
         "#       tag of the release commit; or deploy.sh's deployed line or drift-check.sh's ref\n"
         "#       line is missing, repeated or names another commit\n")
assert table(pre).count(row16) == 1 and table(new) == table(pre).replace(row16, row16 + row18), 'exit-code table not exact'

# the header, as --help prints it
help_ = norm(open(sys.argv[3]).read())
assert 'refs/heads/main:refs/heads/main' not in help_, 'header still names main as the push source'
assert help_.count('git push --atomic origin <RC>:refs/heads/main <TAGOBJ>:refs/tags/rel-<t8>') >= 3, 'header push lines'
assert 'git update-ref refs/tags/rel-<t8> <TAGOBJ>' in help_, 'header 18 recovery'
inv = help_[help_.index(' Invariants'):]
for s in (" Pushes exactly what it deployed.",
          "The push sends the release commit and the tag object by sha, so a commit that lands on main, or a tag "
          "moved, after the tag is made is pushed neither by this job nor by the recovery line its stop prints.",
          "Before the push, deploy.sh's deployed line and drift-check.sh's ref line must each name the release "
          "commit, or the job stops with 18 and pushes nothing."):
    assert s in inv, s[:50]

# release-selftest.sh
tnew = open('scripts/release-selftest.sh').read(); tpre = open(sys.argv[2]).read()
bar = '# =====================================================================================\n'
a = tnew.index(bar + '# EXACT (INFRA-024)'); b = tnew.index(bar + '# HYGIENE\n')
assert a < b and 'INFRA-024/EXACT' in tnew[a:b], 'EXACT section before HYGIENE'
push_old = '"release:   git push --atomic origin refs/heads/main:refs/heads/main refs/tags/rel-$T1_8:refs/tags/rel-$T1_8"'
push_new = '"release:   git push --atomic origin $(git -C "$C" rev-parse HEAD):refs/heads/main $(git -C "$C" rev-parse "refs/tags/rel-$T1_8"):refs/tags/rel-$T1_8"'
test_swaps = [
    ('SSH_REFUSE="$WORK_DIR/ssh-refuse"\n', 'SSH_REFUSE="$WORK_DIR/ssh-refuse"\nSSH_HOOK="$WORK_DIR/ssh-hook"\n', 1),
    ('echo "invoked" >> "$SSH_MARKER"\n',
     'echo "invoked" >> "$SSH_MARKER"\nif [ -f "$SSH_HOOK" ]; then\n  mv "$SSH_HOOK" "$SSH_HOOK.ran"\n'
     '  bash "$SSH_HOOK.ran" < /dev/null > /dev/null 2>&1\nfi\n', 1),
    ('  rm -f "$CONTROL_DIR"/override-* "$SSH_MARKER" "$SSH_REFUSE"\n',
     '  rm -f "$CONTROL_DIR"/override-* "$SSH_MARKER" "$SSH_REFUSE" "$SSH_HOOK" "$SSH_HOOK.ran"\n', 1),
    ('  && has "$OUT" ' + push_old + ' && has "$OUT" "release:   git tag -d rel-$T1_8" \\\n',
     '  && has "$OUT" ' + push_new + ' && has "$OUT" "release:   git tag -d rel-$T1_8" \\\n', 1),
    ('  && has "$OUT" ' + push_old + '; then ok=0; fi\n', '  && has "$OUT" ' + push_new + '; then ok=0; fi\n', 1),
]
assert body(tnew[:a] + tnew[b:]) == swapped(body(tpre), test_swaps), 'release-selftest.sh outside EXACT differs from PRE plus the swaps'

# docs and backlog
arch = open('docs/architecture.md').read(); i = arch.index('**Release job**')
para = norm(arch[i:arch.index('\n\n', i)])
for s in ('It sends the release commit and the tag object, both by sha,',
          'only once the deploy and the drift check each report the release commit.'):
    assert s in para, 'architecture Release job: ' + s[:40]
bl = open('docs/cer/backlog.md').read()
now = bl[bl.index('\n## Do Now'):bl.index('\n## Do Later')]
row = re.search(r'^\| CER-066 \|.*$', now, re.M)
assert row and '**RESOLVED Phase 14-post1 — INFRA-024:**' in row.group(0), 'CER-066 row in Do Now'
assert len(re.findall(r'^\| CER-066 \|', bl, re.M)) == 1, 'one CER-066 row'
print('docs ok')
PY

# 4. every selftest green; no host, local path or URL in added text (word-diff, not whole lines)
for t in scripts/*-selftest.sh; do bash "$t" > /dev/null 2>&1 || { echo "FAIL: $t"; exit 1; }; done
if git diff --word-diff=porcelain "$PRE" -- scripts/release.sh scripts/release-selftest.sh docs/architecture.md docs/cer/backlog.md \
  | grep -E '^\+[^+]' | grep -nE '/mnt/|/home/|~/|https?://'; then exit 1; fi
echo ALL-OK
```

**Acceptance.**
- The block prints `docs ok` and `ALL-OK`, and every command exits 0.
- The reviewer applies the mutations above.
- The reviewer confirms that the story's diff leaves `deploy.sh`, `drift-check.sh`, the other
  scripts, both bundles and the manifest unchanged.
- INFRA-023's own Tests block is pinned to its `PRE` and asserts the old push text, so it
  fails from here on by design. It is a historical record and is not re-run.

## Out of scope

- **The `pushInsteadOf` gap.** It is stated and ruled (INFRA-023).
- **A tag moved after the drift check passed.** The push still sends `TAG_OBJECT`, and that is
  tested. The local tag then differs from origin's, and the next run refuses with 8. There is
  no extra pre-push re-check of the local ref.
- **A post-commit hook that adds a commit before `RELEASE_COMMIT` is read.** See open
  question 3 in Context. Any change to how `RELEASE_COMMIT` is captured is out of scope.
- **The exit-10 rerun.** It still prints its recovery from what HEAD and the tag name at the
  rerun. It does not remember the original run's shas.
- **No rollback lines on an 18 stop.** The finish and abandon steps both redeploy.
- **No changes to `deploy.sh`, `drift-check.sh` or their output formats.**
