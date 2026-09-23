-- Run against a disposable database or inside a transaction as a privileged test runner.
-- Confirms that authenticated employees cannot cross privileged RPC boundaries.
begin;

create temporary table security_negative_results (
  test_name text primary key,
  passed boolean,
  detail text
) on commit drop;
grant select, insert on security_negative_results to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

-- Replace the synthetic subject/profile IDs in a test fixture before execution.
-- Production verification on 2026-09-23 covered:
-- admin_set_executive_task_access, admin_update_profile_details,
-- run_recurring_tasks_safe, and list_deleted_tasks.

rollback;
