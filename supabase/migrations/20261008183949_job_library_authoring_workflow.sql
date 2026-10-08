begin;
-- Additive: published snapshots, historical approvals and in-flight reviews stay intact.
alter table public.job_descriptions
 add column reports_to_job_id uuid references public.job_descriptions(id),
 add column reference_profile_id uuid references public.profiles(id),
 add column reviewer_mode text not null default 'legacy' check(reviewer_mode in ('legacy','auto','override')),
 add column reviewer_override_reason text;
create index job_descriptions_reports_to_job_idx on public.job_descriptions(reports_to_job_id);
create index job_descriptions_reference_profile_idx on public.job_descriptions(reference_profile_id);

-- Narrow organizational lookup needs privileged visibility across employee assignments.
create function private.resolve_job_direct_manager(p_job public.job_descriptions)
returns uuid language plpgsql stable security definer set search_path='pg_catalog','public','private' as $$
declare ids uuid[]; missing integer; candidate uuid;
begin
 if not private.can_job_stage('DRAFT') then raise exception 'صلاحية إعداد الوصف مطلوبة' using errcode='42501'; end if;
 if p_job.reviewer_mode in ('legacy','override') and p_job.reviewer_id is not null then
  candidate:=p_job.reviewer_id;
 else
  select array_agg(distinct p.manager_id) filter(where p.manager_id is not null),count(*) filter(where p.manager_id is null)
   into ids,missing from public.employee_job_assignments a join public.profiles p on p.id=a.profile_id
   where a.job_description_id=p_job.id and p.active=true and p.status='active';
  if coalesce(missing,0)>0 then raise exception 'يوجد موظف دون مدير مباشر؛ عالج المرجعية أو عيّن بديلًا مع السبب'; end if;
  if coalesce(cardinality(ids),0)=0 and p_job.reference_profile_id is not null then
   select array[p.manager_id] into ids from public.profiles p where p.id=p_job.reference_profile_id and p.active=true and p.status='active' and p.manager_id is not null;
  end if;
  if coalesce(cardinality(ids),0)=0 and p_job.reports_to_job_id is not null then
   select array_agg(distinct p.id) into ids from public.employee_job_assignments a join public.profiles p on p.id=a.profile_id
    where a.job_description_id=p_job.reports_to_job_id and p.active=true and p.status='active';
  end if;
  if coalesce(cardinality(ids),0)<>1 then raise exception 'تعذر تحديد مدير مباشر واحد. راجع الهيكل التنظيمي أو عيّن بديلًا مع السبب'; end if;
  candidate:=ids[1];
 end if;
 if not exists(select 1 from public.profiles where id=candidate and active=true and status='active') then raise exception 'حساب المدير المباشر غير نشط'; end if;
 return candidate;
end $$;
revoke all on function private.resolve_job_direct_manager(public.job_descriptions) from public,anon;
grant execute on function private.resolve_job_direct_manager(public.job_descriptions) to authenticated;

create function private.guard_job_authoring()
returns trigger language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
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
  if old.final_reviewed_at is not null and new.status='MANAGER_APPROVED' and (new.title,new.purpose,new.content) is distinct from (old.title,old.purpose,old.content) then raise exception 'أعد الوصف للتعديل قبل تغيير محتوى تمت مراجعته نهائيًا'; end if;
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
end $$;
revoke all on function private.guard_job_authoring() from public,anon,authenticated;
create trigger z_guard_job_authoring before insert or update on public.job_descriptions for each row execute function private.guard_job_authoring();

create function public.create_job_description_draft(p_request_id uuid,p_payload jsonb)
returns public.job_descriptions language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
declare j public.job_descriptions%rowtype; code_number integer;
begin
 if not private.can_job_stage('DRAFT') then raise exception 'صلاحية إعداد الوصف مطلوبة' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(61920854);
 select * into j from public.job_descriptions where id=p_request_id;
 if found then
  if j.created_by is distinct from (select auth.uid()) then raise exception 'طلب الإنشاء مستخدم' using errcode='42501'; end if;
  return j;
 end if;
 if char_length(btrim(coalesce(p_payload->>'title','')))<2 then raise exception 'المسمى الوظيفي مطلوب'; end if;
 select coalesce(max(substring(job_code from 5)::integer),0)+1 into code_number from public.job_descriptions;
 insert into public.job_descriptions(id,job_code,title,family,job_level,reports_to_title,purpose,content,reviewer_id,reviewer_mode,reviewer_override_reason,reports_to_job_id,reference_profile_id,created_by,updated_by)
 values(p_request_id,'JOB-'||case when code_number<1000 then lpad(code_number::text,3,'0') else code_number::text end,
 btrim(p_payload->>'title'),p_payload->>'family',p_payload->>'job_level',p_payload->>'reports_to_title',coalesce(p_payload->>'purpose',''),coalesce(p_payload->'content','{}'),
 nullif(p_payload->>'reviewer_id','')::uuid,coalesce(p_payload->>'reviewer_mode','auto'),p_payload->>'reviewer_override_reason',nullif(p_payload->>'reports_to_job_id','')::uuid,nullif(p_payload->>'reference_profile_id','')::uuid,(select auth.uid()),(select auth.uid())) returning * into j;
 return j;
end $$;
revoke all on function public.create_job_description_draft(uuid,jsonb) from public,anon;
grant execute on function public.create_job_description_draft(uuid,jsonb) to authenticated;

create function public.save_job_description_draft(p_job_id uuid,p_expected_revision integer,p_payload jsonb)
returns public.job_descriptions language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
declare j public.job_descriptions%rowtype;
begin
 if not private.can_job_stage('DRAFT') then raise exception 'صلاحية إعداد الوصف مطلوبة' using errcode='42501'; end if;
 select * into j from public.job_descriptions where id=p_job_id for update;
 if not found then raise exception 'الوصف غير متاح'; end if;
 if j.revision<>p_expected_revision then raise exception 'عدّل مستخدم آخر الوصف. أعد تحميل النسخة قبل الحفظ' using errcode='40001'; end if;
 if j.status not in ('DRAFT','CHANGES_REQUESTED','PUBLISHED') then raise exception 'أعد الوصف للتعديل قبل تغيير محتواه'; end if;
 if char_length(btrim(coalesce(p_payload->>'title','')))<2 then raise exception 'المسمى الوظيفي مطلوب'; end if;
 update public.job_descriptions set title=p_payload->>'title',family=p_payload->>'family',job_level=p_payload->>'job_level',reports_to_title=p_payload->>'reports_to_title',purpose=coalesce(p_payload->>'purpose',''),content=coalesce(p_payload->'content','{}'),
 reviewer_mode=coalesce(p_payload->>'reviewer_mode',j.reviewer_mode),reviewer_id=case when p_payload->>'reviewer_mode'='override' then nullif(p_payload->>'reviewer_id','')::uuid else j.reviewer_id end,
 reviewer_override_reason=p_payload->>'reviewer_override_reason',reports_to_job_id=nullif(p_payload->>'reports_to_job_id','')::uuid,reference_profile_id=nullif(p_payload->>'reference_profile_id','')::uuid,
 status=case when j.status='PUBLISHED' then 'DRAFT' else j.status end where id=p_job_id returning * into j;
 return j;
end $$;
revoke all on function public.save_job_description_draft(uuid,integer,jsonb) from public,anon;
grant execute on function public.save_job_description_draft(uuid,integer,jsonb) to authenticated;

create function public.submit_job_description_draft(p_job_id uuid,p_expected_revision integer)
returns public.job_descriptions language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
declare j public.job_descriptions%rowtype; k jsonb; total numeric:=0;
begin
 if not private.can_job_stage('DRAFT') then raise exception 'صلاحية إعداد الوصف مطلوبة' using errcode='42501'; end if;
 select * into j from public.job_descriptions where id=p_job_id for update;
 if not found or j.status not in ('DRAFT','CHANGES_REQUESTED') then raise exception 'الوصف ليس مسودة قابلة للإرسال'; end if;
 if j.revision<>p_expected_revision then raise exception 'عدّل مستخدم آخر الوصف. أعد تحميل النسخة' using errcode='40001'; end if;
 if char_length(btrim(j.purpose))<40 or jsonb_array_length(coalesce(j.content->'responsibilities','[]'))=0
  or jsonb_array_length(coalesce(j.content->'authorities','[]'))=0 or jsonb_array_length(coalesce(j.content->'kpis','[]'))=0
  or jsonb_array_length(coalesce(j.content->'reports','[]'))=0 or nullif(btrim(j.content#>>'{qualifications,education}'),'') is null then
  raise exception 'أكمل الغرض والمهام والصلاحيات والمؤشرات والمخرجات والمؤهلات قبل الإرسال'; end if;
 if j.reviewer_mode<>'legacy' then
  for k in select value from jsonb_array_elements(j.content->'kpis') loop
   if nullif(btrim(k->>'name'),'') is null or nullif(btrim(k->>'measure'),'') is null or nullif(btrim(k->>'source'),'') is null or nullif(btrim(k->>'target'),'') is null or coalesce(k->>'weight','')!~'^[0-9]+(\.[0-9]+)?$' then
    raise exception 'أكمل اسم وطريقة قياس ومصدر ومستهدف ووزن كل مؤشر'; end if;
   if (k->>'weight')::numeric<=0 then raise exception 'وزن المؤشر يجب أن يكون موجبًا'; end if;
   total:=total+(k->>'weight')::numeric;
  end loop;
  if abs(total-100)>0.001 then raise exception 'مجموع أوزان المؤشرات يجب أن يساوي ١٠٠٪'; end if;
 end if;
 update public.job_descriptions set status='IN_REVIEW' where id=p_job_id returning * into j;
 return j;
end $$;
revoke all on function public.submit_job_description_draft(uuid,integer) from public,anon;
grant execute on function public.submit_job_description_draft(uuid,integer) to authenticated;

create function public.return_job_description_for_changes(p_job_id uuid,p_expected_revision integer,p_reason text)
returns public.job_descriptions language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare j public.job_descriptions%rowtype;
begin
 if not private.current_user_is_active() then raise exception 'حساب نشط مطلوب' using errcode='42501'; end if;
 select * into j from public.job_descriptions where id=p_job_id for update;
 if not found then raise exception 'الوصف غير متاح'; end if;
 if not ((j.status='IN_REVIEW' and j.reviewer_id=(select auth.uid())) or (j.status='MANAGER_APPROVED' and (private.can_job_stage('FINAL_REVIEW') or private.can_job_stage('PUBLISH')))) then
  raise exception 'لا تملك صلاحية إعادة هذا الوصف' using errcode='42501'; end if;
 if j.revision<>p_expected_revision then raise exception 'عدّل مستخدم آخر الوصف. أعد تحميل النسخة' using errcode='40001'; end if;
 if char_length(btrim(coalesce(p_reason,'')))<2 then raise exception 'سبب الإعادة مطلوب'; end if;
 update public.job_descriptions set status='CHANGES_REQUESTED',review_note=btrim(p_reason),final_reviewed_at=null,final_reviewed_by=null where id=p_job_id returning * into j;
 return j;
end $$;
revoke all on function public.return_job_description_for_changes(uuid,integer,text) from public,anon;
grant execute on function public.return_job_description_for_changes(uuid,integer,text) to authenticated;

alter table private.job_workflow_tasks drop constraint job_workflow_tasks_phase_check;
alter table private.job_workflow_tasks add constraint job_workflow_tasks_phase_check check(phase in ('MANAGER_REVIEW','ADMIN_APPROVAL','PUBLISH','EMPLOYEE_ACK','DRAFT_REVISION'));
-- Change only the returned-to-draft branch; no backfill or reset of current tasks.
do $$
declare d text;
begin
 select pg_get_functiondef('private.sync_job_workflow_tasks()'::regprocedure) into d;
 d:=replace(d,'if new.status in (''IN_REVIEW'',''CHANGES_REQUESTED'') then',
 'if new.status=''CHANGES_REQUESTED'' then
 perform private.close_job_workflow_tasks(new.id,''MANAGER_REVIEW'');
 perform private.close_job_workflow_tasks(new.id,''ADMIN_APPROVAL'');
 perform private.ensure_job_workflow_task(new,''DRAFT_REVISION'',new.revision::text,private.job_stage_owner(''DRAFT''));
 elsif new.status=''IN_REVIEW'' then
 perform private.close_job_workflow_tasks(new.id,''DRAFT_REVISION'');');
 execute d;
 select pg_get_functiondef('private.prepare_job_description()'::regprocedure) into d;
 d:=replace(d,'and v_final and old.status in (''IN_REVIEW'',''MANAGER_APPROVED'')','and (v_final or v_publish) and old.status in (''IN_REVIEW'',''MANAGER_APPROVED'')');
 execute d;
end $$;

create function public.decide_job_description_proposal(p_proposal_id uuid,p_expected_revision integer,p_decision text,p_value jsonb default null,p_note text default null)
returns public.job_descriptions language plpgsql security invoker set search_path='pg_catalog','public','private' as $$
declare r public.job_description_change_requests%rowtype; j public.job_descriptions%rowtype; v_content jsonb; rows jsonb; value jsonb; key text; idx integer; matches integer;
begin
 if not private.can_job_stage('FINAL_REVIEW') then raise exception 'صلاحية المراجعة النهائية مطلوبة' using errcode='42501'; end if;
 select * into r from public.job_description_change_requests where id=p_proposal_id;
 if not found then raise exception 'المقترح غير متاح'; end if;
 select * into j from public.job_descriptions where id=r.job_description_id for update;
 select * into r from public.job_description_change_requests where id=p_proposal_id for update;
 if j.status<>'MANAGER_APPROVED' or j.final_reviewed_at is not null then raise exception 'هذه النسخة ليست مفتوحة لمراجعة المقترحات'; end if;
 if r.status<>'PENDING' then return j; end if;
 if j.revision<>p_expected_revision then raise exception 'عدّل مستخدم آخر الوصف. أعد تحميل النسخة' using errcode='40001'; end if;
 if p_decision not in ('ACCEPTED','REVISED','REJECTED') then raise exception 'قرار غير صالح'; end if;
 if p_decision='REJECTED' and char_length(btrim(coalesce(p_note,'')))<2 then raise exception 'سبب الرفض مطلوب'; end if;
 value:=case when p_decision='REVISED' then p_value else r.proposed_value end;
 if p_decision<>'REJECTED' and r.action<>'COMMENT' then
  if r.action not in ('DELETE') and (value is null or value='null'::jsonb) then raise exception 'محتوى المقترح مطلوب'; end if;
  if r.section='PURPOSE' then
   if to_jsonb(j.purpose) is distinct from r.original_value then raise exception 'تغير النص الأصلي؛ راجع المقترح قبل تطبيقه'; end if;
   update public.job_descriptions set purpose=case when r.action='DELETE' then '' else value#>>'{}' end where id=j.id returning * into j;
  else
   key:=case r.section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' when 'REPORTS' then 'reports' end;
   if key is null then raise exception 'راجع المؤهلات في نموذج الإعداد ثم احسم المقترح'; end if;
   v_content:=j.content;rows:=coalesce(v_content->key,'[]');
   if r.action='ADD' then rows:=rows||jsonb_build_array(value);
   else
    select min(ord-1)::integer,count(*) into idx,matches from jsonb_array_elements(rows) with ordinality as x(v,ord) where v=r.original_value;
    if matches<>1 then raise exception 'تغير البند الأصلي أو تكرر؛ راجع المقترح قبل تطبيقه'; end if;
    if r.action='DELETE' then rows:=rows-idx;else rows:=jsonb_set(rows,array[idx::text],value);end if;
   end if;
   v_content:=jsonb_set(v_content,array[key],rows);
   update public.job_descriptions set content=v_content where id=j.id returning * into j;
  end if;
 end if;
 update public.job_description_change_requests set status=p_decision,proposed_value=value,admin_note=p_note where id=r.id;
 return j;
end $$;
revoke all on function public.decide_job_description_proposal(uuid,integer,text,jsonb,text) from public,anon;
grant execute on function public.decide_job_description_proposal(uuid,integer,text,jsonb,text) to authenticated;

create function private.label_job_revision_task()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare j public.job_descriptions%rowtype;
begin
 if new.task_type='job_workflow' and new.legacy_metadata#>>'{job_workflow,phase}'='DRAFT_REVISION' then
  select * into j from public.job_descriptions where id=(new.legacy_metadata#>>'{job_workflow,job_id}')::uuid;
  new.title:='تعديل الوصف الوظيفي: '||j.title;new.description:='أعيد الوصف للتعديل. السبب: '||coalesce(j.review_note,'');
 end if;return new;
end $$;
revoke all on function private.label_job_revision_task() from public,anon,authenticated;
create trigger label_job_revision_task before insert on public.tasks for each row execute function private.label_job_revision_task();
commit;
