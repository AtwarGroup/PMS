-- Only the guarded RPC can mutate batches and their shared metadata.
revoke all on public.task_batches,public.task_batch_attachments from public,anon,authenticated;
grant select on public.task_batches,public.task_batch_attachments to authenticated;
create index task_batches_created_at_idx on public.task_batches(created_at desc);
