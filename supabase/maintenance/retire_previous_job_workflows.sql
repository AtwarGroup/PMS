-- Repair pre-existing stale requests after installing automatic assignment archival.
-- The active binding and published description content remain unchanged.
begin;
do $$
declare a uuid;r record;p text;j public.job_descriptions%rowtype;claims text:=current_setting('request.jwt.claims',true);before_bindings text;before_sources text;
begin
 a:=private.job_stage_owner('ASSIGN');
 if not exists(select 1 from public.profiles where id=a and role='admin' and active and status='active') then raise exception 'Active assignment administrator required';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 select md5(string_agg(jsonb_build_array(profile_id,job_description_id,effective_from)::text,'|' order by profile_id)) into before_bindings from public.employee_job_assignments x;
 select md5(string_agg(jsonb_build_array(id,title,purpose,content,published_snapshot)::text,'|' order by id)) into before_sources from public.job_descriptions;
 for r in select distinct c.requester_id,c.job_description_id,coalesce(x.job_description_id,e.job_description_id) as current_job
  from public.employee_job_change_requests c join public.profiles e on e.id=c.requester_id left join public.employee_job_assignments x on x.profile_id=e.id
  where c.status<>'ARCHIVED' and c.job_description_id is distinct from coalesce(x.job_description_id,e.job_description_id)
 loop
  if exists(select 1 from public.employee_job_assignments where profile_id=r.requester_id) then
   update public.employee_job_assignments set job_description_id=r.current_job where profile_id=r.requester_id;
  else perform private.archive_previous_employee_job(r.requester_id,r.job_description_id,r.current_job,'أرشفة الطلب السابق بعد تغيير الربط الوظيفي؛ لا يمتد اعتماده إلى الوصف الحالي.');end if;
 end loop;
 -- Explicit user instruction: cancel the old Operations & التشغيل Supervisor approval.
 for j in select * from public.job_descriptions where title='مشرف العمليات والتشغيل' and status in ('IN_REVIEW','CHANGES_REQUESTED','MANAGER_APPROVED') for update loop
  if not exists(select 1 from public.job_description_versions where job_description_id=j.id and revision=j.revision) then
   insert into public.job_description_versions(job_description_id,job_code,revision,action,snapshot,actor_id,change_note) values(j.id,j.job_code,j.revision,'UPDATED',to_jsonb(j),a,'حفظ المراجعة القديمة قبل إلغاء طلب الموافقة.');
  end if;
  update public.job_description_change_requests set status='ARCHIVED',archived_at=now(),archive_snapshot=to_jsonb(job_description_change_requests) where job_description_id=j.id and status<>'ARCHIVED';
  update public.job_publication_schedules set status='CANCELLED',cancelled_by=a,note='إلغاء طلب الموافقة القديم بناءً على توجيه الإدارة.' where job_description_id=j.id and status in ('PENDING','BLOCKED');
  update public.job_descriptions set status='DRAFT',submitted_at=null,manager_approved_at=null,manager_approved_by=null,final_reviewed_at=null,final_reviewed_by=null,review_note='أُلغيت المراجعة القديمة بناءً على توجيه الإدارة؛ يلزم بدء مراجعة جديدة عند تجهيز الوصف الحالي.' where id=j.id;
 end loop;
 if before_bindings is distinct from(select md5(string_agg(jsonb_build_array(profile_id,job_description_id,effective_from)::text,'|' order by profile_id)) from public.employee_job_assignments x) then raise exception 'Unexpected binding change';end if;
 if before_sources is distinct from(select md5(string_agg(jsonb_build_array(id,title,purpose,content,published_snapshot)::text,'|' order by id)) from public.job_descriptions) then raise exception 'Unexpected content change';end if;
 perform set_config('request.jwt.claims',coalesce(claims,''),true);
end $$;
commit;
