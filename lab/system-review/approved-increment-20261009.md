# Approved review increment — 9 October 2026

The owner approved implementation of the review and reconfirmed self-created tasks close without approval. That workflow remains unchanged.

Implemented:
- Project Gantt late indicators use the Saudi-local calendar day and only pending/in-progress, nondeleted tasks. Completed, cancelled and awaiting-approval tasks are excluded.
- Workspace combines actionable requests and workflow/task reviews in one ordering: overdue workflow reviews, existing priority, oldest recorded date, stable ID. Existing request/task deduplication and authorization remain. Show approval waiting age from submitted_at; execution deadlines do not become invented approval deadlines. Policy age is labelled time since last update.
- Projects, task collections, project phases/dependencies/risks/files, policy collections/history/comments, job descriptions, assignments, acknowledgements, publication schedules and periodic-review configurations use paginated reads with stable keys. Later-page errors reject incomplete collections; no RLS changes.
- Updated module cache versions.

Validation: all 90 JavaScript groups passed, including Saudi-midnight and cancellation cases, inbox waiting age and priorities, authority/deduplication, 1,203-row pagination and later-page failure, and project refresh preserving dirty editors. Production read-only metadata confirmed every newly selected field and pagination key exists. git diff --check passed. No live browser acceptance or actual backup restoration is claimed by this increment.

Outstanding approved review work: real role-based acceptance for projects/chat/attachments, actual backup restore into a disposable target, load-driven database optimization, older chat/history paging, inbox filters and subsequent product refinements. Do not describe this increment as completing the full roadmap or live system certification. The previous workspace reconnect repair is in PR #94, merged separately after its quality gate passed.
