# Acceptance follow-up — 30 October 2026

Reference checked: main `23aa58989848c9c68c56c5560f9360b57a92a909`; local test source `70aae30` (backup tooling additions; application source unchanged by this follow-up).

## Completed
- All six isolated PostgreSQL fleet suites passed: normal and emergency maintenance, SAR300 boundaries, advance/refund/settlement, independent approvals, stale revisions, access revocation, attachment validation/private storage, custody and handover.
- Fleet alert suite passed: document windows, three intended recipient classes, duplicate prevention, inactive users and transfer revocation. Notifications were isolated test records, not external messages.
- Action-history regression passed across eight tables and six account roles. Conflict suite passed for 16 functions, including PT409 and no stale writes.
- Access model, account modules, employee data permission, policy review access, recruitment model and task history display tests passed.
- On hosted staging, an authenticated context for each of the two distinct active non-admin profile roles was denied by public.access_audit_list. Assertions ran in a transaction ending ROLLBACK, with no writes or audit contents returned.
- Read deployed staging recruitment request/offer function definitions. Request approval order matches the October 27 approval: department -> finance -> HR -> CEO -> recruiter; finance rejection goes to CEO exception, HR rejection to development. Offer flow includes HR, requesting department and CEO. This is code inspection, not full live workflow execution.

## Scope and limits
Isolated regressions use synthetic fixtures; they do not certify the currently deployed staging application end to end. Hosted checks above exercise only audit denial. Full authenticated hosted workflow acceptance and physical Android testing remain open. No production mutation, approval change, salary change, password change or external message occurred.

Security advisor returned 42 informational RLS-with-no-policy findings and 32 authenticated SECURITY DEFINER warnings. These require contextual review; they are not automatically proven vulnerabilities and no grants were broadened. See https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

Browser launch initially failed (missing binary; full Chromium process singleton socket prohibited). Downloaded pinned Chromium headless shell as a working alternative. Browser test final outcome is recorded below.

## Final browser outcome
Both fleet browser suites exited 0. Desktop and 320/360/390/412/740px checks passed; maintenance/payment flows, account grant/revoke and activation handling, manager/fleet/accountant boundaries, drawer/keyboard/camera/file upload, handover, recovery and printable views passed. Browser routes blocked external connections. This is Chromium mobile viewport simulation, not physical Android.

Resume: test the current hosted staging application using authorized test accounts, validate current recruitment/IT workflows without real outbound notifications, then complete physical Android acceptance. No new release was needed for these test-only results.
