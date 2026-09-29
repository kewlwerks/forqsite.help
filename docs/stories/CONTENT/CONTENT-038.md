---
id: CONTENT-038
rail: CONTENT
title: Revise the brief: release-time reconciliation in scope, no-build-step scoped to the published artifact
status: draft
phase: "13"
story_class: doc
auth_gated: false
schema_introduces: false
primary_files:
  - docs/brief.md
touches:
  - docs/ideology.md
  - README.md
narrative_roles: []
---

## Context

The operator wants forqsite.help released automatically, in step with forqsite (phase-12.md
§ After this phase). Two passages in `docs/brief.md` stand in the way. The out-of-scope list
excludes "real-time sync" with `nullvalues/forqsite`, and the brief bans "no build step"
without saying whose step. On 2026-09-28 the operator ruled on both. First, the docs are
reconciled with forqsite **at release time**: forqsite's commits are walked from the new
release back to the pinned release commit, any claim whose evidence moved is updated, and
the result is released. The pages are never live-coupled to forqsite. Second, "no build step"
governs the **published artifact and its reader**. Checking, restamping and deploying run
before publication and are allowed, provided reading the docs never requires them. This
story records that ruling in the brief. It also aligns two passages that restate it: the
self-containment value in `docs/ideology.md` and the auto-sync plan in `README.md` § Updating
(operator decision, 2026-09-28). It also makes the brief's new claim, that the pages
fetch nothing at runtime, a checked fact: the orchestrator found the CDN URLs in both
bundles are only ids in the bundler's `__bundler/ext_resources` map, pointing at inlined
copies, and the Tests block below proves that at load time.

## Requires

- Phase 12 complete (cp-12 tagged). `docs/brief.md` at the merge base is the 88-line brief
  whose passages sit at lines 26-27, 49 and 60-61. `docs/ideology.md`'s belief sits at
  lines 73-74 and `README.md`'s sentence at lines 45-46. The line windows in Tests depend on
  these positions.
- `chromium` on PATH (already relied on for `--dump-dom` renders, `docs/architecture.md`
  § Editing procedure).

## Ensures

`docs/brief.md` differs from the merge base only in its core belief (lines 26-27), its
first constraint (line 49) plus a dated ruling note after the Constraints list, and its
real-time-sync out-of-scope item (lines 60-61). `docs/ideology.md` differs only in its
self-containment value (lines 73-74), and `README.md` only in § Updating's sync sentence
(lines 45-46). Each uses the text given in Instructions, and no other file changes. The unchanged `index.html` and `gap-handoff.html` each render from
`file://` without making a page-initiated network request. Forbidden proxy: a grep showing
no `https://` in the templates, taken as proof on its own (the runtime carries unpkg
fallbacks that only a load-time check can rule out).

## Instructions

Edit `docs/brief.md`, `docs/ideology.md` and `README.md` only, and only at the passages
below. Use the text verbatim, except for line wrapping, which may change. Keep everything
else in the three files byte-identical.

1. **Core beliefs, lines 26-27.** Replace
   `- Self-containment over convenience — no build step, no external assets, even though it makes hand-editing harder.`
   with:
   ```
   - Self-containment over convenience — the published pages need no build step to read and
     fetch nothing when opened, even though that makes hand-editing harder.
   ```
2. **Constraints, line 49.** Replace
   `- No server, no database, no build step for anything published under this repo.` with:
   ```
   - The published artifact is plain, self-contained HTML: it opens from any filesystem, needs
     no server, database or build step to read, and fetches nothing at runtime. Tooling that
     checks, restamps or deploys the pages runs before publication, and reading them must
     never require it.
   ```
   Leave the second constraint (not a forqsite tenant) as it is.
3. **Dated ruling note.** The brief has no revisions section. Follow the project's precedent
   of recording a ruling inline where a reader meets it (ideology.md's "Phase 2 exception
   (recorded …)", CER-002). After the Constraints list and before its `---`, add a blank
   line and then:
   ```
   _Revised 2026-09-28 by operator ruling (CONTENT-038): "no build step" governs the published
   pages and their reader, not the tooling that prepares a release, and release-time
   reconciliation with forqsite replaced the exclusion of real-time sync. In the operator's
   words, the release "is already plain html that could run from a usb disk if copied."_
   ```
4. **Not in scope, lines 60-61.** Replace the `Real-time sync of gap-handoff.html …` item
   with:
   ```
   - Live coupling to `nullvalues/forqsite`. The pages are reconciled with it at release time
     instead: forqsite's commits are walked from the new release back to the pinned release
     commit, every claim whose evidence moved is updated, and the result is released.
   ```

5. **`docs/ideology.md` § Value hierarchy, lines 73-74.** Replace
   `- "Self-containment over convenience — no build step, even though it makes hand-editing harder, because the whole point is that this site depends on nothing external to run."`
   with the text below. The reason clause is kept, and so are the quoted-entry form and the
   voice of the neighbouring "Availability over freshness" entry.
   ```
   - "Self-containment over convenience — the published pages need no build step to read and
     fetch nothing when opened, even though that makes hand-editing harder, because the whole
     point is that this site depends on nothing external to run. Tooling that checks, restamps
     or deploys the pages may run before publication; reading them never needs it."
   ```
6. **`README.md` § Updating, lines 45-46.** Keep line 44 ("These files were originally
   generated by a Claude design session against the forqsite"). Replace
   `repo. Nothing keeps them in sync automatically since that session; a follow-up skill to auto-sync these docs on each forqsite commit is planned but does not exist yet.`
   with the text below. It describes only what exists (the manifest) and what Phase 13 plans
   (the checker), and promises no automation beyond that.
   ```
   repo. They are not synced with forqsite live. They are reconciled at each docs release
   instead: every claim is checked against the new forqsite commit by walking its history back
   to the release commit the pages are pinned to, and claims whose evidence moved are updated
   before the release. `docs/claims-manifest.json` lists those claims. The checker that walks
   the history is being built in Phase 13 and does not exist yet.
   ```

The core belief on line 25 ("Docs must survive infra failure…") and § What a second
implementation must preserve stay unchanged. They already describe the artifact, and the
revision keeps them true.

**Other restatements were checked, and none change.** Each one names the artifact or its
runtime, so none contradicts the revised brief. `docs/ideology.md:37` gives its reason as
when "a forqsite instance is down". Line 103 is scoped to "`index.html` or
`gap-handoff.html`", and line 284 to "Zero runtime dependencies". `docs/architecture.md:6-7`
and `:20-22` describe the content as having no compile step, which stays true.
`docs/reconstruction.md` mirrors ideology's conviction and constraint but not its value
hierarchy. `README.md:13` is about the artifact ("It is plain, self-contained HTML…").

Ideology alignment (Step 4a): "Zero runtime dependencies" (no override permitted) is
narrowed nowhere. The revision makes the brief match that constraint's own scope, the two
bundles.

## Tests

Run from the story worktree, where `main` is the branch this story merges into. It takes
about 30 s (three headless renders). This block is longer than a doc story usually carries,
because the runtime claim can only be checked by loading the pages and needs a negative
control. It was run against a simulated edit of all three files, where every check passes,
and on `main`, where scope, all three hunks checks and every wording line fail. Each check was also shown to fail when its own condition was
broken.

```bash
set -u; cd "$(git rev-parse --show-toplevel)"; T=$(mktemp -d); fail=0
MB=$(git merge-base HEAD main); ok(){ echo "PASS $1"; }; no(){ echo "FAIL $1"; fail=1; }

# 1. Scope: outside story/phase bookkeeping, exactly these three files changed.
[ "$(git diff --name-only "$MB" -- . ':!docs/stories' ':!docs/phases' | tr '\n' ' ')" = "README.md docs/brief.md docs/ideology.md " ] \
  && ok scope || no "scope: $(git diff --name-only "$MB" -- . ':!docs/stories' ':!docs/phases' | tr '\n' ' ')"

# 2. Every hunk sits in a named passage (old-side line windows at the merge base), and every
#    window has one. brief: belief 26-27, constraint 49 + note, out-of-scope 60-61;
#    ideology: value hierarchy 73-74; README: § Updating 45-46.
hunks(){ git diff -U0 "$MB" -- "$1" | python3 -c '
import json,re,sys
W=json.loads(sys.argv[1]); hit=set(); bad=[]
for a,b in re.findall(r"^@@ -(\d+)(?:,(\d+))? ", sys.stdin.read(), re.M):
    lo=int(a); hi=lo+max(int(b if b else 1),1)-1
    w=[k for k,(x,y) in W.items() if x<=lo and hi<=y]
    (hit.update(w) if w else bad.append((lo,hi)))
print("  ",sys.argv[2],"outside windows:",bad,"| missing:",sorted(set(W)-hit)); sys.exit(1 if bad or set(W)-hit else 0)' "$2" "$1"; }
hunks docs/brief.md '{"belief":[25,28],"constraint":[48,53],"out-of-scope":[59,62]}' && ok hunks-brief || no hunks-brief
hunks docs/ideology.md '{"value-hierarchy":[72,75]}' && ok hunks-ideology || no hunks-ideology
hunks README.md '{"updating":[44,47]}' && ok hunks-readme || no hunks-readme

# 3. Old wording gone, new wording present, per file (whitespace-normalised, CER-011; every
#    "new" phrase is absent from its file at the merge base, so this fails on main).
python3 - <<'EOF' && ok wording || no wording
import re,sys
rd=lambda p: re.sub(r"\s+"," ",open(p).read())
b,i,r=rd("docs/brief.md"),rd("docs/ideology.md"),rd("README.md")
sec=lambda s,h: s.split("## "+h,1)[1].split(" ## ",1)[0]
c=[("brief: old out-of-scope line gone","Real-time sync of `gap-handoff.html`" not in b),
   ("brief: old constraint gone","no build step for anything published under this repo" not in b),
   ("brief: constraint names published artifact","published artifact" in sec(b,"Constraints")),
   ("brief: constraint says fetches nothing","fetches nothing" in sec(b,"Constraints")),
   ("brief: dated note","Revised 2026-09-28" in b and "CONTENT-038" in b),
   ("ideology: old belief gone","Self-containment over convenience — no build step, even though" not in i),
   ("ideology: new belief, reason kept",all(p in sec(i,"Value hierarchy") for p in
      ("need no build step to read","fetch nothing when opened","depends on nothing external to run","before publication"))),
   ("readme: old auto-sync plan gone","auto-sync these docs on each forqsite commit" not in r),
   ("readme: release-time reconciliation",all(p in sec(r,"Updating") for p in
      ("reconciled at each docs release","walking its history back","being built in Phase 13")))]
[print(" ", "ok " if v else "BAD", n) for n,v in c]; sys.exit(0 if all(v for _,v in c) else 1)
EOF

# 4. Pages untouched, and their templates reference nothing over http(s).
git diff --quiet "$MB" -- index.html gap-handoff.html && ok pages-unchanged || no pages-unchanged
for b in index gap-handoff; do
  python3 scripts/bundle-template.py extract $b.html $T/$b.t.html >/dev/null
  if grep -Eiq '<(script|link|img|iframe|source)\b[^>]*\b(src|href)\s*=\s*["'"'"']?\s*(https?:)?//|fetch\(|@import|url\(\s*["'"'"']?\s*(https?:)?//' $T/$b.t.html
  then no "static-$b"; else ok "static-$b"; fi
done

# 5. Runtime: opened from file:// with a net log, neither page issues a page-initiated
#    network request, and each actually renders (#dc-root present, loader gone, scripts stripped
#    first per CER-012). A negative control with the bundler's ext_resources map emptied must
#    trip the check (it falls back to the unpkg CDN), proving the check can fail.
python3 - $T index.html > /dev/null <<'EOF'
import re,sys
s=open(sys.argv[2],encoding="utf-8").read()
open(sys.argv[1]+"/neg.html","w",encoding="utf-8").write(re.sub(r'(<script type="__bundler/ext_resources">).*?(</script>)',r"\1[]\2",s,flags=re.S))
EOF
cat > $T/net.py <<'EOF'
import json,re,sys
d=json.load(open(sys.argv[1])); et={v:k for k,v in d["constants"]["logEventTypes"].items()}
jobs=[e["params"] for e in d["events"] if et.get(e["type"])=="URL_REQUEST_START_JOB" and isinstance(e.get("params"),dict)]
page=sorted({p["url"] for p in jobs if p.get("initiator")!="not an origin" and p["url"].split(":")[0] in ("http","https","ws","wss")})
dom=re.sub(r"<(script|style)\b.*?</\1>","",open(sys.argv[2]).read(),flags=re.S|re.I)
rendered='id="dc-root"' in dom and "__bundler_loading" not in dom
print("  page-initiated requests:",page,"| rendered:",rendered); sys.exit(0 if rendered and not page else 1)
EOF
run(){ rm -rf $T/p $T/n.json; timeout 90 chromium --headless=new --disable-gpu --no-first-run \
  --disable-background-networking --disable-component-update --disable-sync --no-pings \
  --user-data-dir=$T/p --log-net-log=$T/n.json --virtual-time-budget=8000 --dump-dom "file://$1" \
  > $T/dom.html 2>/dev/null; python3 $T/net.py $T/n.json $T/dom.html; }
for b in index gap-handoff; do run "$PWD/$b.html" && ok "runtime-$b" || no "runtime-$b"; done
run "$T/neg.html" && no "negative-control-not-caught" || ok "negative-control-caught"

rm -rf $T; [ $fail = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
```

Acceptance: `ALL PASS`, exit 0.

How check 5 works: Chromium's own background requests carry the initiator `not an origin`,
while a request from a `file://` page carries `null`, so the filter counts only what the page
itself asked for. The negative control has to show two `unpkg.com` URLs and fail. If it
passes instead, the check cannot fail, and the result means nothing.

`spec-preflight` gives one warning, "'CONTENT' referenced … no definition found". It is a
false positive: CONTENT is the rail name, not a constant. It also gives one `scope:`
finding for `docs/claims-manifest.json`. That is intentional: the path is only mentioned
inside the new README text, and the manifest is not edited.

## Out of scope

- Any other passage of `docs/ideology.md` or `README.md`, and any edit to
  `docs/architecture.md` or `docs/reconstruction.md`, which were checked above. In
  particular, `README.md:76`'s "Until that exists, periodic refresh passes…" paragraph and
  the "should be re-synced" paragraph after it stay as they are. The stale-claim checker
  story will revisit § Updating when the tool exists.
- Any change to `index.html`, `gap-handoff.html`, `docs/claims-manifest.json` or `scripts/`.
  In particular, the runtime's unpkg fallback code stays in the bundles. It is inert because
  the ext_resources map resolves every CDN id, and check 5 proves that. It is not removed.
- Building the stale-claim checker, a release job or CI (the later Phase 13 stories and
  Phase 14), and the manifest work in CER-045 and CER-046.
