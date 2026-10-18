begin;
do $qa$
declare a uuid;m uuid;e uuid;old_job uuid:=gen_random_uuid();new_job uuid:=gen_random_uuid();jid uuid;kpi jsonb;snap jsonb;rid uuid;new_rid uuid;req public.employee_job_change_requests%rowtype;v integer;
begin
 select id into a from public.profiles where email='e2e-admin@atwargroup.test' and active;
 select id into m from public.profiles where email='e2e-manager@atwargroup.test' and active;
 select id into e from public.profiles where email='e2e-employee@atwargroup.test' and active;
 if a is null or m is null or e is null then raise exception 'QA accounts required';end if;
 begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  kpi:=jsonb_build_object('name','QA lifecycle KPI','measure','QA formula','unit','%','target','95%','source','QA source','frequency','monthly','weight',100,'scale',(select jsonb_agg(jsonb_build_object('score',i,'label','QA '||i)) from generate_series(1,5) i));
  foreach jid in array array[old_job,new_job] loop
   insert into public.job_descriptions(id,job_code,title,family,job_level,purpose,content,reviewer_mode,reviewer_id,reference_profile_id)
   values(jid,'JOB-'||(900000000+floor(random()*99999999)::bigint)::text,'QA lifecycle assignment','QA','QA','QA purpose with enough detail to pass the complete description validation.',jsonb_build_object('responsibilities',jsonb_build_array(jsonb_build_object('text','QA responsibility')),'authorities',jsonb_build_array(jsonb_build_object('text','QA authority')),'kpis',jsonb_build_array(kpi),'reports',jsonb_build_array(jsonb_build_object('name','QA report')),'qualifications',jsonb_build_object('education','QA education')),'auto',m,e);
   update public.job_descriptions set status='IN_REVIEW' where id=jid;
   update public.job_descriptions set status='MANAGER_APPROVED' where id=jid;
   perform public.finish_job_final_review(jid);
   update public.job_descriptions set status='PUBLISHED' where id=jid;
  end loop;
  insert into public.employee_job_assignments(profile_id,job_description_id,assigned_by) values(e,old_job,a) on conflict(profile_id) do update set job_description_id=excluded.job_description_id;
  select published_snapshot into snap from public.job_descriptions where id=old_job;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  rid:=public.submit_employee_job_change_structured(old_job,(snap->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"target":"97%"}','QA lifecycle proposal','',gen_random_uuid());
  select version into v from public.employee_job_change_requests where id=rid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
  perform public.review_employee_job_change(rid,v,'APPROVE','QA approval before reassignment');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  update public.job_descriptions set status='IN_REVIEW' where id=old_job;
  update public.employee_job_assignments set job_description_id=new_job where profile_id=e;
  select * into req from public.employee_job_change_requests where id=rid;
  if req.status<>'ARCHIVED' or req.archive_snapshot->>'status'<>'ADMIN_REVIEW' or req.approval_snapshot is not null or req.manager_decided_at is not null or req.replaced_by_job_id<>new_job then raise exception 'QA FAILED: old approval not archived';end if;
  if (select status from public.job_descriptions where id=old_job)<>'DRAFT' then raise exception 'QA FAILED: old manager review still active';end if;
  if exists(select 1 from public.tasks where deleted_at is null and status<>'مكتملة' and legacy_metadata#>>'{job_workflow,job_id}'=old_job::text) then raise exception 'QA FAILED: old workflow task still active';end if;
  if not exists(select 1 from public.tasks where deleted_at is null and status<>'مكتملة' and legacy_metadata#>>'{job_workflow,job_id}'=new_job::text and legacy_metadata#>>'{job_workflow,phase}'='EMPLOYEE_ACK' and assignee_id=e) then raise exception 'QA FAILED: new acknowledgement missing';end if;
  if (select published_snapshot from public.job_descriptions where id=old_job)<>snap then raise exception 'QA FAILED: published source changed';end if;
  begin
   update public.employee_job_change_requests set status='MANAGER_REVIEW' where id=rid;
   raise exception 'QA FAILED: archived request reopened';
  exception when raise_exception or insufficient_privilege then if sqlerrm like 'QA FAILED:%' then raise;end if;end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  begin
   perform public.submit_employee_job_change_structured(old_job,(snap->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"target":"99%"}','QA old role should fail','',gen_random_uuid());
   raise exception 'QA FAILED: request on old binding accepted';
  exception when raise_exception or insufficient_privilege then if sqlerrm like 'QA FAILED:%' then raise;end if;end;
  select published_snapshot into snap from public.job_descriptions where id=new_job;
  new_rid:=public.submit_employee_job_change_structured(new_job,(snap->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"target":"99%"}','QA current role remains active','',gen_random_uuid());
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  update public.employee_job_assignments set job_description_id=new_job where profile_id=e;
  if (select status from public.employee_job_change_requests where id=new_rid)<>'MANAGER_REVIEW' then raise exception 'QA FAILED: same binding archived a current request';end if;
  -- A shared previous job keeps another employee acknowledgement and its content.
  insert into public.employee_job_assignments(profile_id,job_description_id,assigned_by) values(m,new_job,a) on conflict(profile_id) do update set job_description_id=excluded.job_description_id;
  update public.employee_job_assignments set job_description_id=old_job where profile_id=e;
  if (select status from public.job_descriptions where id=new_job)<>'PUBLISHED' then raise exception 'QA FAILED: shared description changed';end if;
  if not exists(select 1 from public.tasks where deleted_at is null and status<>'مكتملة' and assignee_id=m and legacy_metadata#>>'{job_workflow,job_id}'=new_job::text and legacy_metadata#>>'{job_workflow,phase}'='EMPLOYEE_ACK') then raise exception 'QA FAILED: another employee acknowledgement cancelled';end if;
  raise exception 'QA_ROLLBACK_ASSIGNMENT_LIFECYCLE';
 exception when raise_exception then if sqlerrm<>'QA_ROLLBACK_ASSIGNMENT_LIFECYCLE' then raise;end if;end;
 if exists(select 1 from public.job_descriptions where id in(old_job,new_job)) then raise exception 'QA cleanup failed';end if;
end $qa$;
rollback;
