# Remaining approved improvements — 10 October 2026

Strategy linkage is deferred until CEO approval. Verified main at 1ab7e25467d703764ad42d6800b69e21aedaa092: original project baseline (#102), next recurring occurrences (#91) and management governance obligations (#102) already exist and were not rebuilt.

This increment adds literal body search across all project messages with keyset pagination and stale-response isolation, current-version job acknowledgement coverage within active direct-team scope, periodic review dates, durable task attachment deletion intentions with authenticated Storage API cleanup and retry on task-page entry/reconnection, and configurable approval reminders/escalations. Reminders use Riyadh calendar days from submitted_at; each recipient/stage/submission receives one notification. Escalation never grants decision rights and is sent only to an existing authorized reader. Settings begin disabled because business response durations have not been chosen; active admins can configure and enable them in My Workspace. Existing pending approvals will not receive unsolicited reminders from deployment alone.

Cleanup is persisted in the database; retry is driven by authenticated task-page use (not a separate unattended background worker). A requester who never returns may leave a pending cleanup entry. The queue is retained for maintenance; successful cleanup rows remain an audit trail. No global orphan scan or deletion of old files was performed.

Verification: JavaScript regression suite, behavioral tests of query escaping, stale/cancelled responses, history pagination, acknowledgement rendering and cleanup retry. Transactional database tests cover queue isolation, client mutation denial, manager scope, protected global settings, reminder/escalation idempotence, timing and completed-task exclusions. All synthetic database fixtures roll back. Production records were not used as test recipients. Authenticated live visual/file QA and a real backup restoration remain unproven. Existing restore workflow requires a separately configured disposable database.

Deployed database migration version: 20261010193015. Cleanup Edge Function deployed with JWT verification enabled. Private sent-ledger has no authenticated policy by design and is inaccessible to clients; security advisor reports this as informational, not an exposed table.

User approved public GitHub publication on 10 October 2026. Database migration and JWT-protected cleanup service are deployed; frontend publication is in progress.

Live authenticated file acceptance passed: uploaded a synthetic file in an E2E self-created task, created its metadata, called the JWT-protected deletion service, verified row removal and physical Storage object removal, checked the completed queue entry and retried idempotently. The synthetic task was soft-deleted afterward. A second boundary constraint rejects cross-task paths before enqueuing privileged deletion; the Edge service independently enforces the same folder boundary.

Boundary migration remote version: 20261010193355. Frontend changes verified and approved for publication.
