begin;
create table public.employee_job_change_requests (
 id uuid primary key default gen_random_uuid(), client_key uuid not null,
 job_description_id uuid not null references public.job_descriptions(id),
 requester_name text not null, job_title text not null,
 requester_id uuid not null references public.profiles(id), manager_id uuid references public.profiles(id),
 admin_id uuid not null references public.profiles(id), published_revision integer not null,
 section text not null check(section in ('PURPOSE','RESPONSIBILITIES','AUTHORITIES','KPIS','REPORTS')),
 action text not null check(action in ('ADD','MODIFY','DELETE')), item_index integer,
 original_value jsonb, proposed_value jsonb, reason text not null check(char_length(reason) between 2 and 2000),
 status text not null check(status in ('MANAGER_REVIEW','ADMIN_REVIEW','APPLIED','PUBLISHED','REJECTED','STALE')),
 manager_note text, admin_note text, manager_decided_at timestamptz, admin_decided_at timestamptz,
 applied_revision integer, published_result_revision integer,
 manager_task_id uuid references public.tasks(id), admin_task_id uuid references public.tasks(id),
 version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(requester_id,client_key)
);
create index employee_job_changes_manager_idx on public.employee_job_change_requests(manager_id,status);
create index employee_job_changes_admin_idx on public.employee_job_change_requests(admin_id,status);
create index employee_job_changes_manager_task_idx on public.employee_job_change_requests(manager_task_id);
create index employee_job_changes_admin_task_idx on public.employee_job_change_requests(admin_task_id);
create index employee_job_changes_job_idx on public.employee_job_change_requests(job_description_id,status);
alter table public.employee_job_change_requests enable row level security;
revoke all on public.employee_job_change_requests from public,anon,authenticated;
grant select on public.employee_job_change_requests to authenticated;
create policy employee_job_changes_read on public.employee_job_change_requests for select to authenticated
 using(private.current_user_is_active() and (requester_id=(select auth.uid()) or manager_id=(select auth.uid()) or admin_id=(select auth.uid()) or private.is_admin()));

-- Internal trigger owns tasks; clients cannot create or close these tasks manually.
create function private.sync_employee_job_change_tasks() returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
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
  values(left(case when new.status='MANAGER_REVIEW' then 'مراجعة اقتراح الموظف: ' else 'اعتماد ونشر اقتراح الموظف: ' end||jtitle,200),
   'الموظف: '||employee||E'\nالسبب: '||new.reason||E'\nافتح طلب تعديل الوصف للاطلاع على البند والاقتراح واتخاذ القرار. تُغلق المهمة آليًا؛ مهمة الاعتماد تبقى حتى نشر النسخة.',
   'job_workflow',new.requester_id,recipient,employee,target,'قيد الانتظار','normal',0,current_date,
   jsonb_build_object('job_workflow',jsonb_build_object('job_id',new.job_description_id,'phase',phase,'request_id',new.id))) returning id into t;
  if new.status='MANAGER_REVIEW' then update public.employee_job_change_requests set manager_task_id=t where id=new.id;
  else update public.employee_job_change_requests set admin_task_id=t where id=new.id; end if;
 end if;
 if tg_op='UPDATE' then
  insert into public.notifications(recipient_id,task_id,type,title,message)
   values(new.requester_id,coalesce(new.admin_task_id,new.manager_task_id),'job_change_decision','تحديث طلب تعديل الوصف الوظيفي',
    case new.status when 'ADMIN_REVIEW' then 'أيد المدير اقتراحك وأرسله إلى مدير النظام.' when 'APPLIED' then 'اعتمد اقتراحك وأُضيف إلى المسودة؛ بانتظار النشر.' when 'PUBLISHED' then 'نُشر الإصدار الجديد؛ راجع وصفك وسجل الإقرار الجديد.' when 'STALE' then 'تغير البند أثناء المراجعة؛ راجع ملاحظة القرار.' else 'رُفض الطلب: '||coalesce(new.admin_note,new.manager_note,'') end);
 end if;
 return new;
end $$;
revoke all on function private.sync_employee_job_change_tasks() from public,anon,authenticated;
create trigger employee_job_change_tasks after insert or update of status on public.employee_job_change_requests
for each row execute function private.sync_employee_job_change_tasks();

create function private.submit_employee_job_change(p_job_id uuid,p_revision integer,p_section text,p_action text,p_index integer,p_text text,p_reason text,p_client_key uuid)
returns uuid language plpgsql security definer set search_path='pg_catalog','public','private' as $$
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
 select manager_id into mgr from public.profiles where id=auth.uid();
 if mgr=auth.uid() or not exists(select 1 from public.profiles where id=mgr and active=true and status='active') then mgr:=null; end if;
 select p.id into adm from public.profiles p where p.role='admin' and p.active=true and p.status='active'
 order by (p.id=private.job_stage_owner('FINAL_REVIEW')) desc,p.id limit 1;
 if adm is null then raise exception 'No active system administrator'; end if;
 insert into public.employee_job_change_requests(client_key,job_description_id,requester_name,job_title,requester_id,manager_id,admin_id,published_revision,section,action,item_index,original_value,proposed_value,reason,status)
 values(p_client_key,j.id,(select full_name from public.profiles where id=auth.uid()),j.title,auth.uid(),mgr,adm,p_revision,p_section,p_action,case when p_action='ADD' then null else p_index end,original,proposed,btrim(p_reason),case when mgr is null then 'ADMIN_REVIEW' else 'MANAGER_REVIEW' end)
 on conflict(requester_id,client_key) do nothing returning id into r;
 if r is null then select id into r from public.employee_job_change_requests where requester_id=auth.uid() and client_key=p_client_key; end if;
 return r;
end $$;
revoke all on function private.submit_employee_job_change(uuid,integer,text,text,integer,text,text,uuid) from public,anon;
grant execute on function private.submit_employee_job_change(uuid,integer,text,text,integer,text,text,uuid) to authenticated;

create function private.decide_employee_job_change(p_request_id uuid,p_version integer,p_approve boolean,p_note text)
returns text language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare r public.employee_job_change_requests%rowtype; j public.job_descriptions%rowtype; k text; rows jsonb; c jsonb; newrev integer;
begin
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into r from public.employee_job_change_requests where id=p_request_id for update;
 if not found then raise exception 'Request not found'; end if;
 if p_approve is null then raise exception 'Decision required'; end if;
 if p_version is null or r.version<>p_version then raise exception 'ATWAR_CONFLICT: request changed'; end if;
 if char_length(btrim(coalesce(p_note,''))) not between 2 and 2000 then raise exception 'Decision note required'; end if;
 if r.status='MANAGER_REVIEW' then
  if auth.uid()<>r.manager_id then raise exception 'Assigned manager required' using errcode='42501'; end if;
  update public.employee_job_change_requests set status=case when p_approve then 'ADMIN_REVIEW' else 'REJECTED' end,manager_note=btrim(p_note),manager_decided_at=now(),version=version+1,updated_at=now() where id=r.id;
  return case when p_approve then 'ADMIN_REVIEW' else 'REJECTED' end;
 end if;
 if r.status<>'ADMIN_REVIEW' or not private.is_admin() then raise exception 'System administrator review required' using errcode='42501'; end if;
 if not p_approve then
  update public.employee_job_change_requests set status='REJECTED',admin_note=btrim(p_note),admin_decided_at=now(),version=version+1,updated_at=now() where id=r.id;return 'REJECTED';
 end if;
 select * into j from public.job_descriptions where id=r.job_description_id for update;
 if j.status not in ('PUBLISHED','DRAFT') then raise exception 'Finish the current job review before applying this proposal'; end if;
 if (j.published_snapshot->>'revision')::integer<>r.published_revision then raise exception 'ATWAR_CONFLICT: published revision changed'; end if;
 c:=j.content;
 if r.section='PURPOSE' then
  if to_jsonb(j.purpose) is distinct from r.original_value then raise exception 'ATWAR_CONFLICT: purpose changed'; end if;
  update public.job_descriptions set purpose=r.proposed_value#>>'{}',status='DRAFT' where id=j.id returning revision into newrev;
 else
  k:=case r.section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;
  rows:=coalesce(c->k,'[]'::jsonb);
  if r.action<>'ADD' and (rows->r.item_index) is distinct from r.original_value then raise exception 'ATWAR_CONFLICT: item changed'; end if;
  if r.action='ADD' then rows:=rows||jsonb_build_array(r.proposed_value);
  elsif r.action='DELETE' then rows:=rows-r.item_index;
  else rows:=jsonb_set(rows,array[r.item_index::text],r.proposed_value);end if;
  c:=jsonb_set(c,array[k],rows);
  update public.job_descriptions set content=c,status='DRAFT' where id=j.id returning revision into newrev;
 end if;
 update public.employee_job_change_requests set status='APPLIED',admin_note=btrim(p_note),admin_decided_at=now(),applied_revision=newrev,version=version+1,updated_at=now() where id=r.id;
 return 'APPLIED';
end $$;
revoke all on function private.decide_employee_job_change(uuid,integer,boolean,text) from public,anon;
grant execute on function private.decide_employee_job_change(uuid,integer,boolean,text) to authenticated;

create function private.publish_employee_job_changes() returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare r public.employee_job_change_requests%rowtype; k text; rows jsonb; matches boolean;
begin
 if new.status<>'PUBLISHED' or new.published_snapshot is not distinct from old.published_snapshot then return new; end if;
 for r in select * from public.employee_job_change_requests where job_description_id=new.id and status='APPLIED' for update loop
  if r.section='PURPOSE' then matches:=new.published_snapshot->'purpose'=r.proposed_value;
  else
   k:=case r.section when 'RESPONSIBILITIES' then 'responsibilities' when 'AUTHORITIES' then 'authorities' when 'KPIS' then 'kpis' else 'reports' end;
   rows:=coalesce(new.published_snapshot->'content'->k,'[]'::jsonb);
   if r.action='DELETE' then matches:=not rows @> jsonb_build_array(r.original_value);
   else matches:=rows @> jsonb_build_array(r.proposed_value);end if;
  end if;
  if matches and (exists(select 1 from public.employee_job_assignments where profile_id=r.requester_id and job_description_id=new.id) or exists(select 1 from public.profiles where id=r.requester_id and job_description_id=new.id)) then
   perform private.ensure_job_workflow_task(new,'EMPLOYEE_ACK',new.published_snapshot->>'revision',r.requester_id);
  end if;
  update public.employee_job_change_requests set status=case when matches then 'PUBLISHED' else 'STALE' end,
   published_result_revision=(new.published_snapshot->>'revision')::integer,
   admin_note=case when matches then admin_note else coalesce(admin_note,'')||' — لم يتضمن الإصدار المنشور البند المقترح كما اعتمد؛ يلزم اقتراح جديد.' end,
   version=version+1,updated_at=now() where id=r.id;
 end loop;
 return new;
end $$;
revoke all on function private.publish_employee_job_changes() from public,anon,authenticated;
create trigger employee_job_changes_published after update of status,published_snapshot on public.job_descriptions
for each row execute function private.publish_employee_job_changes();
-- Invoker API wrappers expose only the guarded operations, not privileged bodies.
create function public.submit_employee_job_change(p_job_id uuid,p_revision integer,p_section text,p_action text,p_index integer,p_text text,p_reason text,p_client_key uuid)
returns uuid language sql security invoker set search_path='pg_catalog','private' as $$
 select private.submit_employee_job_change(p_job_id,p_revision,p_section,p_action,p_index,p_text,p_reason,p_client_key)
$$;
create function public.decide_employee_job_change(p_request_id uuid,p_version integer,p_approve boolean,p_note text)
returns text language sql security invoker set search_path='pg_catalog','private' as $$
 select private.decide_employee_job_change(p_request_id,p_version,p_approve,p_note)
$$;
revoke all on function public.submit_employee_job_change(uuid,integer,text,text,integer,text,text,uuid) from public,anon;
revoke all on function public.decide_employee_job_change(uuid,integer,boolean,text) from public,anon;
grant execute on function public.submit_employee_job_change(uuid,integer,text,text,integer,text,text,uuid) to authenticated;
grant execute on function public.decide_employee_job_change(uuid,integer,boolean,text) to authenticated;
commit;
