begin;

create or replace function private.enforce_task_delete_ownership()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_role text;
  v_task public.tasks%rowtype;
begin
  if tg_op = 'UPDATE' then
    if old.deleted_at is not null or new.deleted_at is null then
      return new;
    end if;
    v_task := old;
  else
    v_task := old;
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id = v_uid and p.active = true and p.status = 'active';

  if v_role = 'admin' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_uid is not null
     and v_task.creator_id = v_uid
     and v_task.status <> 'مكتملة' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  raise exception 'ATWAR_DELETE_FORBIDDEN: only admin or the creator of a non-completed task may delete it'
    using errcode = '42501';
end;
$$;

revoke all on function private.enforce_task_delete_ownership() from public, anon, authenticated;

create or replace function private.can_delete_task(target_task uuid)
returns boolean
language sql
stable
security definer
set search_path = 'pg_catalog', 'public'
as $$
  select exists (
    select 1
    from public.tasks t
    where t.id = target_task
      and private.current_user_is_active()
      and (
        private.is_admin()
        or (t.creator_id = (select auth.uid()) and t.status <> 'مكتملة')
      )
  );
$$;

revoke all on function private.can_delete_task(uuid) from public, anon;
grant execute on function private.can_delete_task(uuid) to authenticated;

create or replace function public.delete_task_safe(p_task_id uuid,p_reason text default null)
returns void
language plpgsql
security definer
set search_path = 'public', 'private', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_role text;
  v_active boolean;
  v_task public.tasks%rowtype;
  v_name text;
  v_seq integer;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;

  select role,coalesce(active,true) and coalesce(status,'active')='active',full_name
    into v_role,v_active,v_name
  from public.profiles
  where id=v_actor;

  if not coalesce(v_active,false) then raise exception 'Inactive user'; end if;
  if v_role not in ('employee','manager','admin') then raise exception 'Invalid user role'; end if;

  select * into v_task from public.tasks where id=p_task_id for update;
  if not found or v_task.deleted_at is not null then raise exception 'Task not found'; end if;

  if v_role<>'admin' and (v_task.creator_id<>v_actor or v_task.status='مكتملة') then
    raise exception 'ATWAR_DELETE_FORBIDDEN: only admin or the creator of a non-completed task may delete it'
      using errcode='42501';
  end if;

  perform set_config('app.soft_delete_mode','on',true);
  update public.tasks
  set deleted_at=now(),deleted_by=v_actor,delete_reason=nullif(btrim(coalesce(p_reason,'')),'')
  where id=p_task_id;

  v_seq:=private.next_task_activity_sequence(p_task_id);
  insert into public.task_activity(task_id,sequence_no,event_type,actor_id,actor_name_snapshot,detail,created_at,legacy_actor_firebase_uid)
  values(p_task_id,v_seq,'deleted',v_actor,v_name,'تم حذف المهمة من العرض التشغيلي (حذف آمن)',now(),null);

  insert into public.admin_audit_log(actor_id,actor_name_snapshot,action,target_type,target_id,detail)
  values(v_actor,v_name,'TASK_SOFT_DELETE','task',p_task_id::text,jsonb_build_object('reason',p_reason,'title',v_task.title));
end;
$$;

revoke all on function public.delete_task_safe(uuid,text) from public, anon;
grant execute on function public.delete_task_safe(uuid,text) to authenticated;

drop trigger if exists enforce_task_delete_ownership_before_update on public.tasks;
create trigger enforce_task_delete_ownership_before_update
before update of deleted_at on public.tasks
for each row execute function private.enforce_task_delete_ownership();

drop trigger if exists enforce_task_delete_ownership_before_delete on public.tasks;
create trigger enforce_task_delete_ownership_before_delete
before delete on public.tasks
for each row execute function private.enforce_task_delete_ownership();

commit;
