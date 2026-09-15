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

drop trigger if exists enforce_task_delete_ownership_before_update on public.tasks;
create trigger enforce_task_delete_ownership_before_update
before update of deleted_at on public.tasks
for each row execute function private.enforce_task_delete_ownership();

drop trigger if exists enforce_task_delete_ownership_before_delete on public.tasks;
create trigger enforce_task_delete_ownership_before_delete
before delete on public.tasks
for each row execute function private.enforce_task_delete_ownership();

commit;
