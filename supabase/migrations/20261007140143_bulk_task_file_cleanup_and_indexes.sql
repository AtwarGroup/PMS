-- Own uploads must be visible to the uploader for Storage API orphan cleanup.
drop policy task_batch_download on storage.objects;
create policy task_batch_download on storage.objects for select to authenticated using(
 bucket_id='task-batch-attachments' and (
  (private.is_admin() and (storage.foldername(name))[1]=auth.uid()::text)
  or exists(select 1 from public.task_batch_attachments a where a.storage_path=name and private.can_read_task_batch(a.batch_id))
 )
);
create index task_batch_attachments_batch_id_idx on public.task_batch_attachments(batch_id);
create index task_batch_attachments_uploader_idx on public.task_batch_attachments(uploader_id);
create index task_batches_creator_idx on public.task_batches(creator_id);
