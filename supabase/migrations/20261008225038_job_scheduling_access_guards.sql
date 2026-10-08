begin;
alter policy job_schedule_read on public.job_publication_schedules using(private.current_user_is_active() and (
 private.can_job_stage('DRAFT') or private.can_job_stage('FINAL_REVIEW') or private.can_job_stage('PUBLISH') or private.can_job_stage('ASSIGN')
 or exists(select 1 from public.job_descriptions j where j.id=job_description_id and j.reviewer_id=auth.uid())));
alter policy job_periodic_read on public.job_periodic_reviews using(private.current_user_is_active() and (
 private.can_job_stage('DRAFT') or private.can_job_stage('FINAL_REVIEW') or private.can_job_stage('PUBLISH')
 or exists(select 1 from public.job_descriptions j where j.id=job_description_id and j.reviewer_id=auth.uid())));
alter policy job_periodic_events_read on public.job_periodic_review_events using(private.current_user_is_active() and (
 private.can_job_stage('DRAFT') or private.can_job_stage('FINAL_REVIEW') or private.can_job_stage('PUBLISH')
 or exists(select 1 from public.job_descriptions j where j.id=job_description_id and j.reviewer_id=auth.uid())));
create function private.guard_job_periodic_reviewer() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if not exists(select 1 from public.job_descriptions j join public.profiles p on p.id=new.reviewer_id where j.id=new.job_description_id and p.active=true and p.status='active'
 and (p.role='admin' or p.id=j.reviewer_id or exists(select 1 from public.job_stage_owners o where o.profile_id=p.id and o.stage in ('DRAFT','FINAL_REVIEW','PUBLISH')))) then
  raise exception 'مسؤول المراجعة يجب أن يكون مراجع الوصف أو صاحب صلاحية في دورة الأوصاف بحساب نشط';
 end if;return new;
end $$;
create trigger guard_job_periodic_reviewer before insert or update of reviewer_id on public.job_periodic_reviews for each row execute function private.guard_job_periodic_reviewer();
revoke all on function private.guard_job_periodic_reviewer() from public,anon,authenticated;
-- A newly linked employee acknowledges the current published snapshot, including while a future revision waits.
do $$ declare d text;begin
 select pg_get_functiondef('private.sync_job_assignment_workflow_task()'::regprocedure) into d;
 if position('v_job.status=''PUBLISHED''' in d)=0 then raise exception 'Assignment function changed';end if;
 d:=replace(d,'v_job.status=''PUBLISHED''','v_job.status<>''ARCHIVED''');execute d;
 select pg_get_functiondef('private.queue_job_publication_email(public.job_descriptions,uuid)'::regprocedure) into d;
 if position('p_job.status<>''PUBLISHED''' in d)=0 then raise exception 'Publication queue function changed';end if;
 d:=replace(d,'p_job.status<>''PUBLISHED''','p_job.status=''ARCHIVED''');execute d;
end $$;
commit;
