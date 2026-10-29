# Weekend remediation checkpoint — 29 October 2026

Status: preparation only; no production application changes, maintenance, database changes, notifications or deployment.

Approved plan read in full: Atwar_ONE_Weekend_Remediation_Plan.md (28 October 2026).
Baseline main: 21e6af36044be30861152ee81fbb08a0399f8733 (PR #179). Isolated branch: remediation/weekend-20261029. Existing main changes retained unchanged.
Production https://one.atwargroup.com returned HTTP 200; index redirects to landing.html. This does NOT establish deployed commit identity.

Validation performed locally after npm ci --ignore-scripts:
- node tests/phase-three-quality-gate.mjs: PASS, 19 UI handlers and 9 workflow contracts.
- node tests/phase-four-ux-safety.mjs: PASS, 11 interaction contracts.
- theme-contract.cjs: BLOCKED before page checks. Installed Chromium 1194 aborted with SIGABRT during launch in execution environment. No visual assertions passed. Android physical testing not available or performed.

No complete baseline measurements, database backup/restore validation, route coverage, workflow acceptance or performance comparisons have been completed. Source reference is recorded; it is not a verified operational rollback package.

Resume: restore working Chromium execution or use another supported isolated browser environment; verify actual deployed assets against source; inspect repository instructions and CI gates; inventory all current routes (plan's 50 are preliminary); capture cold/warm timing and role/state coverage with outbound integrations isolated; validate rollback before application changes. Then implement shared components, route coverage, evidence-based performance changes, full acceptance and release gates in approved order. Do not deploy until gates pass. Preserve identity, audit-log authorization, approval cycles, passwords and salary rules. No new costs or real test messages.

Window closes 31 October 2026 22:00 Asia/Riyadh; reserve at least two hours for rollback. This checkpoint does not represent continuous unattended execution or completed remediation.

## Continued execution — 29 October 2026

Production baseline check: index.html, landing.html, assets/js/shell-components.js, assets/css/app-theme.css and assets/js/data-state.mjs were fetched and compared byte-for-byte to 21e6af3; all matched. This verifies those assets, not the identity of every deployed file or database state.

Current source inventory is 51 application HTML routes (new recruitment guide included). Separate generated/lab fixtures account for the broader system audit's 61 HTML files. Route inventory is recorded in 2026-10-29-route-inventory.md; acceptance is still pending, not inferred from inclusion of shared CSS.

Implemented on the isolated branch / draft PR #180:
- Start the canonical theme and typography request while parsing; preserve final cascade order and avoid assigning an unchanged CSS URL again.
- Share accessible loading/error/empty status semantics; ignore duplicate retry activation and recover from rejected callbacks without an unhandled rejection.
- Notifications display loading until the first read settles, including retry; empty results appear only after a successful read.
- Update all existing protected-page shell cache references to 2.8.6 and refresh the shared data-state import cache references. Three existing cache-contract assertions were updated consistently.
- Add isolated browser coverage for safe text, loading/error/empty, duplicate retry prevention and recovery at desktop and 412/390/360 widths. Add a parsing-blocked test for early theme delivery and one canonical CSS request.

Validation actually completed:
- All 137 tests/*.mjs were executed locally: 134 passed initially; three expected-version assertions failed after the cache bump and passed on rerun after updating to the new version.
- Separate system syntax/link audit passed: 61 HTML files and 282 JavaScript modules.
- Local PostgreSQL emulation: fleet database, integrity, operations, review, private storage and feedback suites passed; recruitment database, policy, approved workflow/release and mocked email suites passed. No live business writes or actual emails were used.
- GitHub run 40907311165: system/workflow audit passed; fleet/recruitment database workflow step, fleet browser workflow and notification history recovery passed. Remaining browser/theme steps were still running when this entry was written; final status must be checked before release.

Local Chromium blocker diagnosed: socket() is denied in the execution environment. Reinstallation and restricted launch options did not resolve it. Existing GitHub CI can run Chromium, so browser validation continues there rather than treating local launch as an application failure.

Not completed: comparable cold/warm performance distribution, physical Android test, all per-route dynamic state/role acceptance, verified operational backup/restore and full-system release readiness. No live deployment, maintenance, password, approval, salary, database or integration changes have been made. The next step is to check final browser CI results (including the additional early-theme test), address failures, then continue the approved per-unit state and layout work. Do not treat this initial shared-component package as full completion of the weekend plan.

CI found a real cascade regression in the initial early-load change: typography remained ahead of inline page styles because its previous loader returned when a link existed. Corrected to move the same typography link after module CSS at DOMContentLoaded, without changing its URL. Full browser gates must rerun; the initial failed run is not accepted.

Backup metadata review: weekly-backup run 39883068276 completed successfully on 23 October 2026 (01:16–01:23 UTC). No restore-drill workflow runs were returned by the read-only workflow history request; no successful operational restore is claimed. Both existing Supabase projects (production and staging) reported ACTIVE_HEALTHY; no new branch, project or paid resource was created. Action-history permission tests passed for 8 history tables and 6 account roles; business-conflict tests passed for 16 functions, including stale-write rejection without writes.

Run 40908023961 completed successfully for 7e1b98c after the typography correction: 47 content pages at desktop/mobile, 52 native dialog layouts, 140 shared confirmation/input dialogs, 54 populated/empty library/daily-work/project states, 65 runtime empty/error/filled states, 16 recruitment tabs/dialogs, policy editor and compensation/leave readers. Early-theme test proved the canonical request starts before DOMContentLoaded, loads once and retains typography at desktop/412/390/360 widths. These are explicit isolated scenarios; they do not certify every dynamic state of every route.

Read-only static delivery baseline: 50 successful HTTP requests across five assets, ten attempts per asset; results and scope in 2026-10-29-static-delivery.json. These are execution-host transport timings, not browser navigation/readiness, network conditions representative of a Saudi user, CLS or proof of application improvement.

Staging was resolved to https://test.atwargroup.com, Site version 33. Its published browser configuration points at the existing staging database, with connect-src restricted to that database. Source checkout is being inspected before any update to preserve concurrent feature work. No claim is made yet about isolation of server-side email/schedules, complete data copying or live acceptance.

## Latest verified handoff — 29 October 2026

Application/test commit 1244fcd2f4d08e2341fd27666e7af518c7530750 passed GitHub Quality Gate run 40909393580 and asset verification run 40909393641. This includes the added actual-notification-module slow/failure/retry/empty test. Previous references to that run as pending are superseded.

Staging version 34 deployed successfully, source 0314afcc54e0c7fd660056250b12866d9d368af6, at test.atwargroup.com (Sites returned deployment URL https://atwar-one-staging.mbasunbol.chatgpt.site). Existing staging IT-support/recruitment work and backend behavior were retained by focused patching. Worker build, ESM validation and 56 static HTML routes passed without outbound calls; deployed shell/data-state/config bytes matched local source. Notification module and data-state helper match the tested application package exactly. Version 33 is retained for staging rollback. No production release occurred.

Connected acceptance blocker: automatic approval review rejected the attempted login via the trial selector under a specifically named account, stating that this exact account/impersonation flow was not explicitly authorized in the current transcript. No credential was entered and no alternate account, API session or indirect bypass was attempted. Public login page was inspected only. Explicit authorization for the chosen named trial account is needed before continuing that authenticated browser flow. No passwords are needed or requested.

Next resume: read PR #180's latest status and this checkpoint; verify current main/staging heads for concurrent changes; obtain the missing exact-account authorization, then measure authenticated cold/warm timing and CLS and complete per-route connected role/state/workflow acceptance with external delivery isolated. Complete operational rollback evidence before production release. Do not confuse the successful isolated tests and staged first package with full completion of the approved weekend plan. Production remains at baseline 21e6af3; no maintenance is active from this work.
