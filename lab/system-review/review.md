# ATWAR ONE system review — 7 October 2026

## Scope and evidence

Reviewed 34 nonredirect HTML pages at desktop (1440×1000) and mobile (390×844), including internal pages, communication, sign-in, guides and templates. The first pass is a static layout review with application scripts disabled and the normal shell rendered; it does not prove real login or populated business states. Five alias/redirect routes lead to existing canonical pages.

A second pass runs the real frontend scripts on 23 internal pages using a mocked authenticated Supabase client and fixtures for active, approval, completed and cancelled tasks. It exercises initial populated or legitimate empty states at both widths. All 46 views finished without uncaught JavaScript errors, hidden bodies or page-level horizontal overflow. Intentional internal scrolling, such as Kanban and tables, remains supported. Some pages, including the job review and published description, render their legitimate unavailable/unlinked state because the fixture has no published job. This is not a claim that every editor or role-specific business path was visually tested.

The shared theme is already applied across the standard shell pages. Communication keeps its approved conversation layout and canonical palette. No wholesale theme replacement was needed. Rescheduling now uses a single accessible native dialog with two date pickers on one row and a reason field, rather than three consecutive text prompts. The browser test covers invalid dates, successful submission, mobile alignment and Escape cancellation. Admin accounts now reuse the standard Supabase runtime rather than a duplicated loader and unused external ESM import.

## Corrected findings

1. Executive overdue counts previously included late submissions awaiting approval and cancelled tasks. They now include only pending/in-progress tasks. The execution counter is labelled “متبقية للتنفيذ”; cancelled tasks are excluded from completion-rate denominators.
2. The home monthly completion counter could include cancelled tasks. It now counts completed tasks only, and its scope label distinguishes admin all-time totals from other roles' monthly totals. Deleted tasks are excluded explicitly. Manager dashboard totals remain within their task/team/creator/delegator scope even when executive read-all permission is granted.
3. Home approval counts previously treated any direct report's approval task as the manager's decision, regardless of its commissioner. Home and workspace now share commissioner, self-task direct-manager, project-approver and self-approval exclusion rules.
4. A disabled task creator could reject a reschedule request. A live rollback regression reproduced this before the fix, then passed after active-account authorization was added to request and decision RPCs and the request SELECT policy.
5. Requests could remain pending after task cancellation, delegation/reclaim, schedule changes, or submission for approval. A task trigger now cancels invalidated requests, preserving history and creating an in-app notification. Decisions lock the task before the request and verify current assignee, creator, dates and editable state. Two pre-existing invalid pending requests were closed; the stale-request audit now returns zero.
6. Cancellation mode could stay enabled for later statements in the same transaction. The cancellation RPC now restores the prior setting.
7. Reschedule controls now show an existing pending request to the assignee, prevent duplicate submission, ignore an outdated task-panel response after selection changes, and refresh task data after the decision.

## Validation

- Full root JavaScript regression suite passed, including new exception-counter and approval-scope tests.
- `regression.sql` reproduces the disabled-creator issue and verifies denial after the fix.
- `exceptions.sql` runs inside BEGIN/ROLLBACK against the live database. It verifies delegation and stale-revision replay without duplicate activity, reclaim clears delegation metadata, employee scope after reclaim, employee delegation/approval/cancellation denial, dates remain unchanged before approval, accepted dates match the approved request, second decisions are denied, reassignment/cancellation/approval invalidates old requests, and cancellation mode does not leak.
- Fixtures, task rows, notifications and temporary profile changes from those test transactions were rolled back. The two obsolete production requests are the intentional persisted repair, separate from tests.
- Supabase security advisors were checked. The guarded authenticated SECURITY DEFINER RPCs remain intentional; active-account and scope checks are enforced in the functions and tested.
- No password login, real end-user session walkthrough, real Storage file download, concurrency load test or long-duration stability test is claimed by this review.

## Reproduction

Run root tests normally. Browser scripts require Playwright in `CODEX_PRIMARY_RUNTIME_NODE_MODULES` and the documented local Chromium fixture; screenshots and machine-readable results are intermediate files under `/tmp/atwar-review-screens`.

- `node lab/system-review/screens.mjs`
- `node lab/system-review/populated-ui.mjs`
- `node lab/system-review/reschedule-ui.mjs`
- Execute the two SQL tests through the authorized database connector; keep their final ROLLBACK.
