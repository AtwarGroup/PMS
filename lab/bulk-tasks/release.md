# Bulk task assignment — 2026-10-07

Active system admins can create a separate normal task for each selected active, assignable employee. The directory supports a department, all available employees, and individual selection. Single task creation remains the existing workflow. Up to 250 recipients and five 10 MB attachments are supported per batch.

The batch RPC validates all recipients and uploads before creating tasks in one transaction through `create_task_safe`. A request UUID, canonical payload comparison, transaction advisory lock, and a unique batch/assignee index prevent retries from duplicating tasks. A changed payload using an existing request UUID is rejected. Shared uploads are immutable from individual task controls; completion attachments remain independent.

Batch reports show the most recent 50 batches. Remaining and overdue count only nondeleted pending/in-progress tasks. Approval, completed, cancelled, and deleted tasks have separate counters. Overdue uses the Riyadh calendar date. Task links use the existing detail screen and completed archive.

Authorization is checked against active database profiles. Manager and employee callers are denied the creation/directory/report RPCs. Shared metadata and private Storage objects require access to a nondeleted task in the batch; the active admin uploader can also read their own uploaded objects for orphan cleanup. Client code uses the normal publishable Supabase client and user session.

Validation:
- All root `tests/*.mjs` passed; existing cache-version assertions advanced alongside the task imports.
- New batch summary and attachment tests cover approval exclusions, signed-url bucket selection, deletion blocking, hydration scope, and failed shared reads.
- `verify.sql` ran in a rolled-back live database transaction: atomic creation, duplicate recipient normalization, idempotent replay, changed-payload rejection, invalid recipient rollback, active manager/employee denial, independent approval workflow, actual authenticated RLS reads, outsider denial, deletion denial, notifications, and approval exclusion from overdue. Fixture rows and notifications were rolled back.
- Browser harness with mocked Supabase responses passed department selection, escaped names, a committed request with a lost response and identical retry, one attachment upload, summary counts, mobile overflow/date alignment, and auth-switch cleanup.
- Production end-to-end interaction with real login and actual Storage file bytes was not performed. The browser scenario uses mocks; database policies and task workflow were exercised against the live database in a transaction.
- Security advisors list the guarded authenticated SECURITY DEFINER RPCs; this is intentional and covered by caller-role tests. No new table lacks RLS.
