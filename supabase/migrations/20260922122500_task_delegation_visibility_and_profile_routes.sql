begin;

alter table public.tasks
  add column if not exists delegated_by_id uuid references public.profiles(id) on delete restrict,
  add column if not exists delegated_by_name_snapshot text,
  add column if not exists delegated_at timestamptz;

create index if not exists tasks_delegated_by_id_idx
  on public.tasks(delegated_by_id) where delegated_by_id is not null and deleted_at is null;

create or replace function private.can_view_task(target_task uuid)
returns boolean language sql stable security definer
set search_path='pg_catalog','public','private'
as $$
  select private.current_user_is_active() and coalesce(exists(
    select 1 from public.tasks t
    where t.id=target_task and t.deleted_at is null and (
      t.creator_id=(select auth.uid())
      or t.assignee_id=(select auth.uid())
      or t.delegated_by_id=(select auth.uid())
      or private.is_admin()
      or private.manages_user(t.assignee_id)
    )
  ),false)
$$;
revoke all on function private.can_view_task(uuid) from public,anon;
grant execute on function private.can_view_task(uuid) to authenticated;

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
  select full_name into v_actor_name from public.profiles where id=v_uid;
  update public.tasks set assignee_id=p_target_id,assignee_name_snapshot=v_name,
    delegated_by_id=v_uid,delegated_by_name_snapshot=v_actor_name,delegated_at=now(),
    revision=revision+1,updated_at=now() where id=p_task_id;
  v_seq:=private.next_task_activity_sequence(p_task_id);
  insert into public.task_activity(task_id,sequence_no,event_type,detail,actor_id,actor_name_snapshot,created_at,legacy_actor_firebase_uid)
  values(p_task_id,v_seq,'delegated','تم تفويض المهمة من '||coalesce(v_actor_name,'المسؤول')||' إلى '||v_name,v_uid,v_actor_name,now(),null);
  insert into public.notifications(recipient_id,type,title,message,task_id,created_at)
  select recipient_id,'TASK_DELEGATED','تم تفويض مهمة',
    'فوّض '||coalesce(v_actor_name,'المسؤول')||' المهمة إلى '||v_name,p_task_id,now()
  from (values(v_task.creator_id),(v_uid),(p_target_id)) recipients(recipient_id)
  where recipient_id is not null
  group by recipient_id;
  return query select * from public.tasks where id=p_task_id;
end $$;
revoke all on function public.delegate_task_safe(uuid,uuid,integer) from public,anon;
grant execute on function public.delegate_task_safe(uuid,uuid,integer) to authenticated;

commit;
