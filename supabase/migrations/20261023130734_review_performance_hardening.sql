-- Selective indexes for directory filters, conversation/file reads and reviewer queues.
create index if not exists hr_employees_department_idx on private.hr_employees(department_id);
create index if not exists hr_employees_section_department_idx on private.hr_employees(section_id,department_id);
create index if not exists hr_employees_title_idx on private.hr_employees(title_id);
create index if not exists communication_files_conversation_idx on private.communication_files(conversation_id);
create index if not exists communication_notifications_conversation_idx on private.communication_notifications(conversation_id);
create index if not exists job_periodic_reviews_reviewer_idx on public.job_periodic_reviews(reviewer_id);
create index if not exists fleet_documents_driver_idx on private.fleet_documents(authorized_driver_id);
create index if not exists job_stage_owners_profile_idx on public.job_stage_owners(profile_id);

-- Keep every existing predicate and policy mode; only cache the statement-constant UID.
do $$declare p record;begin
 for p in select schemaname,tablename,policyname,qual from pg_policies
 where schemaname='public' and policyname in('job_schedule_read','task_reschedule_select_policy','job_periodic_read','job_periodic_events_read','module_boundary')
 and tablename in('job_publication_schedules','task_reschedule_requests','job_periodic_reviews','job_periodic_review_events','employee_job_assignments') and qual like '%auth.uid()%'
 loop execute format('alter policy %I on %I.%I using (%s)',p.policyname,p.schemaname,p.tablename,replace(p.qual,'auth.uid()','(select auth.uid())'));end loop;
end$$;

alter table private.job_workflow_tasks enable row level security;
revoke all on function private.can_read_task_batch(uuid),private.protect_task_batch_link() from public,anon;
grant execute on function private.can_read_task_batch(uuid) to authenticated;
