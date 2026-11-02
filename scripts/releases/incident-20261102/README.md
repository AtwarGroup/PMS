# Live incident: latency, acknowledgement mail, communication transport

## Evidence

- Function gateway logs show communication OPTIONS/POST 502/503 bursts around 2026-11-02 11:00 UTC (14:00 Riyadh). The visible English transport error can occur before the request reaches the application. This change provides bounded recovery; it cannot guarantee upstream availability.
- The reported acknowledgement email belongs to a newly accepted revision 10 at 10:56 UTC on November 2. The previous acknowledgement was revision 9 on October 4. Comparing snapshots showed title and department changes, with responsibilities, authorities and KPIs preserved. The old acknowledgement was not resent or reset. Mandatory acknowledgement rules remain unchanged.
- A production administrator task-catalogue EXPLAIN returned 434 rows in 361.383 ms before the policy optimization. A rollback-only trial returned the same 434 rows in 2.530 ms. This is a database-query measurement, not a full-page load claim.

## Changes

Cache account/module identity checks once per statement; use the existing row's owner/assignee/delegator fields before the unchanged manager fallback. Retain active-account, deleted-record, module and project boundaries. A transactional visibility test compares exact visible task-ID arrays across role/status/module/read-all combinations before and after both policy alterations.

Communication preflights can be cached for 600 seconds. File/history/single-message reads call their existing authorized RPC directly. Independent caller-RLS catalogues run concurrently; old linked task lookups are deduplicated and batched in groups of at most 100. No caller query is replaced with a service-role task query.

The browser retries only safe reads and explicitly idempotent writes; a retried message keeps the original client ID and attachment payload. A single total deadline aborts the actual request. Toggles are never replayed automatically, authorization failures remain failures, and terminal transport errors are in Arabic. Hidden tabs stop background requests, and global alerts stop reclaiming already-handled unread notifications.

Acknowledgement mail subjects and headings include the revision. Provider idempotency keys protect initial sends and explicitly requested corrected-PDF retries. No acceptance timestamps, snapshots, existing emails or passwords are changed. No live test messages or acknowledgement emails were sent by this release.

## Validation

Rollback-only exact visibility comparisons on staging and production, administrator query plan before/trial/after deployment, communication transport/edge/background tests, existing attachment/startup/bfcache/production/work-link/navigation/acknowledgement tests, and the JavaScript regression suite. The only initial regression failure was the existing shared-shell version contract; the communication page retains that canonical shell tag, while its own app entrypoint is cache-versioned.

Backend migration and Edge Functions are deployed to staging and production under the user's existing live-fix authorization. Frontend publication follows the protected GitHub checks. Upstream 502/503 failures remain observable and must not be reported as permanently eliminated.
