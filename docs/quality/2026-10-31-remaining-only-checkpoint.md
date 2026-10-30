# Remaining-only checkpoint — 31 October 2026 (Saudi)

## Scope discipline
The completed route sweep, rollback-only recruitment/support workflows, fleet suites, restore/archive/Storage checks and the 56 history role/table combinations were NOT rerun here.
Existing evidence: 2026-10-31-staging-route-matrix.md and preceding dated hosted-interface, hosted-database, owner-admin and recovery reports.
Current staging source remains Sites v48 / 20a5455506391cf1348e512395b554c11e35427d. No new application deployment or production write.

## New security-advisory review
Fresh advisory inventory:
| Finding | Production | Staging | Disposition |
|---|---:|---:|---|
| RLS enabled / no policy | 41 | 42 | Catalog confirmed no effective direct anon/authenticated table/column grants with schema usage. Deliberately closed internal/migration/queue tables; no policy was opened. |
| Authenticated SECURITY DEFINER execution | 33 | 32 | Authenticated execution is intentional for these APIs. Read authorization gates; all have fixed search_path; neither anon nor authenticated can CREATE in public. No anonymous execution grant. |
| Leaked password protection disabled | 1 | 1 | Still open; existing organization is already Pro, so no upgrade was made or needed. Dashboard requires sign-in and connector has no Auth-config mutation tool. |
| Unindexed foreign keys (INFO) | 50 | 53 | Triaged; no index automatically added without a query/plan justification. |
| Unused indexes (INFO) | 125 | 139 | Triaged; no index dropped from a statistics-only observation. |
| Auth absolute connection allocation (INFO) | 1 | 1 | Configuration review remains; no resource or pool change. |

Independent actual-role test: BEGIN READ ONLY / SET LOCAL ROLE anon invoked every warned function with typed NULL arguments. Production: 33 denied; staging: 32 denied; unexpectedly executable=0 in both; transaction_read_only=on. Both tests ended ROLLBACK.
These are new denial tests for the advisory functions, not a rerun of the earlier eight history-table tests.
All 32 staging definitions match their production counterparts. Production additionally has task_approval_pause_days.
Source authorization inventory is not proof of every business branch or every dependent helper; earlier behavioral suites remain complementary evidence.

| Function | Observed gate | Actual anonymous result |
|---|---|---|
| `acknowledge_job_description(uuid,text)` | Active caller + published-job visibility | anon denied |
| `admin_update_profile_details(uuid,text,date,text,text)` | Administrator | anon denied |
| `cancel_task_safe(uuid,text)` | Active manager/admin + creator/assignee/direct-manager scope | anon denied |
| `communication_assignees()` | Module + communication actor + hierarchy + assignable target | anon denied |
| `communication_notification_open(uuid)` | Communication actor + notification recipient + conversation membership | anon denied |
| `communication_status()` | Module + communication actor | anon denied |
| `communication_task_command(text,uuid,text,uuid,date)` | Task/communication modules + actor + conversation membership + task/project visibility | anon denied |
| `communication_trial_notification_open(uuid)` | Trial allowlist + recipient + conversation membership | anon denied |
| `communication_trial_status()` | Module + trial allowlist | anon denied |
| `communication_trial_task_command(text,uuid,text,uuid,date)` | Trial allowlist + conversation membership + task/project visibility + trial target | anon denied |
| `complete_job_description_review(uuid)` | Assigned reviewer + workflow state | anon denied |
| `create_task_batch_safe(uuid,text,uuid[],text,text,date,date,text,jsonb)` | Task module + active administrator + allowed assignees + owned uploaded files | anon denied |
| `create_task_safe(text,uuid,text,text,date,date,text)` | Active actor and assignee + hierarchy/assignment scope | anon denied |
| `decide_task_reschedule(uuid,boolean,text)` | Active caller + task visibility + creator/admin + revision/current schedule | anon denied |
| `delegate_task_safe(uuid,uuid,integer)` | Task/module access + assigned manager/admin + hierarchy + revision/state | anon denied |
| `delete_task_safe(uuid,text)` | Active role + creator ownership/completed restriction or administrator | anon denied |
| `finish_job_final_review(uuid)` | Final-review stage permission + workflow state | anon denied |
| `get_my_manager_profile()` | Active caller's own manager | anon denied |
| `import_tasks_safe(jsonb)` | Active manager/admin + hierarchy/target scope + status restrictions | anon denied |
| `job_stage_directory()` | Job module + named stage permission | anon denied |
| `list_deleted_tasks()` | Task module + administrator filtering | anon denied |
| `record_executive_task_access(text)` | Task module + tasks.read_all | anon denied |
| `request_task_reschedule(uuid,date,date,text)` | Active assignee + task visibility + state + distinct creator | anon denied |
| `resolve_task_date_issue(uuid,date,date,text)` | Task module + administrator | anon denied |
| `restore_task_safe(uuid)` | Task module + administrator | anon denied |
| `return_job_description_for_changes(uuid,integer,text)` | Active caller + assigned reviewer/stage permission + state + revision | anon denied |
| `run_recurring_tasks_safe()` | Task module + active administrator | anon denied |
| `save_task_followup(uuid,boolean,text,text,text,date,integer,integer)` | Active caller + view/edit rights + task and follow-up revisions | anon denied |
| `set_job_stage_owner(text,uuid)` | Job module + administrator + active target | anon denied |
| `task_approval_pause_days(uuid[],text)` | Active caller + module/task visibility or executive permission | anon denied |
| `task_batch_directory()` | Task module + active administrator + allowed targets | anon denied |
| `task_batch_report(uuid)` | Task module + active administrator | anon denied |
| `task_followup_context(uuid)` | Active caller + task visibility; edit capability separately scoped | anon denied |

Remediation references:
- https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys
- https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## New database-read baseline (staging only)
Active existing owner-admin claims under actual authenticated database role, transaction READ ONLY, representative existing data. Server clock timing; 30 sequential samples per operation, warm-cache effects possible. No browser/network/render time or concurrent-user load is included.

| Operation | Samples | P50 ms | P95 ms | Max ms |
|---|---:|---:|---:|---:|
| active_task_projection | 30 | 230.72 | 235.91 | 243.35 |
| task_list | 30 | 238.04 | 246.42 | 247.95 |
| recent_task_history | 30 | 618.12 | 639.97 | 814.84 |

First combined 90-read DO statement reached its 25-second statement deadline while processing history. It was canceled, not recorded as a passing run. The same three operations were then measured separately under the same per-statement deadline; all completed. This distinction prevents a batch deadline from being misreported as an individual-query SLA.
Historical normalized production query statistics identify task_activity and task-list reads as the largest accumulated read costs. Their means/maxima are not P95 and do not certify UI performance.
No index, function, RLS policy or query implementation was changed based on these samples.
End-to-end P50/P95 across representative devices/networks remains open.

## New hosted keyboard acceptance
On the actual v48 IT new-request native dialog:
- Initial focus on closeDialog inside the dialog.
- Shift+Tab boundary and 12 subsequent Tab steps remained inside the dialog.
- Escape closed the dialog and restored focus to createRequest.
- No input data, submit, request save, upload, provider email or test notification.
This closes the representative hosted keyboard check, not a universal accessibility certification of every control.

## Exact remaining dependencies
1. Auth protection configuration: existing Pro plan verified; dashboard redirected to sign-in. Need owner dashboard authentication to inspect/enable leaked-password protection on staging first and validate it. No password or auth setting changed.
2. Physical Android acceptance and representative end-to-end page timings: no physical Android device is exposed to the execution tools. Prior phone drawer evidence and viewport simulations remain complete but narrower evidence. Do not rerun them as a substitute.
3. Production promotion: preserve as a separate gated action after the applicable acceptance is complete. Never promote staging trial/owner auth or blindly copy concurrent IT/recruitment work.
The deployment window ends 2026-10-31 22:00 Asia/Riyadh. No outage or new paid resource was used. No continuous/background job remains.

## Authentication handoff update
Secure browser authentication selected the email/password method and submitted credentials without exposing them to the agent. Supabase then displayed an hCaptcha challenge. Dashboard sign-in is not yet verified and no Auth setting was changed. The challenge requires user completion in the retained cloud-browser tab; do not switch methods or retry credential entry automatically.
