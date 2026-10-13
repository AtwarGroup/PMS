begin;
alter table public.employee_job_change_requests add column related_request_ids uuid[] not null default '{}';
create function private.link_employee_job_changes(p_ids uuid[],p_note text) returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare ids uuid[];owners uuid[];r public.employee_job_change_requests%rowtype;
begin
 if not private.current_user_is_active() or not private.is_admin() then raise exception 'تصحيح الربط لمسؤول النظام فقط' using errcode='42501';end if;
 if char_length(btrim(coalesce(p_note,''))) not between 2 and 2000 then raise exception 'سبب الربط مطلوب';end if;
 select array_agg(distinct id order by id) into ids from (select unnest(p_ids) id union select unnest(related_request_ids) from public.employee_job_change_requests where id=any(p_ids)) s;
 if coalesce(cardinality(ids),0)<2 or cardinality(ids)>10 then raise exception 'اختر من طلبين إلى عشرة طلبات';end if;
 perform id from public.employee_job_change_requests where id=any(ids) order by id for update;
 if (select count(*) from public.employee_job_change_requests where id=any(ids))<>cardinality(ids) then raise exception 'أحد الطلبات غير متاح';end if;
 select array_agg(distinct manager_id) into owners from public.employee_job_change_requests where id=any(ids);
 if cardinality(owners)<>1 or owners[1] is null then raise exception 'الطلبات المرتبطة تحتاج صاحب قرار واحد؛ لا يغير الربط صلاحيات الاعتماد';end if;
 for r in select * from public.employee_job_change_requests where id=any(ids) loop
  if r.status not in ('MANAGER_REVIEW','ADMIN_REVIEW','NEEDS_CHANGES','STALE') then raise exception 'لا تربط طلبًا جرى تطبيقه أو انتهى';end if;
  if r.manager_id is distinct from (select manager_id from public.profiles where id=r.requester_id) then raise exception 'صحح مرجعية الطلب قبل الربط';end if;
  insert into public.employee_job_change_events(request_id,action,actor_id,note,snapshot) values(r.id,'ربط الطلبات قبل إعادة القرار',auth.uid(),p_note,to_jsonb(r));
  update public.employee_job_change_requests set status='NEEDS_CHANGES',related_request_ids=array_remove(ids,r.id),approval_snapshot=null,manager_decided_at=null,manager_note=null,admin_note='سبب ربط الطلبات: '||btrim(p_note),version=version+1,updated_at=now() where id=r.id;
  update public.employee_job_change_requests set status='MANAGER_REVIEW' where id=r.id;
 end loop;
end $$;
revoke all on function private.link_employee_job_changes(uuid[],text) from public,anon;
grant execute on function private.link_employee_job_changes(uuid[],text) to authenticated;
create function public.link_employee_job_changes(p_ids uuid[],p_note text) returns void language sql security invoker set search_path='pg_catalog','private' as $$ select private.link_employee_job_changes(p_ids,p_note); $$;
revoke all on function public.link_employee_job_changes(uuid[],text) from public,anon;
grant execute on function public.link_employee_job_changes(uuid[],text) to authenticated;

create function private.review_employee_job_change_group(p_request_id uuid,p_versions jsonb,p_action text,p_note text) returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare r public.employee_job_change_requests%rowtype;ids uuid[];current_request public.employee_job_change_requests%rowtype;
begin
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501';end if;
 if p_action is null or p_action not in ('APPROVE','REJECT','RETURN') then raise exception 'إجراء قرار غير صالح';end if;
 select * into r from public.employee_job_change_requests where id=p_request_id;
 if not found or r.manager_id<>auth.uid() then raise exception 'القرار لصاحب الصلاحية المكلّف' using errcode='42501';end if;
 ids:=array_append(r.related_request_ids,r.id);
 perform id from public.employee_job_change_requests where id=any(ids) order by id for update;
 if (select count(*) from public.employee_job_change_requests where id=any(ids))<>cardinality(ids) then raise exception 'طلب مرتبط غير متاح';end if;
 for current_request in select * from public.employee_job_change_requests where id=any(ids) order by id loop
  if current_request.manager_id<>auth.uid() or current_request.status<>'MANAGER_REVIEW' then raise exception 'يلزم أن تكون كل الطلبات عند صاحب القرار نفسه' using errcode='42501';end if;
  if nullif(p_versions->>current_request.id::text,'') is null or (p_versions->>current_request.id::text)::int<>current_request.version then raise exception 'ATWAR_CONFLICT: linked request changed';end if;
 end loop;
 for current_request in select * from public.employee_job_change_requests where id=any(ids) order by id loop
  perform private.review_employee_job_change(current_request.id,current_request.version,p_action,p_note);
 end loop;
end $$;
revoke all on function private.review_employee_job_change_group(uuid,jsonb,text,text) from public,anon;
grant execute on function private.review_employee_job_change_group(uuid,jsonb,text,text) to authenticated;
create function public.review_employee_job_change_group(p_request_id uuid,p_versions jsonb,p_action text,p_note text) returns void language sql security invoker set search_path='pg_catalog','private' as $$ select private.review_employee_job_change_group(p_request_id,p_versions,p_action,p_note); $$;
revoke all on function public.review_employee_job_change_group(uuid,jsonb,text,text) from public,anon;
grant execute on function public.review_employee_job_change_group(uuid,jsonb,text,text) to authenticated;
CREATE OR REPLACE FUNCTION private.prepare_job_description()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_uid uuid:=(select auth.uid());v_admin boolean:=private.is_admin();
  v_draft boolean:=private.can_job_stage('DRAFT');v_final boolean:=private.can_job_stage('FINAL_REVIEW');
  v_publish boolean:=private.can_job_stage('PUBLISH');
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 new.job_code:=upper(btrim(new.job_code));new.title:=btrim(new.title);new.purpose:=btrim(new.purpose);
 if tg_op='INSERT' then
   if not v_draft then raise exception 'Draft creation permission required' using errcode='42501'; end if;
   new.created_by:=v_uid;new.updated_by:=v_uid;new.created_at:=now();new.updated_at:=now();new.revision:=1;
   new.status:='DRAFT';new.final_reviewed_at:=null;new.final_reviewed_by:=null;
 else
   if old.status='MANAGER_APPROVED' and new.status='MANAGER_APPROVED' and (new.title,new.purpose,new.content) is distinct from (old.title,old.purpose,old.content) then
     new.status:='DRAFT';new.final_reviewed_at:=null;new.final_reviewed_by:=null;new.manager_approved_by:=null;new.manager_approved_at:=null;
   end if;
   new.created_by:=old.created_by;new.created_at:=old.created_at;new.updated_by:=v_uid;new.updated_at:=now();new.revision:=old.revision+1;
   if old.status in ('IN_REVIEW','CHANGES_REQUESTED') and old.reviewer_id=v_uid and not (v_draft or v_final or v_publish) then
     new.job_code:=old.job_code;new.reviewer_id:=old.reviewer_id;
     if new.status not in ('IN_REVIEW','CHANGES_REQUESTED','MANAGER_APPROVED') then raise exception 'Reviewer cannot publish or archive'; end if;
     if new.status='CHANGES_REQUESTED' and char_length(btrim(coalesce(new.review_note,'')))<2 then raise exception 'A review note is required'; end if;
     if new.status='MANAGER_APPROVED' then new.manager_approved_by:=v_uid;new.manager_approved_at:=now(); end if;
   else
     if not (v_draft or v_final or v_publish) then raise exception 'Job stage permission required' using errcode='42501'; end if;
     if (new.job_code,new.title,new.family,new.job_level,new.reports_to_title,new.purpose,new.content,new.reviewer_id)
         is distinct from (old.job_code,old.title,old.family,old.job_level,old.reports_to_title,old.purpose,old.content,old.reviewer_id)
       and not (v_draft or (v_final and old.status='MANAGER_APPROVED')) then
       raise exception 'Draft or final review permission required' using errcode='42501';
     end if;
     if new.status is distinct from old.status then
       if new.status='IN_REVIEW' and v_draft and old.status in ('DRAFT','CHANGES_REQUESTED','PUBLISHED') then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='CHANGES_REQUESTED' and (v_final or v_publish) and old.status in ('IN_REVIEW','MANAGER_APPROVED') then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='MANAGER_APPROVED' and old.status in ('PUBLISHED','DRAFT') and v_draft and private.employee_change_covers_job(new,old) then
         select r.manager_id,r.manager_decided_at into new.manager_approved_by,new.manager_approved_at from public.employee_job_change_requests r where r.job_description_id=new.id and r.status='APPLIED' and r.applied_revision=old.revision+1;
       elsif new.status='MANAGER_APPROVED' and (old.reviewer_id=v_uid or v_admin) and old.status in ('IN_REVIEW','CHANGES_REQUESTED') then
         new.manager_approved_by:=v_uid;new.manager_approved_at:=now();
       elsif new.status='DRAFT' and v_draft then
         new.final_reviewed_at:=null;new.final_reviewed_by:=null;
       elsif new.status='PUBLISHED' and v_publish and old.status='MANAGER_APPROVED' and old.final_reviewed_at is not null then
         new.published_by:=v_uid;new.published_at:=now();
         new.published_snapshot:=jsonb_build_object('job_code',new.job_code,'title',new.title,'family',new.family,
           'job_level',new.job_level,'reports_to_title',new.reports_to_title,'purpose',new.purpose,
           'content',new.content,'revision',new.revision,'published_at',now());
       elsif new.status='ARCHIVED' and v_publish then null;
       else raise exception 'Stage transition is not permitted' using errcode='42501'; end if;
     end if;
   end if;
   if new.final_reviewed_at is distinct from old.final_reviewed_at and new.final_reviewed_at is not null then
     if not v_final or old.status<>'MANAGER_APPROVED' then raise exception 'Final review permission required' using errcode='42501'; end if;
     if exists(select 1 from public.job_description_change_requests where job_description_id=old.id and status='PENDING' and action<>'COMMENT') then raise exception 'Resolve pending proposals first'; end if;
     new.final_reviewed_at:=now();new.final_reviewed_by:=v_uid;
   end if;
 end if;
 return new;
end $function$
;
-- E2E checks use only existing dedicated test accounts; all generated data rolls back.
do $qa$
declare a uuid;m uuid;e uuid; jid uuid:=gen_random_uuid();rid uuid; req public.employee_job_change_requests%rowtype;before_snapshot jsonb;kpi jsonb;job public.job_descriptions%rowtype; result text;rid2 uuid; versions jsonb;
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

  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  rid:=public.submit_employee_job_change_structured(jid,(before_snapshot->>'revision')::int,'RESPONSIBILITIES','MODIFY',0,'{"text":"QA linked duty"}','QA related duty','QA related role',gen_random_uuid());
  rid2:=public.submit_employee_job_change_structured(jid,(before_snapshot->>'revision')::int,'REPORTS','MODIFY',0,'{"name":"QA linked report"}','QA related report','QA related role',gen_random_uuid());
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  perform public.link_employee_job_changes(array[rid,rid2],'QA linked changes with one owner');
  if not (select related_request_ids @> array[rid2] and approval_snapshot is null from public.employee_job_change_requests where id=rid) then raise exception 'QA FAILED: links or old approval';end if;
  select jsonb_object_agg(id::text,version) into versions from public.employee_job_change_requests where id in(rid,rid2);
  begin perform public.review_employee_job_change_group(rid,versions,'APPROVE','QA admin cannot decide group');raise exception 'QA FAILED: admin group decision';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
  begin perform public.review_employee_job_change_group(rid,versions||jsonb_build_object(rid2::text,0),'APPROVE','QA stale group');raise exception 'QA FAILED: stale group';exception when raise_exception then if sqlerrm not like 'ATWAR_CONFLICT:%' then raise;end if;end;
  if exists(select 1 from public.employee_job_change_requests where id in(rid,rid2) and status<>'MANAGER_REVIEW') then raise exception 'QA FAILED: partial group decision';end if;
  perform public.review_employee_job_change_group(rid,versions,'APPROVE','QA owner approves both changes');
  if exists(select 1 from public.employee_job_change_requests where id in(rid,rid2) and status<>'ADMIN_REVIEW') then raise exception 'QA FAILED: group approval';end if;
  raise exception using errcode='ZX001',message='QA rollback after successful checks';
 exception when sqlstate 'ZX001' then null;end;
 raise notice 'PASS: structured changes, owner-only decision, return, correction audit, exact approval reuse, published protection and unrelated-edit invalidation';
end $qa$;



commit;

