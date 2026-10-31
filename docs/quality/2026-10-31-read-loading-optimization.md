# Task and workspace read optimization — 31 October 2026

## Baseline and acceptance boundary

The owner supplied a complete production Android cohort at 14:07 UTC (17:07 Saudi), before this optimization: 90 successful samples, zero interruptions. Numeric source evidence is `2026-10-31-android-before-read-optimization.json`.

| Page | P50 ms | P95 ms | Max ms |
| --- | ---: | ---: | ---: |
| Home | 2594.9 | 3875.3 | 3885.4 |
| Tasks | 6371.9 | 14647.2 | 14658.8 |
| Workspace | 3639.8 | 8496.9 | 11130.6 |

This is single-session sequential iframe readiness timing with natural cache behavior, 30 samples per route after one excluded warm-up. It is not a multi-user load SLA or proof of complete rasterization. No after-optimization physical Android cohort is available at this checkpoint. A speed rating of 10/10 or numerical production-speed closure is not claimed.

## Change

PR https://github.com/AtwarGroup/PMS/pull/188 removes independent sequential read dependencies:

- Start completed-task counts alongside task loading. The readiness marker still waits for both initial counts and successful task data/rendering; errors cannot be converted to ready.
- Read participant names alongside task children. Fetch shared batch attachments alongside other child tables.
- Allow at most two concurrent 100-ID batches per related-read family and approval-pause RPC family. Preserve original input order, deduplication, all rows/pages, caller RLS and error rejection. Other callers retain serial default behavior. This is a per-family bound, not a global two-connection cap.
- Start workspace job-acknowledgement and approval-settings reads alongside the main reads. Readiness still waits for these panels, with existing role guards and the settings edit guard.
- Increment page/module URL versions, including the bridge version asserted by atomic-save and delegation tests.

There is no schema migration, index change, new cache of user data, authorization-policy change, audit exposure, business write, salary/approval-cycle change, password change or new paid resource. Ordinary notification behavior is retained; hosted verification used the existing `performance_probe=1` guard on tasks.

## Verification

- All 141 JavaScript regression files passed locally. New tests execute actual loading functions with deferred reads, checking overlap, two-batch limits, 100-ID boundaries, result ordering, failure propagation, role guards and readiness waits.
- Existing real-bridge network/reconnect/conflict tests, private shared attachments, atomic task/subtask save, delegation, dashboard pagination, overdue/approval counters and workspace filtering passed.
- Artificial-transport comparison: 30 paired runs, 167 IDs, 100-ID chunks, simulated 25ms request delay. Serial P50/P95 50.62/50.99ms; two-batch P50/P95 25.38/26.06ms. This only demonstrates the scheduler improvement under the fixture, not page or production-device speed.
- Authenticated stage RLS read returned 167 active tasks. Read-only authenticated production check of the unchanged private approval-pause function returned 100 authorized summaries. Both transactions rolled back.
- Staging v55, source e2366c460153164a05cee13d4a18ea4a03ed911f, built, validated and deployed successfully. Stage retains its existing bridge variant without production's private pause-summary RPC; stage and production timing equivalence is not claimed.
- A post-change cloud timing attempt stopped on unchanged Home after 23 successful samples with one `paint-timeout`. It never measured Tasks or Workspace and is not accepted as an after-speed cohort. Its raw export was not retained after navigating to direct functional checks.
- Direct authenticated stage verification: 167 tasks loaded with the readiness marker complete; representative details showed two subtasks and nine audit entries to the admin. Workspace reached its full updated status, tracking displayed, and both acknowledgement/settings hosts had content without error. No save or notification action was invoked.

## Publication

- Required checks all passed on candidate 2d2573bdaea0f2860721b757f50cda26c86807fb: quality run 41211535628; generated assets run 41211535725. Initial failure was two exact old bridge-version assertions; these were updated to the new required version without weakening save or delegation checks.
- Squash merge 7981703788a9b433c1cc18e590aba88c917def39; tree 6b739a41f2d471da1ef38f87129b87b4e9d5c453 exactly equals the tested candidate tree.
- Pages run 41212437252 and postmerge generated-assets run 41212437706 succeeded.
- Actual production HTTP 200 responses matched tested-source SHA-256 for tasks/index.html, workspace/index.html, tasks-page.js, supabase-firebase-compat.js, paged-related-read.mjs and workspace-page.mjs, using their new module URLs where applicable.
- Automatic postmerge quality run 41212437686 completed successfully. Required premerge checks, postmerge quality, generated-assets verification and Pages publication are all green. Authenticated production browser UI was not re-tested; no new credential request was made.

## Continuation and rollback

The code improvement and tested-source publication are complete. To close numerical mobile-speed acceptance, obtain one after-update report from the same actual Android device/session/network and compare each route with the baseline above. Do not reuse the old report or present the synthetic batch gain as whole-page speed. Further tuning depends on that evidence.

Reverting PR 188 restores the prior read scheduling and module versions. No database rollback or downtime is required. Preserve completed functional, recovery and permission evidence from the earlier remediation rather than repeating it.
