begin;
CREATE OR REPLACE FUNCTION private.employee_change_covers_job(p_new job_descriptions, p_old job_descriptions)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare r public.employee_job_change_requests%rowtype; expected jsonb; expected_purpose text; k text; a jsonb; matched integer:=0;
begin
 if p_old.published_snapshot is null then return false; end if;
 if (p_old.title,p_old.family,p_old.job_level,p_old.reports_to_title,p_old.purpose,p_old.content) is distinct from
 (p_old.published_snapshot->>'title',p_old.published_snapshot->>'family',p_old.published_snapshot->>'job_level',p_old.published_snapshot->>'reports_to_title',p_old.published_snapshot->>'purpose',p_old.published_snapshot->'content') then return false; end if;
 expected:=p_old.content;expected_purpose:=p_old.purpose;
 for r in select * from public.employee_job_change_requests where job_description_id=p_new.id and status='APPLIED' and applied_revision=p_old.revision+1 and manager_decided_at is not null and approval_snapshot is not null order by case when action='ADD' then 1 else 0 end,item_index desc,id loop
  if r.approval_snapshot<>jsonb_build_object('section',r.section,'action',r.action,'index',r.item_index,'original',r.original_value,'proposed',r.proposed_value,'impact',r.impact_note) or r.published_revision<>(p_old.published_snapshot->>'revision')::int then return false; end if;
  if r.section='PURPOSE' then if to_jsonb(expected_purpose) is distinct from r.original_value then return false;end if;expected_purpose:=r.proposed_value#>>'{}';
  else k:=case r.section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;a:=coalesce(expected->k,'[]');
   if r.action<>'ADD' and a->r.item_index is distinct from r.original_value then continue; end if;
   a:=case r.action when 'ADD' then a||jsonb_build_array(r.proposed_value) when 'DELETE' then a-r.item_index else jsonb_set(a,array[r.item_index::text],r.proposed_value) end;expected:=jsonb_set(expected,array[k],a);
  end if;
  matched:=matched+1;
 end loop;
 return matched>0 and (p_new.title,p_new.family,p_new.job_level,p_new.reports_to_title,p_new.purpose,p_new.content) is not distinct from (p_old.title,p_old.family,p_old.job_level,p_old.reports_to_title,expected_purpose,expected);
end
$function$;

CREATE OR REPLACE FUNCTION private.review_employee_job_change(p_request_id uuid, p_version integer, p_action text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare r public.employee_job_change_requests%rowtype;j public.job_descriptions%rowtype;c jsonb;a jsonb;k text;next_purpose text;prepared jsonb; related public.employee_job_change_requests%rowtype; prepared_ids uuid[]:='{}';
begin
 if p_action is null or p_action not in ('APPROVE','REJECT','RETURN','PREPARE') then raise exception 'إجراء غير صالح';end if;
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into r from public.employee_job_change_requests where id=p_request_id for update;
 if not found then raise exception 'Request not found'; end if;
 if r.version<>p_version then raise exception 'ATWAR_CONFLICT: request changed'; end if;
 if char_length(btrim(coalesce(p_note,''))) not between 2 and 2000 then raise exception 'توضيح الإجراء مطلوب'; end if;
 if p_action='RETURN' then
  if not((r.status='MANAGER_REVIEW' and r.manager_id=auth.uid()) or (r.status='ADMIN_REVIEW' and private.is_admin())) then raise exception 'صاحب الإجراء الحالي فقط يمكنه إعادة الطلب' using errcode='42501'; end if;
  update public.employee_job_change_requests set status='NEEDS_CHANGES',admin_note=case when private.is_admin() then btrim(p_note) else admin_note end,manager_note=case when auth.uid()=r.manager_id then btrim(p_note) else manager_note end,approval_snapshot=null,manager_decided_at=null,version=version+1,updated_at=now() where id=r.id;return 'NEEDS_CHANGES';
 end if;
 if p_action in ('APPROVE','REJECT') then
  if r.status<>'MANAGER_REVIEW' or r.manager_id<>auth.uid() then raise exception 'القرار للمدير المباشر المكلّف' using errcode='42501'; end if;
  if p_action='APPROVE' then
   if r.manager_id is distinct from (select manager_id from public.profiles where id=r.requester_id) then raise exception 'تغير المدير المباشر؛ صحح مرجعية الطلب قبل القرار';end if;
   perform private.validate_job_change_value(r.section,r.action,r.original_value,r.proposed_value);
   select * into j from public.job_descriptions where id=r.job_description_id;
   if j.status='ARCHIVED' or (j.published_snapshot->>'revision')::int<>r.published_revision then raise exception 'ATWAR_CONFLICT: published revision changed';end if;
  end if;
  update public.employee_job_change_requests set status=case p_action when 'APPROVE' then 'ADMIN_REVIEW' else 'REJECTED' end,manager_note=btrim(p_note),manager_decided_at=now(),approval_snapshot=case p_action when 'APPROVE' then jsonb_build_object('section',r.section,'action',r.action,'index',r.item_index,'original',r.original_value,'proposed',r.proposed_value,'impact',r.impact_note) else null end,version=version+1,updated_at=now() where id=r.id;
  return case p_action when 'APPROVE' then 'ADMIN_REVIEW' else 'REJECTED' end;
 end if;
 if p_action<>'PREPARE' or r.status<>'ADMIN_REVIEW' or not private.is_admin() or r.manager_decided_at is null or r.approval_snapshot is null then raise exception 'التجهيز يتطلب قرارًا محددًا من المدير وصلاحية مسؤول النظام' using errcode='42501'; end if;
 if r.manager_id is distinct from (select manager_id from public.profiles where id=r.requester_id) then raise exception 'تغير المدير المباشر؛ يلزم إعادة المراجعة';end if;
 perform private.validate_job_change_value(r.section,r.action,r.original_value,r.proposed_value);
 select * into j from public.job_descriptions where id=r.job_description_id for update;
 if j.status not in ('PUBLISHED','DRAFT') or (j.published_snapshot->>'revision')::int<>r.published_revision then raise exception 'ATWAR_CONFLICT: published revision changed'; end if;
 c:=j.content;next_purpose:=j.purpose;
 for related in select * from public.employee_job_change_requests where job_description_id=j.id and id=any(array_append(r.related_request_ids,r.id)) order by case when action='ADD' then 1 else 0 end,item_index desc,id for update loop
  if related.status<>'ADMIN_REVIEW' or related.manager_id<>r.manager_id or related.manager_decided_at is null or related.approval_snapshot is null or related.published_revision<>r.published_revision or related.manager_id is distinct from (select manager_id from public.profiles where id=related.requester_id) then raise exception 'يلزم قرار صحيح لكل تغيير مرتبط قبل التجهيز';end if;
  if related.approval_snapshot<>jsonb_build_object('section',related.section,'action',related.action,'index',related.item_index,'original',related.original_value,'proposed',related.proposed_value,'impact',related.impact_note) then raise exception 'ATWAR_CONFLICT: approved proposal changed';end if;
  perform private.validate_job_change_value(related.section,related.action,related.original_value,related.proposed_value);
  prepared_ids:=array_append(prepared_ids,related.id);
 if related.section='PURPOSE' then if to_jsonb(j.purpose) is distinct from related.original_value then raise exception 'ATWAR_CONFLICT: purpose changed';end if;next_purpose:=related.proposed_value#>>'{}';
 else k:=case related.section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;a:=coalesce(c->k,'[]');if related.action<>'ADD' and a->related.item_index is distinct from related.original_value then raise exception 'ATWAR_CONFLICT: item changed';end if;
  a:=case related.action when 'ADD' then a||jsonb_build_array(related.proposed_value) when 'DELETE' then a-related.item_index else jsonb_set(a,array[related.item_index::text],related.proposed_value) end;c:=jsonb_set(c,array[k],a);
 end if;

 end loop;
 prepared:=jsonb_build_object('title',j.title,'family',j.family,'job_level',j.job_level,'reports_to_title',j.reports_to_title,'purpose',next_purpose,'content',c);
 update public.employee_job_change_requests set status='APPLIED',applied_revision=j.revision+1,prepared_snapshot=prepared,admin_note=btrim(p_note),admin_decided_at=now(),version=version+1,updated_at=now() where id=any(prepared_ids);
 j.content:=c;j.purpose:=next_purpose;
 if not private.employee_change_covers_job(j,(select d from public.job_descriptions d where id=r.job_description_id)) then raise exception 'توجد تغييرات أخرى في المسودة؛ راجعها مع المدير قبل دمج هذا القرار'; end if;
 j.reviewer_mode:='auto';
 perform private.check_job_authoring_content(j);
 update public.job_descriptions set content=c,purpose=next_purpose,reviewer_id=r.manager_id,status='MANAGER_APPROVED',final_reviewed_at=null,final_reviewed_by=null where id=j.id;
 return 'APPLIED';
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
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  update public.job_descriptions set purpose=before_snapshot->>'purpose',content=before_snapshot->'content',status='DRAFT' where id=jid;
  kpi:=before_snapshot#>'{content,kpis,0}';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
  rid:=public.submit_employee_job_change_structured(jid,(before_snapshot->>'revision')::int,'KPIS','MODIFY',0,kpi||'{"weight":50}','QA rebalance original weight','QA coupled weights',gen_random_uuid());
  rid2:=public.submit_employee_job_change_structured(jid,(before_snapshot->>'revision')::int,'KPIS','ADD',null,kpi||'{"name":"QA added indicator","weight":50}','QA additional weight','QA coupled weights',gen_random_uuid());
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
  select * into req from public.employee_job_change_requests where id=rid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  perform public.review_employee_job_change(rid,req.version,'PREPARE','QA prepare two approved weights together');
  if (select sum((v->>'weight')::numeric) from public.job_descriptions d,jsonb_array_elements(d.content->'kpis') v where d.id=jid)<>100 or (select jsonb_array_length(content->'kpis') from public.job_descriptions where id=jid)<>2 then raise exception 'QA FAILED: linked weights or indicators';end if;
  if exists(select 1 from public.employee_job_change_requests where id in(rid,rid2) and status<>'APPLIED') then raise exception 'QA FAILED: partial linked preparation';end if;
  raise exception using errcode='ZX001',message='QA rollback after successful checks';
 exception when sqlstate 'ZX001' then null;end;
 raise notice 'PASS: structured changes, owner-only decision, return, correction audit, exact approval reuse, published protection and unrelated-edit invalidation';
end $qa$;




commit;

