# Improvement proposals release — 2026-10-08

Employees submit opportunities from My Workspace or a source task. Active system administrators study proposals, record a reason, accept with priority, defer or mark unsuitable, and reopen study when circumstances change. Accepted proposals convert once to a task or project through existing engines. Employee notifications and a proposal history cover decisions, conversion, and execution status changes, including cancellation/deletion.

RLS limits employees to their own proposals and admins to review. Proposal ownership grants an execution summary but no additional task/project access. Direct writes are revoked. Revision checks prevent stale decisions; client keys and row locks prevent duplicate submissions/conversions. Proposal strategic priority is independent of normal task urgency.

Validation: 79 root test files, real-script browser fixtures at desktop/mobile sizes, and rolled-back SQL tests under authenticated RLS covering isolation, disabled accounts, stale revisions, required priority, retries, task/project conversion, deferral/reopening, cancellation summary, history and execution notifications. No production fixtures remain. No interactive real-account login was performed in this release.

Security advisor returned no improvement-specific notices. Existing unrelated advisor findings were not changed by this feature.
