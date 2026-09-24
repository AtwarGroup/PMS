-- Reassignment to the previous delegator ends the current delegation.
-- Admin reassignment on behalf of another user is an assignment, not a new
-- delegation by the admin. The historical activity rows remain intact.
create or replace function public.delegate_task_safe(p_task_id uuid,p_target_id uuid,p_expected_revision integer)
returns setof public.tasks language plpgsql security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_task public.tasks%rowtype;
  v_uid uuid := (select auth.uid());
  v_name text;
  v_actor_name text;
  v_seq integer;
  v_is_admin boolean;
  v_return boolean;
  v_delegation boolean;
  v_event text;
  v_detail text;
begin
  select * into v_task from public.tasks where id=p_task_id and deleted_at is null for update;
  if not found then raise exception 'Task not found'; end if;
  v_is_admin := private.is_admin();

  -- A repeated request after a successful transfer must not rewrite its history.
  if v_task.assignee_id=p_target_id and
     (v_is_admin or (private.current_user_role()='manager' and
       (v_uid=p_target_id or v_task.delegated_by_id=v_uid))) then
    return query select * from public.tasks where id=p_task_id;
    return;
  end if;

  if v_task.revision<>p_expected_revision then raise exception 'ATWAR_CONFLICT: task changed' using errcode='40001'; end if;
  if v_task.status in('بانتظار الاعتماد','مكتملة') then raise exception 'Task cannot be reassigned in its current status'; end if;
  v_return := v_task.delegated_by_id=p_target_id;
  if not v_is_admin and not (
    private.current_user_role()='manager' and
    ((v_task.assignee_id=v_uid and private.manages_user(p_target_id)) or
     (v_return and v_uid=p_target_id and private.manages_user(v_task.assignee_id)))
  ) then raise exception 'Only the assigned manager may delegate, or reclaim a task delegated to a subordinate' using errcode='42501'; end if;

  select full_name into v_name from public.profiles where id=p_target_id and active=true and status='active';
  if not found then raise exception 'Active target employee not found'; end if;
  select full_name into v_actor_name from public.profiles where id=v_uid;
  v_delegation := not v_return and v_task.assignee_id=v_uid;

  update public.tasks set
    assignee_id=p_target_id,assignee_name_snapshot=v_name,
    delegated_by_id=case when v_delegation then v_uid else null end,
    delegated_by_name_snapshot=case when v_delegation then v_actor_name else null end,
    delegated_at=case when v_delegation then now() else null end,
    revision=revision+1,updated_at=now()
  where id=p_task_id;

  -- Superseded delegation alerts should disappear when ownership changes.
  -- The task activity log keeps the history; only actionable alerts are removed.
  delete from public.notifications
  where task_id=p_task_id and
    (type='TASK_DELEGATED' or (type='assigned' and recipient_id=v_task.assignee_id));

  v_event := case when v_return then 'reclaimed' when v_delegation then 'delegated' else 'assigned' end;
  v_detail := case when v_return then 'تمت إعادة المهمة إلى '||v_name
                   when v_delegation then 'تم تفويض المهمة من '||coalesce(v_actor_name,'المسؤول')||' إلى '||v_name
                   else 'تم إسناد المهمة إلى '||v_name end;
  v_seq:=private.next_task_activity_sequence(p_task_id);
  insert into public.task_activity(task_id,sequence_no,event_type,detail,actor_id,actor_name_snapshot,created_at,legacy_actor_firebase_uid)
  values(p_task_id,v_seq,v_event,v_detail,v_uid,v_actor_name,now(),null);
  insert into public.notifications(recipient_id,type,title,message,task_id,created_at)
  select recipient_id,
    case when v_return then 'TASK_RECLAIMED' when v_delegation then 'TASK_DELEGATED' else 'TASK_ASSIGNED' end,
    case when v_return then 'تمت إعادة المهمة' when v_delegation then 'تم تفويض مهمة' else 'تم إسناد مهمة' end,
    v_detail,p_task_id,now()
  from (values(v_task.creator_id),(v_task.assignee_id),(p_target_id)) recipients(recipient_id)
  where recipient_id is not null
  group by recipient_id;
  return query select * from public.tasks where id=p_task_id;
end $function$;

revoke all on function public.delegate_task_safe(uuid,uuid,integer) from public,anon;
grant execute on function public.delegate_task_safe(uuid,uuid,integer) to authenticated;
