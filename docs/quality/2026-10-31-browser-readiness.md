# Browser page readiness measurement — 31 October 2026

## Completed cohort

- Staging URL: https://atwar-one-staging.mbasunbol.chatgpt.site/lab/performance.html
- Measured Sites version: 49; source 82b4dc7c8cf8eb7879ab7bcdfdf1503fdb6d8947.
- Started 12:29:38.743 UTC, 31 October 2026. Completed around 12:40 UTC.
- Authenticated staging owner-admin session; 1363 × 936 parent viewport, visible same-origin iframe (1100px wide, 540px high in this build).
- 30 successful samples per page, one successful excluded warm-up per route; 90 measured successes, zero sample failures.
- Raw numerical evidence: `2026-10-31-browser-readiness-staging.json`. Recomputed independently from downloaded JSON using nearest-rank percentiles.

| Page | Samples | P50 ms | P95 ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| Home | 30 | 4330 | 5346.4 | 6363.5 |
| Tasks | 30 | 7380.3 | 9673 | 9945.7 |
| Workspace | 30 | 5346.4 | 6362.9 | 7376.9 |

## Method and limits

The parent page's monotonic browser clock measures from assigning the iframe navigation URL to observing successful data readiness, followed by two animation frames. Readiness checks run every requested 40ms; scheduler delays remain part of the reported measurement. Readiness means the home summary finished without unavailable data, tasks rendered their initial successful subscription with the shell visible, or workspace reported fully updated. A login, partial error, timeout, hidden document, cancellation or resized viewport cannot be accepted as a successful cohort.

These are cloud-desktop, staging, single-user, sequential **instrumented upper-bound timings**, not production Android timings, a top-level navigation benchmark, proof of complete rasterization, backend-only latency, or concurrent load capacity. The observed clustering near one-second intervals indicates substantial scheduler/observation granularity in this environment; it is not sufficient evidence to assign that entire delay to SQL or the production application. All rendering and readiness detection delays are included. No cross-environment speed comparison or production SLA is established.

Version 49's raw JSON says “warm-cache”; this is an imprecise label. No cache clearing or cache retention was forced, and the staging Worker serves `Cache-Control: no-store`. The correct method is sequential navigation with **natural cache behavior and one excluded warm-up**. Subsequent diagnostic source corrects the label and records iframe dimensions explicitly.

An initial attempt had no staging application session and ended during warm-up with timeout; it produced no accepted samples. The owner's existing trusted staging login restored the admin session without a new credential request. The successful cohort above is the subsequent independent run.

## Safety and publication

No business forms were submitted. No external email, SMS or notification test was sent. The task overdue-notification generator returns immediately only for `performance_probe=1`; ordinary pages retain their behavior. Data access uses the current session's existing RLS scope. The report contains timing/state data and viewport/cohort metadata, with no record IDs, names, tokens or business payloads. It is only downloaded on explicit interaction; no telemetry endpoint or browser persistence is used.

The production candidate is isolated in PR https://github.com/AtwarGroup/PMS/pull/186. Initial premerge testing caught that the new diagnostic lacked the canonical shared theme; fixed by adding the approved theme and Tajawal typography. It has not been merged or deployed at this checkpoint. Normal quality checks must pass on the final candidate before merge. Do not bypass the required theme check or copy the staging application over production.

## Continuation

1. Verify final PR checks, then merge only the isolated diagnostic and task instrumentation changes; verify Pages publication.
2. Run the production diagnostic using an existing authenticated session. A real Android cohort must run on the actual Android device and be explicitly labeled as such; cloud evidence cannot substitute for it.
3. Use representative production evidence to set a target and investigate bottlenecks. This completed staging cohort is not a 10/10 acceptance claim.
4. Rollback: revert the isolated PR (no schema migration, business writes, credential changes or outage are involved). Stage rollback version 48 predates this diagnostic; version 49 retains the measured implementation.
