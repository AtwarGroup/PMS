begin;
alter table public.employee_job_change_requests add column impact_note text not null default '', add column approval_snapshot jsonb, add column prepared_snapshot jsonb;
alter table public.employee_job_change_requests drop constraint employee_job_change_requests_status_check;
alter table public.employee_job_change_requests add constraint employee_job_change_requests_status_check check(status in ('MANAGER_REVIEW','ADMIN_REVIEW','APPLIED','PUBLISHED','REJECTED','STALE','NEEDS_CHANGES'));
create table public.employee_job_change_events(
 id bigint generated always as identity primary key,
 request_id uuid not null references public.employee_job_change_requests(id),
 action text not null, actor_id uuid references public.profiles(id), note text, snapshot jsonb,
 created_at timestamptz not null default now()
);
create index employee_job_change_events_request_idx on public.employee_job_change_events(request_id,id);
alter table public.employee_job_change_events enable row level security;
revoke all on public.employee_job_change_events from public,anon,authenticated;
grant select on public.employee_job_change_events to authenticated;
create policy employee_job_change_events_read on public.employee_job_change_events for select to authenticated
using(exists(select 1 from public.employee_job_change_requests r where r.id=request_id));
insert into public.employee_job_change_events(request_id,action,note,snapshot)
select id,'الطلب قبل تحديث المسار','حُفظ الطلب وملاحظاته السابقة دون اتخاذ قرار جديد.',to_jsonb(r) from public.employee_job_change_requests r;
create function private.audit_employee_job_change() returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
 if tg_op='INSERT' or (new.section,new.action,new.original_value,new.proposed_value,new.reason,new.status,new.manager_note,new.admin_note,new.impact_note) is distinct from (old.section,old.action,old.original_value,old.proposed_value,old.reason,old.status,old.manager_note,old.admin_note,old.impact_note) then
 insert into public.employee_job_change_events(request_id,action,actor_id,note,snapshot) values(new.id,
 case when tg_op='INSERT' then 'إنشاء الطلب' when new.section is distinct from old.section or new.proposed_value is distinct from old.proposed_value then 'تصحيح الطلب وإعادة المراجعة' when new.status='NEEDS_CHANGES' then 'إعادة للاستكمال' when new.status='ADMIN_REVIEW' then 'موافقة المدير' when new.status='REJECTED' then 'رفض المدير' when new.status='APPLIED' then 'تجهيز الإصدار' when new.status='PUBLISHED' then 'نشر الإصدار' else 'تحديث الطلب' end,
 auth.uid(),case when new.status in ('MANAGER_REVIEW','NEEDS_CHANGES','APPLIED') then coalesce(new.admin_note,new.manager_note) else coalesce(new.manager_note,new.admin_note) end,to_jsonb(new));
 end if; return new;
end $$;
revoke all on function private.audit_employee_job_change() from public,anon,authenticated;
create trigger audit_employee_job_change after insert or update on public.employee_job_change_requests for each row execute function private.audit_employee_job_change();

-- Read only the published source for a request the caller can already access.
create function public.get_employee_job_change_source(p_request_id uuid) returns jsonb language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
declare r public.employee_job_change_requests%rowtype; j public.job_descriptions%rowtype;
begin
 select * into r from public.employee_job_change_requests where id=p_request_id;
 if not found then raise exception 'الطلب غير متاح' using errcode='42501'; end if;
 select * into j from public.job_descriptions where id=r.job_description_id;
 if not found then raise exception 'الوصف غير متاح لهذا الحساب' using errcode='42501'; end if;
 return jsonb_build_object('id',j.id,'published_snapshot',j.published_snapshot);
end $$;
revoke all on function public.get_employee_job_change_source(uuid) from public,anon;
grant execute on function public.get_employee_job_change_source(uuid) to authenticated;

create function private.validate_job_change_value(p_section text,p_action text,p_original jsonb,p_value jsonb) returns jsonb language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
declare result jsonb; k text;
begin
 if p_section not in ('PURPOSE','RESPONSIBILITIES','AUTHORITIES','KPIS','REPORTS') or p_action not in ('ADD','MODIFY','DELETE') then raise exception 'القسم أو الإجراء غير صالح'; end if;
 if p_action='DELETE' then return null; end if;
 if p_value is null then raise exception 'التعديل المطلوب مفقود'; end if;
 if p_section='KPIS' then
  if jsonb_typeof(p_value)<>'object' then raise exception 'يلزم إدخال تفاصيل المؤشر'; end if;
  for k in select jsonb_object_keys(p_value) loop
   if k not in ('name','perspective','measure','unit','target','source','weight','frequency','scale','scale_basis','scale_note','measurement_note','measurement_review_note') then raise exception 'حقل مؤشر غير صالح'; end if;
  end loop;
  result:=coalesce(p_original,'{}')||p_value;
  foreach k in array array['name','measure','unit','target','source','frequency'] loop
   if nullif(btrim(result->>k),'') is null or char_length(result->>k)>2000 then raise exception 'أكمل بيانات المؤشر'; end if;
  end loop;
  if coalesce(result->>'weight','')!~'^[0-9]+(\.[0-9]+)?$' or (result->>'weight')::numeric<=0 or (result->>'weight')::numeric>100 then raise exception 'وزن المؤشر غير صالح'; end if;
  if jsonb_typeof(result->'scale')<>'array' or jsonb_array_length(result->'scale')<>5 or exists(select 1 from jsonb_array_elements(result->'scale') with ordinality s(value,n) where nullif(btrim(value->>'label'),'') is null or coalesce(value->>'score','')<>n::text) then raise exception 'أكمل سلم التقييم الخماسي'; end if;
  if (result->'target',result->'measure',result->'scale') is distinct from (p_original->'target',p_original->'measure',p_original->'scale') then
   result:=result||jsonb_build_object('scale_basis',result->>'target','scale_note','سلم مقترح؛ يعتمد مع قرار صاحب الصلاحية','measurement_review_note','');
  end if;
 else
  k:=case when p_section='REPORTS' then 'name' else 'text' end;
  if p_section='PURPOSE' then
   if jsonb_typeof(p_value)<>'string' or char_length(btrim(p_value#>>'{}')) not between 2 and 2000 then raise exception 'النص المقترح غير صالح'; end if;
   result:=to_jsonb(btrim(p_value#>>'{}'));
  else
   if nullif(btrim(coalesce(p_value->>k,p_value#>>'{}')),'') is null then raise exception 'النص المقترح مطلوب'; end if;
   if jsonb_typeof(p_original)='object' then result:=p_original||jsonb_build_object(k,btrim(coalesce(p_value->>k,p_value#>>'{}')));
   else result:=jsonb_build_object(k,btrim(coalesce(p_value->>k,p_value#>>'{}'))); end if;
  end if;
 end if;
 if p_action='MODIFY' and result=p_original then raise exception 'لم يتغير البند؛ المبررات وحدها لا تمثل تعديلًا'; end if;
 return result;
end $$;
revoke all on function private.validate_job_change_value(text,text,jsonb,jsonb) from public,anon;
grant execute on function private.validate_job_change_value(text,text,jsonb,jsonb) to authenticated;

create function public.submit_employee_job_change_structured(p_job_id uuid,p_revision integer,p_section text,p_action text,p_index integer,p_value jsonb,p_reason text,p_impact text,p_client_key uuid) returns uuid language plpgsql security definer set search_path='pg_catalog','public','private' as $$
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
end $$;
revoke all on function public.submit_employee_job_change_structured(uuid,integer,text,text,integer,jsonb,text,text,uuid) from public,anon;
grant execute on function public.submit_employee_job_change_structured(uuid,integer,text,text,integer,jsonb,text,text,uuid) to authenticated;

create function public.correct_employee_job_change(p_request_id uuid,p_version integer,p_section text,p_action text,p_index integer,p_value jsonb,p_reason text,p_impact text,p_correction_note text) returns uuid language plpgsql security definer set search_path='pg_catalog','public','private' as $$
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
end $$;
revoke all on function public.correct_employee_job_change(uuid,integer,text,text,integer,jsonb,text,text,text) from public,anon;
grant execute on function public.correct_employee_job_change(uuid,integer,text,text,integer,jsonb,text,text,text) to authenticated;

-- A single manager decision covers only its exact original/proposed change, never unrelated draft edits.
create function private.employee_change_covers_job(p_new public.job_descriptions,p_old public.job_descriptions) returns boolean language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare r public.employee_job_change_requests%rowtype; expected jsonb; expected_purpose text; k text; a jsonb;
begin
 if p_old.published_snapshot is null then return false; end if;
 if (p_old.title,p_old.family,p_old.job_level,p_old.reports_to_title,p_old.purpose,p_old.content) is distinct from
 (p_old.published_snapshot->>'title',p_old.published_snapshot->>'family',p_old.published_snapshot->>'job_level',p_old.published_snapshot->>'reports_to_title',p_old.published_snapshot->>'purpose',p_old.published_snapshot->'content') then return false; end if;
 for r in select * from public.employee_job_change_requests where job_description_id=p_new.id and status='APPLIED' and applied_revision=p_old.revision+1 and manager_decided_at is not null and approval_snapshot is not null loop
  if r.approval_snapshot<>jsonb_build_object('section',r.section,'action',r.action,'index',r.item_index,'original',r.original_value,'proposed',r.proposed_value,'impact',r.impact_note) or r.published_revision<>(p_old.published_snapshot->>'revision')::int then continue; end if;
  expected:=p_old.content;expected_purpose:=p_old.purpose;
  if r.section='PURPOSE' then expected_purpose:=r.proposed_value#>>'{}';
  else k:=case r.section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;a:=coalesce(expected->k,'[]');
   if r.action<>'ADD' and a->r.item_index is distinct from r.original_value then continue; end if;
   a:=case r.action when 'ADD' then a||jsonb_build_array(r.proposed_value) when 'DELETE' then a-r.item_index else jsonb_set(a,array[r.item_index::text],r.proposed_value) end;expected:=jsonb_set(expected,array[k],a);
  end if;
  if (p_new.title,p_new.family,p_new.job_level,p_new.reports_to_title,p_new.purpose,p_new.content) is not distinct from (p_old.title,p_old.family,p_old.job_level,p_old.reports_to_title,expected_purpose,expected) then return true; end if;
 end loop;
 return false;
end $$;
revoke all on function private.employee_change_covers_job(public.job_descriptions,public.job_descriptions) from public,anon,authenticated;

create function public.review_employee_job_change(p_request_id uuid,p_version integer,p_action text,p_note text) returns text language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare r public.employee_job_change_requests%rowtype;j public.job_descriptions%rowtype;c jsonb;a jsonb;k text;next_purpose text;prepared jsonb;
begin
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
end $$;
revoke all on function public.review_employee_job_change(uuid,integer,text,text) from public,anon;
grant execute on function public.review_employee_job_change(uuid,integer,text,text) to authenticated;
-- Keep older links functional without granting the administrator a content decision.
create or replace function private.decide_employee_job_change(p_request_id uuid,p_version integer,p_approve boolean,p_note text) returns text language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare r public.employee_job_change_requests%rowtype;
begin
 select * into r from public.employee_job_change_requests where id=p_request_id;
 if p_approve is null then raise exception 'Decision required';end if;
 return public.review_employee_job_change(p_request_id,p_version,case when r.status='MANAGER_REVIEW' then case when p_approve then 'APPROVE' else 'REJECT' end else case when p_approve then 'PREPARE' else 'RETURN' end end,p_note);
end $$;
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
   if old.status='MANAGER_APPROVED' and new.status='MANAGER_APPROVED' and (new.title,new.purpose,new.content) is distinct from (old.title,old.purpose,old.content) and exists(select 1 from public.employee_job_change_requests r where r.job_description_id=old.id and r.status='APPLIED' and r.applied_revision<=old.revision) then
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
end $function$;

CREATE OR REPLACE FUNCTION private.submit_employee_job_change(p_job_id uuid, p_revision integer, p_section text, p_action text, p_index integer, p_text text, p_reason text, p_client_key uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare j public.job_descriptions%rowtype; r uuid; mgr uuid; adm uuid; original jsonb; proposed jsonb; k text; rows jsonb;
begin
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_client_key is null then raise exception 'Request key required'; end if;
 select id into r from public.employee_job_change_requests where requester_id=auth.uid() and client_key=p_client_key;
 if r is not null then return r; end if;
 select * into j from public.job_descriptions where id=p_job_id for share;
 if not found or not private.can_view_published_job(p_job_id) or j.published_snapshot is null or j.status='ARCHIVED' then raise exception 'Only your published job description is eligible' using errcode='42501'; end if;
 if (j.published_snapshot->>'revision')::integer<>p_revision then raise exception 'ATWAR_CONFLICT: published revision changed'; end if;
 if p_section not in ('PURPOSE','RESPONSIBILITIES','AUTHORITIES','KPIS','REPORTS') or p_action not in ('ADD','MODIFY','DELETE') then raise exception 'Invalid proposal'; end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 2 and 2000 or (p_action<>'DELETE' and char_length(btrim(coalesce(p_text,''))) not between 2 and 2000) then raise exception 'Text and reason are required (2–2000 characters)'; end if;
 if p_section='PURPOSE' then
  if p_action<>'MODIFY' then raise exception 'Purpose allows modification only'; end if;
  original:=j.published_snapshot->'purpose';proposed:=to_jsonb(btrim(p_text));
 else
  k:=case p_section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;
  rows:=coalesce(j.published_snapshot->'content'->k,'[]'::jsonb);
  if p_action<>'ADD' and (p_index is null or p_index<0 or p_index>=jsonb_array_length(rows)) then raise exception 'Invalid item index'; end if;
  original:=case when p_action='ADD' then null else rows->p_index end;
  proposed:=case when p_action='DELETE' then null when jsonb_typeof(original)='object' then original||jsonb_build_object(case when p_section in ('KPIS','REPORTS') then 'name' else 'text' end,btrim(p_text)) when p_action='ADD' then jsonb_build_object(case when p_section in ('KPIS','REPORTS') then 'name' else 'text' end,btrim(p_text)) else to_jsonb(btrim(p_text)) end;
 end if;
 if p_section='KPIS' and p_action='ADD' then raise exception 'استخدم نموذج المؤشر الكامل لإضافة مؤشر';end if;
 proposed:=private.validate_job_change_value(p_section,p_action,original,proposed);
 select manager_id into mgr from public.profiles where id=auth.uid();
 if mgr=auth.uid() or not exists(select 1 from public.profiles where id=mgr and active=true and status='active') then mgr:=null; end if;
 select p.id into adm from public.profiles p where p.role='admin' and p.active=true and p.status='active'
 order by (p.id=private.job_stage_owner('FINAL_REVIEW')) desc,p.id limit 1;
 if mgr is null then raise exception 'حدد صاحب قرار المحتوى في الهيكل؛ لا يحول الطلب إلى مسؤول النظام';end if;
 if adm is null then raise exception 'No active system administrator'; end if;
 insert into public.employee_job_change_requests(client_key,job_description_id,requester_name,job_title,requester_id,manager_id,admin_id,published_revision,section,action,item_index,original_value,proposed_value,reason,status)
 values(p_client_key,j.id,(select full_name from public.profiles where id=auth.uid()),j.title,auth.uid(),mgr,adm,p_revision,p_section,p_action,case when p_action='ADD' then null else p_index end,original,proposed,btrim(p_reason),case when mgr is null then 'ADMIN_REVIEW' else 'MANAGER_REVIEW' end)
 on conflict(requester_id,client_key) do nothing returning id into r;
 if r is null then select id into r from public.employee_job_change_requests where requester_id=auth.uid() and client_key=p_client_key; end if;
 return r;
end $function$;

CREATE OR REPLACE FUNCTION private.sync_employee_job_change_tasks()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare t uuid; recipient uuid; phase text; jtitle text; employee text; target text;
begin
 if tg_op='UPDATE' and new.status=old.status then return new; end if;
 if tg_op='UPDATE' then
  update public.tasks set status='مكتملة',progress=100,completed_at=now(),actual_end_date=current_date,revision=revision+1,updated_at=now()
   where id in (new.manager_task_id,new.admin_task_id) and status<>'مكتملة' and deleted_at is null
   and not(new.status='APPLIED' and id=new.admin_task_id);
 end if;
 if new.status in ('MANAGER_REVIEW','ADMIN_REVIEW') then
  recipient:=case when new.status='MANAGER_REVIEW' then new.manager_id else new.admin_id end;
  phase:=case when new.status='MANAGER_REVIEW' then 'EMPLOYEE_CHANGE_MANAGER' else 'EMPLOYEE_CHANGE_ADMIN' end;
  select title into jtitle from public.job_descriptions where id=new.job_description_id;
  select full_name into employee from public.profiles where id=new.requester_id;
  select full_name into target from public.profiles where id=recipient;
  insert into public.tasks(title,description,task_type,creator_id,assignee_id,creator_name_snapshot,assignee_name_snapshot,status,priority,progress,start_date,legacy_metadata)
  values(left(case when new.status='MANAGER_REVIEW' then 'مراجعة اقتراح الموظف: ' else 'تجهيز ونشر تعديل وافق عليه المدير: ' end||jtitle,200),
   'الموظف: '||employee||E'\nالسبب: '||new.reason||E'\nافتح طلب تعديل الوصف للاطلاع على البند والاقتراح واتخاذ القرار. تُغلق المهمة آليًا؛ مهمة الاعتماد تبقى حتى نشر النسخة.',
   'job_workflow',new.requester_id,recipient,employee,target,'قيد الانتظار','normal',0,current_date,
   jsonb_build_object('job_workflow',jsonb_build_object('job_id',new.job_description_id,'phase',phase,'request_id',new.id))) returning id into t;
  if new.status='MANAGER_REVIEW' then update public.employee_job_change_requests set manager_task_id=t where id=new.id;
  else update public.employee_job_change_requests set admin_task_id=t where id=new.id; end if;
 end if;
 if tg_op='UPDATE' then
  insert into public.notifications(recipient_id,task_id,type,title,message)
   values(new.requester_id,coalesce(new.admin_task_id,new.manager_task_id),'job_change_decision','تحديث طلب تعديل الوصف الوظيفي',
    case new.status when 'ADMIN_REVIEW' then 'وافق المدير على التغيير المحدد؛ ينتظر التحقق والتجهيز.' when 'APPLIED' then 'جُهز التغيير الذي وافق عليه المدير؛ بانتظار النشر.' when 'PUBLISHED' then 'نُشر الإصدار الجديد؛ راجع وصفك وسجل الإقرار الجديد.' when 'NEEDS_CHANGES' then 'أعيد الطلب للاستكمال: '||coalesce(new.admin_note,new.manager_note,'') when 'STALE' then 'تغير البند أثناء المراجعة؛ راجع ملاحظة القرار.' else 'رُفض الطلب: '||coalesce(new.admin_note,new.manager_note,'') end);
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION private.sync_job_workflow_tasks()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_admin uuid;v_cycle text;v_revision text;v_assignment record;
begin
  if tg_op='UPDATE' and new.status=old.status and new.reviewer_id is not distinct from old.reviewer_id then return new; end if;
  v_cycle:=coalesce(new.submitted_at::text,new.id::text);
  if new.status='CHANGES_REQUESTED' then
 perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW');
 perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
 perform private.ensure_job_workflow_task(new,'DRAFT_REVISION',new.revision::text,private.job_stage_owner('DRAFT'));
 elsif new.status='IN_REVIEW' then
 perform private.close_job_workflow_tasks(new.id,'DRAFT_REVISION');
    perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
    perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW',null,new.reviewer_id);
    perform private.ensure_job_workflow_task(new,'MANAGER_REVIEW',v_cycle,new.reviewer_id);
  elsif new.status='MANAGER_APPROVED' then
    perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW');
    select id into v_admin from public.profiles where id=new.created_by and role='admin' and active=true and status='active';
    if v_admin is null then select id into v_admin from public.profiles where role='admin' and active=true and status='active' order by id limit 1; end if;
    if not exists(select 1 from public.employee_job_change_requests r where r.job_description_id=new.id and r.status='APPLIED' and r.applied_revision=new.revision) then
     perform private.ensure_job_workflow_task(new,'ADMIN_APPROVAL',v_cycle,private.job_stage_owner('FINAL_REVIEW'));
    end if;
  elsif new.status='PUBLISHED' then
    perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW');
    perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
    v_revision:=coalesce(new.published_snapshot->>'revision',new.revision::text);
    for v_assignment in select profile_id from public.employee_job_assignments where job_description_id=new.id loop
      perform private.ensure_job_workflow_task(new,'EMPLOYEE_ACK',v_revision,v_assignment.profile_id);
    end loop;
  elsif new.status in ('DRAFT','ARCHIVED') then
    perform private.close_job_workflow_tasks(new.id,'MANAGER_REVIEW');
    perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION private.sync_final_job_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
 if old.final_reviewed_at is null and new.final_reviewed_at is not null and new.status='MANAGER_APPROVED' then
   perform private.close_job_workflow_tasks(new.id,'ADMIN_APPROVAL');
   if not exists(select 1 from public.employee_job_change_requests r where r.job_description_id=new.id and r.status='APPLIED') then
     perform private.ensure_job_workflow_task(new,'PUBLISH',coalesce(new.submitted_at::text,new.id::text),private.job_stage_owner('PUBLISH'));
   end if;
 elsif old.status is distinct from new.status and new.status in ('IN_REVIEW','CHANGES_REQUESTED','DRAFT','PUBLISHED','ARCHIVED') then
   perform private.close_job_workflow_tasks(new.id,'PUBLISH');
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION private.guard_job_authoring()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
 if tg_op='INSERT' or (new.reports_to_job_id,new.reference_profile_id,new.reviewer_mode,new.reviewer_override_reason) is distinct from
  (old.reports_to_job_id,old.reference_profile_id,old.reviewer_mode,old.reviewer_override_reason) then
  if not private.can_job_stage('DRAFT') then raise exception 'صلاحية إعداد الوصف مطلوبة' using errcode='42501'; end if;
  if new.reviewer_mode='override' and (not private.is_admin() or char_length(btrim(coalesce(new.reviewer_override_reason,'')))<2) then
   raise exception 'تعيين البديل يتطلب مسؤول النظام وسببًا واضحًا' using errcode='42501';
  end if;
  if new.reports_to_job_id=new.id then raise exception 'لا يمكن أن تتبع الوظيفة نفسها'; end if;
 end if;
 if tg_op='UPDATE' then
  if old.final_reviewed_at is not null and new.status='MANAGER_APPROVED' and (new.title,new.purpose,new.content) is distinct from (old.title,old.purpose,old.content) and not private.employee_change_covers_job(new,old) then raise exception 'أعد الوصف للتعديل قبل تغيير محتوى تمت مراجعته نهائيًا'; end if;
  if old.status='PUBLISHED' and new.status='PUBLISHED' and (new.title,new.purpose,new.content) is distinct from (old.title,old.purpose,old.content) then
   raise exception 'افتح مسودة إصدار جديد قبل تعديل الوصف المنشور';
  end if;
  if new.status='IN_REVIEW' and old.status is distinct from new.status then
   new.reviewer_id:=private.resolve_job_direct_manager(new);
   new.submitted_at:=clock_timestamp();new.manager_approved_at:=null;new.manager_approved_by:=null;
  end if;
  if new.status='CHANGES_REQUESTED' and old.status is distinct from new.status and char_length(btrim(coalesce(new.review_note,'')))<2 then
   raise exception 'سبب الإعادة للتعديل مطلوب';
  end if;
 end if;
 return new;
end $function$
;

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

commit;

