begin;
-- E2E checks use only existing dedicated test accounts; all generated data rolls back.
do $qa$
declare a uuid;m uuid;e uuid; jid uuid:=gen_random_uuid();rid uuid; req public.employee_job_change_requests%rowtype;before_snapshot jsonb;kpi jsonb;job public.job_descriptions%rowtype; result text;
begin
 select id into a from public.profiles where email='e2e-admin@atwargroup.test' and active=true;
 select id into m from public.profiles where email='e2e-manager@atwargroup.test' and active=true;
 select id into e from public.profiles where email='e2e-employee@atwargroup.test' and active=true;
 if a is null or m is null or e is null then raise exception 'Dedicated QA accounts required';end if;
 begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  kpi:=jsonb_build_object('name','QA indicator','unit','%','measure','QA valid measure','source','QA source','target','95%','weight',100,'frequency','quarterly','scale',jsonb_build_array(jsonb_build_object('score',1,'label','<60'),jsonb_build_object('score',2,'label','60-79'),jsonb_build_object('score',3,'label','80-89'),jsonb_build_object('score',4,'label','90-94'),jsonb_build_object('score',5,'label','>=95')));
  insert into public.job_descriptions(id,job_code,title,family,job_level,purpose,content,reviewer_mode,reviewer_id,reference_profile_id)
  values(jid,'JOB-'||(900000000+floor(random()*99999999)::bigint)::text,'QA structured KPI review','QA','QA','QA purpose with enough detail for the complete job content validation.',jsonb_build_object('responsibilities',jsonb_build_array(jsonb_build_object('text','QA duty')),'authorities',jsonb_build_array(jsonb_build_object('text','QA authority')),'kpis',jsonb_build_array(kpi),'reports',jsonb_build_array(jsonb_build_object('name','QA report')),'qualifications',jsonb_build_object('education','QA education')),'auto',m,e);
  update public.job_descriptions set status='IN_REVIEW' where id=jid;
  update public.job_descriptions set status='MANAGER_APPROVED' where id=jid;
  perform public.finish_job_final_review(jid);
  update public.job_descriptions set status='PUBLISHED' where id=jid;
  insert into public.employee_job_assignments(profile_id,job_description_id,assigned_by) values(e,jid,a) on conflict(profile_id) do update set job_description_id=excluded.job_description_id;
  select published_snapshot into before_snapshot from public.job_descriptions where id=jid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  begin
   perform public.submit_employee_job_change_structured(jid,(before_snapshot->>'revision')::int,'KPIS','MODIFY',0,kpi,'QA unchanged request','',gen_random_uuid());
   raise exception 'QA FAILED: unchanged proposal accepted';
  exception when raise_exception then if sqlerrm not like 'لم يتغير%' then raise;end if;end;
  rid:=public.submit_employee_job_change_structured(jid,(before_snapshot->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"target":"98%"}','QA target-only change','QA related impact',gen_random_uuid());
  select * into req from public.employee_job_change_requests where id=rid;
  if req.manager_id<>m or req.manager_task_id is null then raise exception 'QA FAILED: wrong decision owner';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  begin perform public.review_employee_job_change(rid,req.version,'APPROVE','Admin must not decide');raise exception 'QA FAILED: admin content decision';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
  perform public.review_employee_job_change(rid,req.version,'RETURN','QA incomplete details');
  select * into req from public.employee_job_change_requests where id=rid;
  if req.status<>'NEEDS_CHANGES' then raise exception 'QA FAILED: return status';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  perform public.correct_employee_job_change(rid,req.version,'KPIS','MODIFY',0,kpi||'{"target":"99%"}','QA corrected reason','QA unchanged impact','QA correction note');
  select * into req from public.employee_job_change_requests where id=rid;
  if req.manager_decided_at is not null or req.approval_snapshot is not null or req.status<>'MANAGER_REVIEW' then raise exception 'QA FAILED: correction reused approval';end if;
  if not exists(select 1 from public.employee_job_change_events where request_id=rid and action='أصل الطلب قبل التصحيح') then raise exception 'QA FAILED: original lost';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
  perform public.review_employee_job_change(rid,req.version,'APPROVE','QA approves corrected target');
  select * into req from public.employee_job_change_requests where id=rid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  perform public.review_employee_job_change(rid,req.version,'PREPARE','QA technical preparation');
  select * into job from public.job_descriptions where id=jid;
  if job.status<>'MANAGER_APPROVED' or job.manager_approved_by<>m or job.content#>>'{kpis,0,target}'<>'99%' or job.published_snapshot<>before_snapshot then raise exception 'QA FAILED: approval transfer or published snapshot';end if;
  if exists(select 1 from public.tasks where legacy_metadata#>>'{job_workflow,job_id}'=jid::text and legacy_metadata#>>'{job_workflow,phase}'='ADMIN_APPROVAL' and status<>'مكتملة') then raise exception 'QA FAILED: duplicate preparation task';end if;
  perform public.finish_job_final_review(jid);
  update public.job_descriptions set status='PUBLISHED' where id=jid;
  if (select status from public.employee_job_change_requests where id=rid)<>'PUBLISHED' then raise exception 'QA FAILED: request publication';end if;
  -- Changing a prepared draft after approval must invalidate that coverage.
  select published_snapshot into before_snapshot from public.job_descriptions where id=jid;
  kpi:=before_snapshot#>'{content,kpis,0}';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  rid:=public.submit_employee_job_change_structured(jid,(before_snapshot->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"target":"100%"}','QA second target','',gen_random_uuid());
  select * into req from public.employee_job_change_requests where id=rid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
  perform public.review_employee_job_change(rid,req.version,'APPROVE','QA second approval');
  select * into req from public.employee_job_change_requests where id=rid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  perform public.review_employee_job_change(rid,req.version,'PREPARE','QA second preparation');
  update public.job_descriptions set purpose=purpose||' Extra unrelated edit.' where id=jid;
  if (select status from public.job_descriptions where id=jid)<>'DRAFT' then raise exception 'QA FAILED: unrelated draft kept approval';end if;
  raise exception using errcode='ZX001',message='QA rollback after successful checks';
 exception when sqlstate 'ZX001' then null;end;
 raise notice 'PASS: structured changes, owner-only decision, return, correction audit, exact approval reuse, published protection and unrelated-edit invalidation';
end $qa$;


rollback;
