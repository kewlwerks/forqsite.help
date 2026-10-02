---
id: "001"
name: forqsite.help — Initial development
status: active
---

## Strategic intent

Keep forqsite's administrator documentation available and accurate as a zero-dependency
static site that survives a forqsite outage — and track the dev→prod gap backlog
(`gap-handoff.html`) as it gets closed upstream in `nullvalues/forqsite`.

## Rails

| Rail | Primary domain |
|------|----------------|
| CONTENT | `index.html` docs content — builder/self-hoster/reference sections, env-var table, architecture maps |
| INFRA | Hosting, publishing, the generated-artifact re-export workflow, `gap-handoff.html` backlog upkeep |
| TEST | Verifying generated HTML renders correctly (offline/`file://`, static server), link and content accuracy checks |
| API | _(fill in primary domain)_ |
| UI | _(fill in primary domain)_ |
| DB | _(fill in primary domain)_ |
| AUTH | _(fill in primary domain)_ |

## Phases

| Phase | Title | Status |
|-------|-------|--------|
| 1 | Bootstrap pairmode methodology | complete |
| 2 | Refresh docs against forqsite drift | complete |
| 3 | Drift re-sweep vs forqsite source (pairmode 0.3.0 proving cycle) | complete |
| 4 | Containerize for edge deployment | complete |
| 5 | SDK 5.0.0 and the generated-registry ingestion path | complete |
| 6 | Full structural back-check, and a verification stamp | complete |
| 7 | Write for the reader, not about the work | complete |
| 8 | The promotion path, and what a pack may carry | complete |
| 9 | Close CP-8: the defect the checklist missed, and the wiring that predates the convention | complete |
| 10 | Name the class, not the instance — and close the backlog by resolving, never deleting | complete |
| 11 | Make the deploy repeatable, and make drift visible | complete |
| 12 | One stamp per release: re-verify every published claim against one forqsite commit | complete |
| 13 | Release-time reconciliation: revise the brief, then check claims against a new forqsite commit | complete |
| 14 | Release from a forqsite checkpoint tag: harden, restamp, release | complete |
| 15 | Bring the unstamped command blocks under the claims manifest | planned |
| 14-post1 | Release hardening before the second release | planned |
