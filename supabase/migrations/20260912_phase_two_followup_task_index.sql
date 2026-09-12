begin;

-- Covers the nullable foreign key for task delete/update checks.
create index if not exists follow_ups_task_id_idx
  on public.follow_ups(task_id)
  where task_id is not null;

commit;
