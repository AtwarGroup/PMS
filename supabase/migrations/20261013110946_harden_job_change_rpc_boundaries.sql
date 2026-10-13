begin;
CREATE OR REPLACE FUNCTION private.correct_employee_job_change(p_request_id uuid, p_version integer, p_section text, p_action text, p_index integer, p_value jsonb, p_reason text, p_impact text, p_correction_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare r public.employee_job_change_requests%rowtype; j public.job_descriptions%rowtype; original jsonb; result jsonb; mgr uuid; k text;
begin
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into r from public.employee_job_change_requests where id=p_request_id for update;
 if not found or not(private.is_admin() or (r.requester_id=auth.uid() and r.status in ('NEEDS_CHANGES','STALE'))) then raise exception 'صلاحية تصحيح الطلب مطلوبة' using errcode='42501'; end if;
 if r.version<>p_version then raise exception 'ATWAR_CONFLICT: request changed'; end if;
 if r.status not in ('MANAGER_REVIEW','ADMIN_REVIEW','NEEDS_CHANGES','STALE') then raise exception 'لا يمكن تصحيح طلب انتهى إجراءه'; end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 2 and 2000 or char_length(btrim(coalesce(p_correction_note,''))) not between 2 and 2000 then raise exception 'المبررات وسبب التصحيح مطلوبان'; end if;
 select * into j from public.job_descriptions where id=r.job_description_id for share;
 if j.published_snapshot is null or j.status='ARCHIVED' then raise exception 'الوصف المنشور غير متاح'; end if;
 select manager_id into mgr from public.profiles where id=r.requester_id;
 if mgr is null or mgr=r.requester_id or not exists(select 1 from public.profiles where id=mgr and active=true and status='active') then raise exception 'حدد صاحب القرار في الهيكل قبل الإرسال'; end if;
 k:=case p_section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;
 original:=case when p_action='ADD' then null when p_section='PURPOSE' then j.published_snapshot->'purpose' else j.published_snapshot->'content'->k->p_index end;
 if p_action<>'ADD' and (original is null or (p_section<>'PURPOSE' and (p_index is null or p_index<0 or p_index>=jsonb_array_length(coalesce(j.published_snapshot->'content'->k,'[]'))))) then raise exception 'اختر البند الصحيح'; end if;
 if p_section='PURPOSE' and p_action<>'MODIFY' then raise exception 'الغرض الوظيفي يسمح بالتعديل فقط'; end if;
 result:=private.validate_job_change_value(p_section,p_action,original,p_value);
 insert into public.employee_job_change_events(request_id,action,actor_id,note,snapshot) values(r.id,'أصل الطلب قبل التصحيح',auth.uid(),p_correction_note,to_jsonb(r));
 -- Close old tasks before re-routing even if the previous stage was manager review.
 update public.tasks set status='مكتملة',progress=100,completed_at=now(),actual_end_date=current_date,revision=revision+1,updated_at=now() where id in(r.manager_task_id,r.admin_task_id) and status<>'مكتملة' and deleted_at is null;
 update public.employee_job_change_requests set section=p_section,action=p_action,item_index=case when p_section='PURPOSE' or p_action='ADD' then null else p_index end,original_value=original,proposed_value=result,published_revision=(j.published_snapshot->>'revision')::int,reason=btrim(p_reason),impact_note=left(coalesce(p_impact,''),2000),manager_id=mgr,status='MANAGER_REVIEW',manager_note=null,manager_decided_at=null,approval_snapshot=null,prepared_snapshot=null,admin_note='تصحيح التهيئة: '||btrim(p_correction_note),admin_decided_at=null,version=version+1,updated_at=now() where id=r.id;
 -- The existing task trigger only acts on status changes.
 if r.status='MANAGER_REVIEW' then
  update public.employee_job_change_requests set status='NEEDS_CHANGES' where id=r.id;
  update public.employee_job_change_requests set status='MANAGER_REVIEW' where id=r.id;
 end if;
 return r.id;
end $function$
;
revoke all on function private.correct_employee_job_change(uuid,integer,text,text,integer,jsonb,text,text,text) from public,anon;
grant execute on function private.correct_employee_job_change(uuid,integer,text,text,integer,jsonb,text,text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.correct_employee_job_change(p_request_id uuid, p_version integer, p_section text, p_action text, p_index integer, p_value jsonb, p_reason text, p_impact text, p_correction_note text) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog','public','private' AS $$ SELECT private.correct_employee_job_change(p_request_id,p_version,p_section,p_action,p_index,p_value,p_reason,p_impact,p_correction_note); $$;
revoke all on function public.correct_employee_job_change(uuid,integer,text,text,integer,jsonb,text,text,text) from public,anon;
grant execute on function public.correct_employee_job_change(uuid,integer,text,text,integer,jsonb,text,text,text) to authenticated;
CREATE OR REPLACE FUNCTION private.review_employee_job_change(p_request_id uuid, p_version integer, p_action text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare r public.employee_job_change_requests%rowtype;j public.job_descriptions%rowtype;c jsonb;a jsonb;k text;next_purpose text;prepared jsonb;
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
 if r.section='PURPOSE' then if to_jsonb(j.purpose) is distinct from r.original_value then raise exception 'ATWAR_CONFLICT: purpose changed';end if;next_purpose:=r.proposed_value#>>'{}';
 else k:=case r.section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;a:=coalesce(c->k,'[]');if r.action<>'ADD' and a->r.item_index is distinct from r.original_value then raise exception 'ATWAR_CONFLICT: item changed';end if;
  a:=case r.action when 'ADD' then a||jsonb_build_array(r.proposed_value) when 'DELETE' then a-r.item_index else jsonb_set(a,array[r.item_index::text],r.proposed_value) end;c:=jsonb_set(c,array[k],a);
 end if;
 prepared:=jsonb_build_object('title',j.title,'family',j.family,'job_level',j.job_level,'reports_to_title',j.reports_to_title,'purpose',next_purpose,'content',c);
 update public.employee_job_change_requests set status='APPLIED',applied_revision=j.revision+1,prepared_snapshot=prepared,admin_note=btrim(p_note),admin_decided_at=now(),version=version+1,updated_at=now() where id=r.id;
 j.content:=c;j.purpose:=next_purpose;
 if not private.employee_change_covers_job(j,(select d from public.job_descriptions d where id=r.job_description_id)) then raise exception 'توجد تغييرات أخرى في المسودة؛ راجعها مع المدير قبل دمج هذا القرار'; end if;
 j.reviewer_mode:='auto';
 perform private.check_job_authoring_content(j);
 update public.job_descriptions set content=c,purpose=next_purpose,reviewer_id=r.manager_id,status='MANAGER_APPROVED',final_reviewed_at=null,final_reviewed_by=null where id=j.id;
 return 'APPLIED';
end $function$
;
revoke all on function private.review_employee_job_change(uuid,integer,text,text) from public,anon;
grant execute on function private.review_employee_job_change(uuid,integer,text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.review_employee_job_change(p_request_id uuid, p_version integer, p_action text, p_note text) RETURNS text LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog','public','private' AS $$ SELECT private.review_employee_job_change(p_request_id,p_version,p_action,p_note); $$;
revoke all on function public.review_employee_job_change(uuid,integer,text,text) from public,anon;
grant execute on function public.review_employee_job_change(uuid,integer,text,text) to authenticated;
CREATE OR REPLACE FUNCTION private.submit_employee_job_change_structured(p_job_id uuid, p_revision integer, p_section text, p_action text, p_index integer, p_value jsonb, p_reason text, p_impact text, p_client_key uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare j public.job_descriptions%rowtype; original jsonb; result jsonb; k text; id uuid; mgr uuid; adm uuid;
begin
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501'; end if;
 select r.id into id from public.employee_job_change_requests r where r.requester_id=auth.uid() and r.client_key=p_client_key;
 if id is not null then return id; end if;
 select * into j from public.job_descriptions where job_descriptions.id=p_job_id;
 if not found or not private.can_view_published_job(j.id) or j.published_snapshot is null or j.status='ARCHIVED' then raise exception 'Only your published job description is eligible' using errcode='42501'; end if;
 if (j.published_snapshot->>'revision')::integer<>p_revision then raise exception 'ATWAR_CONFLICT: published revision changed'; end if;
 select manager_id into mgr from public.profiles where profiles.id=auth.uid();
 if mgr is null or mgr=auth.uid() or not exists(select 1 from public.profiles where profiles.id=mgr and active=true and status='active') then raise exception 'يلزم تحديد صاحب قرار المحتوى في الهيكل؛ لا يحول الطلب تلقائيًا إلى مسؤول النظام'; end if;
 k:=case p_section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;
 original:=case when p_action='ADD' then null when p_section='PURPOSE' then j.published_snapshot->'purpose' else j.published_snapshot->'content'->k->p_index end;
 if p_action<>'ADD' and (original is null or (p_section<>'PURPOSE' and (p_index is null or p_index<0 or p_index>=jsonb_array_length(coalesce(j.published_snapshot->'content'->k,'[]'))))) then raise exception 'اختر البند الصحيح'; end if;
 if p_section='PURPOSE' and p_action<>'MODIFY' then raise exception 'الغرض الوظيفي يسمح بالتعديل فقط'; end if;
 result:=private.validate_job_change_value(p_section,p_action,original,p_value);
 if p_client_key is null or char_length(btrim(coalesce(p_reason,''))) not between 2 and 2000 or char_length(coalesce(p_impact,''))>2000 then raise exception 'المبررات أو مفتاح الطلب غير صالح';end if;
 select p.id into adm from public.profiles p where p.role='admin' and p.active=true and p.status='active' order by (p.id=private.job_stage_owner('FINAL_REVIEW')) desc,p.id limit 1;
 if adm is null then raise exception 'No active system administrator';end if;
 insert into public.employee_job_change_requests(client_key,job_description_id,requester_name,job_title,requester_id,manager_id,admin_id,published_revision,section,action,item_index,original_value,proposed_value,reason,status,impact_note)
 values(p_client_key,j.id,(select full_name from public.profiles where profiles.id=auth.uid()),j.title,auth.uid(),mgr,adm,p_revision,p_section,p_action,case when p_action='ADD' or p_section='PURPOSE' then null else p_index end,original,result,btrim(p_reason),'MANAGER_REVIEW',coalesce(p_impact,'')) on conflict(requester_id,client_key) do nothing returning employee_job_change_requests.id into id;
 if id is null then select r.id into id from public.employee_job_change_requests r where r.requester_id=auth.uid() and r.client_key=p_client_key;end if;
 return id;
end $function$
;
revoke all on function private.submit_employee_job_change_structured(uuid,integer,text,text,integer,jsonb,text,text,uuid) from public,anon;
grant execute on function private.submit_employee_job_change_structured(uuid,integer,text,text,integer,jsonb,text,text,uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.submit_employee_job_change_structured(p_job_id uuid, p_revision integer, p_section text, p_action text, p_index integer, p_value jsonb, p_reason text, p_impact text, p_client_key uuid) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog','public','private' AS $$ SELECT private.submit_employee_job_change_structured(p_job_id,p_revision,p_section,p_action,p_index,p_value,p_reason,p_impact,p_client_key); $$;
revoke all on function public.submit_employee_job_change_structured(uuid,integer,text,text,integer,jsonb,text,text,uuid) from public,anon;
grant execute on function public.submit_employee_job_change_structured(uuid,integer,text,text,integer,jsonb,text,text,uuid) to authenticated;
commit;

