-- Rebuild consent tasks through an internal trigger so workflow guards stay enabled.
-- This creates no acknowledgements and sends no acknowledgement emails.
create temporary table job_ack_backfill_run (run boolean) on commit drop;
create function pg_temp.restore_job_ack_tasks() returns trigger language plpgsql as $$
declare item record;
begin
 for item in
  select j as job,p.id as recipient,
   coalesce(nullif(j.published_snapshot->>'revision',''),j.revision::text) as cycle
  from public.employee_job_assignments a
  join public.profiles p on p.id=a.profile_id and p.active and p.status='active'
  join public.job_descriptions j on j.id=a.job_description_id
  where j.status<>'ARCHIVED' and j.published_at is not null and j.published_snapshot is not null
 loop
  perform private.ensure_job_workflow_task(item.job,'EMPLOYEE_ACK',item.cycle,item.recipient);
 end loop;
 return new;
end $$;
create trigger restore_job_ack_tasks after insert on job_ack_backfill_run
for each row execute function pg_temp.restore_job_ack_tasks();
insert into job_ack_backfill_run values(true);
