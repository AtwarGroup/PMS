begin;

-- The assigned reviewer completes the managerial review through one guarded RPC.
-- Direct client updates remain restricted to the system administrator.
create or replace function public.complete_job_description_review(p_job_id uuid)
returns public.job_descriptions
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_job public.job_descriptions%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;

  select * into v_job
  from public.job_descriptions
  where id=p_job_id
  for update;

  if not found then raise exception 'Job description not found'; end if;
  if v_job.reviewer_id is distinct from v_uid then
    raise exception 'Only the assigned reviewer may complete this review' using errcode='42501';
  end if;
  if v_job.status not in ('IN_REVIEW','CHANGES_REQUESTED') then
    raise exception 'This job description is not open for review';
  end if;

  update public.job_descriptions
  set status='MANAGER_APPROVED', updated_by=v_uid,
      manager_approved_by=v_uid, manager_approved_at=now()
  where id=p_job_id
  returning * into v_job;

  insert into public.job_description_comments(job_description_id,author_id,body)
  values(p_job_id,v_uid,'اكتملت مراجعة المدير وتم إرسال الوصف إلى مدير النظام للمراجعة والاعتماد');

  insert into public.notifications(recipient_id,type,title,message,created_at)
  select p.id,'JOB_REVIEW_READY','وصف وظيفي بانتظار اعتمادك',
    v_job.title||' — اكتملت مراجعة المدير وأصبح جاهزًا للاعتماد',now()
  from public.profiles p
  where p.role='admin' and p.active=true and p.status='active';

  return v_job;
end $$;

revoke all on function public.complete_job_description_review(uuid) from public,anon,authenticated;
grant execute on function public.complete_job_description_review(uuid) to authenticated;

create or replace function private.notify_job_assignment()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
declare v_title text; v_published boolean;
begin
  if tg_op='UPDATE' and old.job_description_id=new.job_description_id then return new; end if;
  select title,(published_at is not null) into v_title,v_published
  from public.job_descriptions where id=new.job_description_id;
  insert into public.notifications(recipient_id,type,title,message,created_at)
  values(
    new.profile_id,'JOB_DESCRIPTION_ASSIGNED','تم ربط وصفك الوظيفي',
    v_title||case when v_published then ' — يمكنك الاطلاع عليه الآن من ملفك الوظيفي' else ' — سيظهر في ملفك الوظيفي بعد اعتماده ونشره' end,
    now()
  );
  return new;
end $$;

revoke all on function private.notify_job_assignment() from public,anon,authenticated;
drop trigger if exists employee_job_assignment_notify on public.employee_job_assignments;
create trigger employee_job_assignment_notify
after insert or update of job_description_id on public.employee_job_assignments
for each row execute function private.notify_job_assignment();

create or replace function private.notify_job_publication()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
begin
  if old.status is distinct from 'PUBLISHED' and new.status='PUBLISHED' then
    insert into public.notifications(recipient_id,type,title,message,created_at)
    select a.profile_id,'JOB_DESCRIPTION_ASSIGNED','تم اعتماد ونشر وصفك الوظيفي',
      new.title||' — افتحه الآن من ملفك الوظيفي للاطلاع والإقرار',now()
    from public.employee_job_assignments a
    where a.job_description_id=new.id;
  end if;
  return new;
end $$;

revoke all on function private.notify_job_publication() from public,anon,authenticated;
drop trigger if exists job_description_publish_notify on public.job_descriptions;
create trigger job_description_publish_notify
after update of status on public.job_descriptions
for each row execute function private.notify_job_publication();

commit;
