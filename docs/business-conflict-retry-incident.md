# Business conflict retry incident — 2026-10-26

## Cause and correction

Production logs contained about 8.6 million `ATWAR_CONFLICT: task changed; reload follow-up` errors over 24 hours, around 100 per second. Two PostgREST 14.5 connections repeatedly executed `save_task_followup`. A business revision check raised SQLSTATE `40001`, which PostgREST 14 treats as a transient serialization error and retries indefinitely.

Reference: https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b

Migration `20261026100805_business_conflict_http409.sql` changes explicit application assignments of `40001` to `PT409` in public/private functions. Production inspection found 30 affected functions across tasks, projects, job descriptions, KPI, accounts, HR, fleet and recruitment. These checks all represent business revision/state conflicts. Genuine database serialization errors are unaffected. Function signatures, messages, guards, ownership and grants remain intact. Existing migrations are not rewritten.

The client already displays the task conflict message without retrying or discarding the draft. No frontend deployment is needed for the fix. New business conflicts must use `PT409`, never synthetic `40001`.

## Validation and operations

- Applied to staging, then production after staging validation.
- Real task follow-up transaction tests passed on both environments: initial save, valid subsequent save, stale task/follow-up conflict, invalid input, unauthorized read/write and direct-write denial. Test rows rolled back.
- Isolated PostgreSQL regression covers 16 real task/fleet/HR/account functions, definition equivalence except the intended SQLSTATE, stable ownership/ACLs, migration replay, no writes on stale revisions and valid saves.
- Production logs showed both formerly looping connections return one `PT409` at 10:09:40 UTC and stop. No matching active backend remained, so termination/restart was unnecessary.
- CPU percentage itself is not inferred from SQL execution time or project health; verify host CPU separately in Supabase Reports. The unrelated Management API incident does not establish the cause of this application loop.
