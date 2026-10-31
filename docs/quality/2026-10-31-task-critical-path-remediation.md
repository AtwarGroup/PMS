# Task loading critical-path remediation — 31 October 2026

## Scope and publication gate

Candidate PR: https://github.com/AtwarGroup/PMS/pull/189
Candidate: bb945c46852c220ee01d338c943080f52cd691a7
Candidate tree: 58fa4387498b793a438ff82ec6804a5ec993af14
Production baseline / rollback source: 7981703788a9b433c1cc18e590aba88c917def39 (PR 188).
Release is gated on all required checks and staging UI verification. No maintenance outage is needed. The authorized window ends 2026-10-31 19:00 UTC / 22:00 Saudi.

## Implemented changes

- Main task lists defer action-history reads until an administrator opens a task. Detail and transaction reads retain the full history. The new loader pages all rows, coalesces requests, supports retry, and discards stale identity responses. It uses no persistent cache.
- All task records, subtasks, attachments, and private approval-pause aggregates remain available. Private audit access is not broadened. Delay calculations continue to use the guarded private summary RPC.
- Render only the active list or Kanban view. Completed archives retain list rendering; keyboard/selection scrolling supports Kanban cards.
- Home directory count loads concurrently with dashboard data.
- Existing daily-work preview receives explicit Kanban state to match the updated renderer.

## Verification performed

- 143 JavaScript test files passed locally on the implementation, including new full-pagination, authorization, identity change, retry, concurrency, and active-view rendering cases.
- The daily-work preview was corrected after CI caught a missing fixture variable; it and the other preview generators then completed locally.
- Staging v56: authenticated Home counters and 167 active tasks loaded; a representative task retained two subtasks and nine administrator history events loaded on opening details.
- Staging v57 source 6542fbfcb90cc74125819e5681004f59f235eb33 deployed successfully at 17:43 UTC. Auth initialization initially stalled without an application console error; a single reload recovered. Subsequent verified ready state: 167 tasks; Kanban had zero hidden list cards; List had 167 cards and an empty board. Details still showed two subtasks and nine history events, including expanded history. The completed archive showed all 204 tasks in List with an empty board. Home showed unchanged counters: 204 completed, 167 active, 97 overdue, 36 approvals, and 147 employees.
- No business saves, actual notification sends, password changes, salary changes, approval-cycle changes, or new paid resources were used.

## Staging database parity

Applied the existing production migration 20261027160323_task_delay_private_summary.sql only to the isolated staging project eeaedzisysjarwvolbwq as task_delay_private_summary_stage_parity. Production schema was unchanged. The exact existing function requires an authenticated active account, enforces task/module/project guards, limits each request to 100 IDs, returns aggregate paused days only, fixes search_path, and denies PUBLIC/anon execution. An authenticated stage read of 100 summaries succeeded. Catalog checks confirmed anon/public execute false. The intentionally authenticated SECURITY DEFINER advisor finding remains reviewed; do not interpret this as all advisors being clean.

## Physical Android evidence and limits

The user's latest supplied live report, created 2026-10-31T16:56:57.345Z, contains 90 successful samples, zero failures, and no interruptions. P50/P95 milliseconds: Home 2699.2/4871.4; Tasks 5372.7/12223.7; Workspace 2614.3/3660.6. These are BEFORE this PR. They show that zero errors did not establish acceptable task performance.

This remediation removes unnecessary list-history reads (a read-only production scope check found 732 visible history rows) and duplicate hidden rendering. Unit, CI, and staging functional evidence cannot establish new physical Android P95. No new phone benchmark was requested in this step. Do not claim 10/10, an achieved whole-device SLA, or an independently verified physical-device improvement from these implementation checks.

## Release and rollback

Pending final CI, merge, Pages deployment and public-byte verification. If any required check fails or staged behavior regresses, do not publish. After release, revert PR 189 to the baseline content rather than resetting main, preserving concurrent work. Staging parity migration is additive and does not require a production rollback.
