begin;

-- امتياز قراءة تنفيذي مستقل عن دور مدير النظام.
create or replace function private.has_permission(p_permission text)
returns boolean language sql stable security definer
set search_path='pg_catalog','public','private'
as $$
  select coalesce(exists(
    select 1 from public.profiles p
    where p.id=(select auth.uid()) and p.active=true and p.status='active'
      and p_permission=any(coalesce(p.permissions,array[]::text[]))
  ),false)
$$;
revoke all on function private.has_permission(text) from public,anon;
grant execute on function private.has_permission(text) to authenticated;

alter policy tasks_select_policy on public.tasks using (
  private.can_view_task(id) or private.has_permission('tasks.read_all')
);
alter policy profiles_select_policy on public.profiles using (
  private.current_user_is_active()
  and (id=(select auth.uid()) or private.is_admin() or private.manages_user(id) or private.has_permission('tasks.read_all'))
);

create table if not exists public.executive_task_access_log(
  id bigint generated always as identity primary key,
  viewer_id uuid not null references public.profiles(id) on delete restrict,
  access_scope text not null default 'ALL_TASKS' check(access_scope='ALL_TASKS'),
  accessed_at timestamptz not null default now(),
  user_agent text
);
alter table public.executive_task_access_log enable row level security;
revoke all on table public.executive_task_access_log from public,anon,authenticated;
grant select on table public.executive_task_access_log to authenticated;
create policy executive_task_access_log_admin_select on public.executive_task_access_log
for select to authenticated using(private.is_admin());

create or replace function public.record_executive_task_access(p_user_agent text default null)
returns void language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
begin
  if not private.has_permission('tasks.read_all') then raise exception 'Executive read access is not granted' using errcode='42501'; end if;
  insert into public.executive_task_access_log(viewer_id,user_agent)
  values((select auth.uid()),nullif(left(coalesce(p_user_agent,''),500),''));
end $$;
revoke all on function public.record_executive_task_access(text) from public,anon;
grant execute on function public.record_executive_task_access(text) to authenticated;

create or replace function public.admin_set_executive_task_access(p_profile_id uuid,p_enabled boolean)
returns void language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
begin
  if not private.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  update public.profiles set permissions=case when p_enabled
    then array(select distinct x from unnest(coalesce(permissions,array[]::text[])||array['tasks.read_all']) x)
    else array_remove(coalesce(permissions,array[]::text[]),'tasks.read_all') end
  where id=p_profile_id;
  if not found then raise exception 'Profile not found'; end if;
end $$;
revoke all on function public.admin_set_executive_task_access(uuid,boolean) from public,anon;
grant execute on function public.admin_set_executive_task_access(uuid,boolean) to authenticated;

-- طلب إعادة الجدولة يحفظ التاريخ المقترح والسبب، ولا يغير المهمة إلا بعد قرار منشئها.
create table if not exists public.task_reschedule_requests(
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete restrict,
  task_creator_id uuid not null references public.profiles(id) on delete restrict,
  current_start_date date,
  current_due_date date,
  proposed_start_date date,
  proposed_due_date date,
  reason text not null,
  status text not null default 'PENDING' check(status in('PENDING','APPROVED','REJECTED','CANCELLED')),
  decided_by uuid references public.profiles(id) on delete set null,
  decision_note text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  constraint task_reschedule_dates_check check(proposed_due_date is null or proposed_start_date is null or proposed_due_date>=proposed_start_date),
  constraint task_reschedule_reason_check check(char_length(btrim(reason)) between 3 and 1000)
);
create unique index if not exists task_reschedule_one_pending_idx on public.task_reschedule_requests(task_id,requester_id) where status='PENDING';
create index if not exists task_reschedule_creator_idx on public.task_reschedule_requests(task_creator_id,status,created_at desc);
alter table public.task_reschedule_requests enable row level security;
revoke all on table public.task_reschedule_requests from public,anon,authenticated;
grant select on table public.task_reschedule_requests to authenticated;
create policy task_reschedule_select_policy on public.task_reschedule_requests for select to authenticated using(
  requester_id=(select auth.uid()) or task_creator_id=(select auth.uid()) or private.is_admin()
);

create or replace function public.request_task_reschedule(p_task_id uuid,p_start_date date,p_due_date date,p_reason text)
returns uuid language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare v_task public.tasks%rowtype; v_id uuid;
begin
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null;
  if not found or v_task.assignee_id<>(select auth.uid()) then raise exception 'Only the current assignee may request rescheduling' using errcode='42501'; end if;
  if v_task.status in('بانتظار الاعتماد','مكتملة') then raise exception 'This task cannot be rescheduled in its current status'; end if;
  if v_task.creator_id=(select auth.uid()) then raise exception 'The task creator can edit the schedule directly'; end if;
  insert into public.task_reschedule_requests(task_id,requester_id,task_creator_id,current_start_date,current_due_date,proposed_start_date,proposed_due_date,reason)
  values(v_task.id,(select auth.uid()),v_task.creator_id,v_task.start_date,v_task.due_date,p_start_date,p_due_date,btrim(p_reason))
  returning id into v_id;
  insert into public.notifications(recipient_id,type,title,message,task_id,created_at)
  values(v_task.creator_id,'TASK_RESCHEDULE_REQUEST','طلب إعادة جدولة',coalesce(v_task.assignee_name_snapshot,'الموظف')||' طلب إعادة جدولة: '||v_task.title,v_task.id,now());
  return v_id;
end $$;
revoke all on function public.request_task_reschedule(uuid,date,date,text) from public,anon;
grant execute on function public.request_task_reschedule(uuid,date,date,text) to authenticated;

create or replace function public.decide_task_reschedule(p_request_id uuid,p_approve boolean,p_note text default null)
returns void language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare v_request public.task_reschedule_requests%rowtype;
begin
  select * into v_request from public.task_reschedule_requests where id=p_request_id for update;
  if not found or v_request.status<>'PENDING' then raise exception 'Pending request not found'; end if;
  if v_request.task_creator_id<>(select auth.uid()) and not private.is_admin() then raise exception 'Only the task creator may decide' using errcode='42501'; end if;
  if p_approve then
    update public.tasks set start_date=v_request.proposed_start_date,due_date=v_request.proposed_due_date,revision=revision+1,updated_at=now() where id=v_request.task_id;
  end if;
  update public.task_reschedule_requests set status=case when p_approve then 'APPROVED' else 'REJECTED' end,decided_by=(select auth.uid()),decision_note=nullif(btrim(coalesce(p_note,'')),''),decided_at=now() where id=p_request_id;
  insert into public.notifications(recipient_id,type,title,message,task_id,created_at)
  values(v_request.requester_id,'TASK_RESCHEDULE_DECISION',case when p_approve then 'تمت الموافقة على إعادة الجدولة' else 'تم رفض إعادة الجدولة' end,coalesce(p_note,''),v_request.task_id,now());
end $$;
revoke all on function public.decide_task_reschedule(uuid,boolean,text) from public,anon;
grant execute on function public.decide_task_reschedule(uuid,boolean,text) to authenticated;

-- تفويض المهمة يحافظ على منشئها وتواريخها، ويغيّر المسؤول فقط داخل شجرة المدير.
create or replace function public.delegate_task_safe(p_task_id uuid,p_target_id uuid,p_expected_revision integer)
returns setof public.tasks language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare v_task public.tasks%rowtype;v_uid uuid:=(select auth.uid());v_name text;v_actor_name text;v_seq integer;
begin
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found then raise exception 'Task not found'; end if;
  if v_task.revision<>p_expected_revision then raise exception 'ATWAR_CONFLICT: task changed' using errcode='40001'; end if;
  if v_task.status in('بانتظار الاعتماد','مكتملة') then raise exception 'Task cannot be delegated in its current status'; end if;
  if not private.is_admin() and not(private.current_user_role()='manager' and v_task.assignee_id=v_uid and private.manages_user(p_target_id)) then
    raise exception 'Only the assigned manager may delegate to a subordinate' using errcode='42501';
  end if;
  select full_name into v_name from public.profiles where id=p_target_id and active=true and status='active';
  if not found then raise exception 'Active target employee not found'; end if;
  update public.tasks set assignee_id=p_target_id,assignee_name_snapshot=v_name,revision=revision+1,updated_at=now() where id=p_task_id;
  select full_name into v_actor_name from public.profiles where id=v_uid;
  v_seq:=private.next_task_activity_sequence(p_task_id);
  insert into public.task_activity(task_id,sequence_no,event_type,detail,actor_id,actor_name_snapshot,created_at,legacy_actor_firebase_uid)
  values(p_task_id,v_seq,'assigned','تم تفويض المهمة إلى '||v_name,v_uid,v_actor_name,now(),null);
  return query select * from public.tasks where id=p_task_id;
end $$;
revoke all on function public.delegate_task_safe(uuid,uuid,integer) from public,anon;
grant execute on function public.delegate_task_safe(uuid,uuid,integer) to authenticated;

-- يمكن لمسؤول النظام تعيين أي موظف نشط كمراجع، بما في ذلك شاغل الوظيفة نفسه.
drop policy if exists job_change_requests_insert_policy on public.job_description_change_requests;
create policy job_change_requests_insert_policy on public.job_description_change_requests
for insert to authenticated with check(
  manager_id=(select auth.uid())
  and exists(select 1 from public.job_descriptions j where j.id=job_description_id and j.reviewer_id=(select auth.uid()) and j.status in('IN_REVIEW','CHANGES_REQUESTED'))
);
create or replace function private.prepare_job_change_request()
returns trigger language plpgsql security invoker
set search_path='pg_catalog','public','private'
as $$
declare v_uid uuid:=(select auth.uid());
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  new.reason:=btrim(new.reason);
  if tg_op='INSERT' then
    if not exists(select 1 from public.job_descriptions j where j.id=new.job_description_id and j.reviewer_id=v_uid and j.status in('IN_REVIEW','CHANGES_REQUESTED')) then raise exception 'Only the assigned reviewer can create proposals'; end if;
    new.manager_id:=v_uid;new.status:='PENDING';new.created_at:=now();new.admin_decision_by:=null;new.admin_decision_at:=null;new.admin_note:=null;
  elsif private.job_library_role()<>'admin' then
    new.job_description_id:=old.job_description_id;new.section:=old.section;new.item_index:=old.item_index;new.action:=old.action;new.original_value:=old.original_value;new.manager_id:=old.manager_id;new.status:='PENDING';new.admin_decision_by:=null;new.admin_decision_at:=null;new.admin_note:=null;
  elsif new.status<>old.status and new.status<>'PENDING' then new.admin_decision_by:=v_uid;new.admin_decision_at:=now(); end if;
  new.updated_at:=now();return new;
end $$;

commit;
