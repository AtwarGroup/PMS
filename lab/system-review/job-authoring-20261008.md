# Job library authoring and workflow — 2026-10-08

Implemented on top of existing governance, preserving existing 57 jobs, published snapshots and active reviews.

- Dedicated five-step authoring page reuses approved review theme; blank/copy, structured rows, reorder/delete, draft save, resume and submit.
- Automatic code allocation serialized by advisory transaction lock; request UUID deduplicates creation retries.
- Optimistic revision lock on save and proposal decisions.
- Direct manager derived from linked employees, optional reference employee (without assignment), or occupied reporting job; ambiguity blocks submission. Existing reviewer assignments retained as legacy. Only administrator can select an exceptional reviewer with reason.
- Returned jobs create a DRAFT_REVISION task; resubmission closes it and opens a new manager cycle. Existing final review, publish and employee acknowledgement tasks retained.
- Atomic proposal decision locates original JSON value after deletion rather than stale array index.
- Published content persists while drafting a new revision; final content cannot be silently edited after final review.
- My reviews, accurate final-review/publish labels, version comparison/history and per-employee acknowledgement state. Archived jobs cannot be newly assigned.

Validation: 83 JavaScript test groups; authenticated database role lifecycle test in supabase/tests/job_authoring_workflow.sql fully rolled back. Covers create/retry, stale revision, direct manager, denied employee actions, return task ownership, shifted proposal index, final review/publication, published snapshot retention. These database role tests do not claim a real browser password sign-in.

Security advisors: no new RLS table exposure. Intentional signed-in SECURITY DEFINER return RPC checks active user, current stage/assigned reviewer, expected revision and reason. Remaining advisory categories predate this change.

UI preview lab/job-authoring-preview.html uses actual authoring module with synthetic in-memory directory and no production database or saving.

Extended database test: acknowledgement retries return the same record; two subsequent publications leave exactly one pending acknowledgement task for the latest revision. Superseded pending tasks are retired without falsely marking employee acknowledgement complete. Published snapshot read is locked during acknowledgement.
