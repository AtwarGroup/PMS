-- Keep a task update and its subtask reconciliation in one database transaction.
-- SECURITY INVOKER preserves the existing task and subtask RLS checks.
create or replace function public.update_task_with_subtasks_safe(
  p_task_id uuid,
  p_expected_revision integer,
  p_patch jsonb,
  p_subtasks jsonb
)
returns public.tasks
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_task public.tasks%rowtype;
  v_item jsonb;
  v_id uuid;
  v_position integer := 0;
  v_keep uuid[] := array[]::uuid[];
  v_done boolean;
begin
  if jsonb_typeof(p_subtasks) is distinct from 'array' then
    raise exception 'Subtasks must be an array' using errcode = '22023';
  end if;
  if not private.can_edit_task_content(p_task_id) then
    raise exception 'Subtask edit is not permitted' using errcode = '42501';
  end if;

  v_task := public.update_task_safe(p_task_id, p_expected_revision, p_patch);
  for v_item in select value from jsonb_array_elements(p_subtasks) loop
    v_position := v_position + 1;
    v_id := (v_item->>'id')::uuid;
    if v_id is null or nullif(btrim(v_item->>'title'), '') is null then
      raise exception 'Subtask id and title are required' using errcode = '22023';
    end if;
    if v_id = any(v_keep) then
      raise exception 'Duplicate subtask id' using errcode = '22023';
    end if;
    v_keep := array_append(v_keep, v_id);
    v_done := coalesce((v_item->>'done')::boolean, false);

    update public.subtasks
    set position = v_position,
        title = v_item->>'title',
        done = v_done,
        completed_at = case when v_done then coalesce(nullif(v_item->>'completed_at', '')::timestamptz, now()) else null end
    where id = v_id and task_id = p_task_id
      and (position, title, done, completed_at) is distinct from
          (v_position, v_item->>'title', v_done,
           case when v_done then coalesce(nullif(v_item->>'completed_at', '')::timestamptz, completed_at, now()) else null end);

    if not found and not exists(select 1 from public.subtasks where id = v_id and task_id = p_task_id) then
      insert into public.subtasks(id, task_id, position, title, done, created_at, completed_at)
      values(v_id, p_task_id, v_position, v_item->>'title', v_done,
             coalesce(nullif(v_item->>'created_at', '')::timestamptz, now()),
             case when v_done then coalesce(nullif(v_item->>'completed_at', '')::timestamptz, now()) else null end);
    end if;
  end loop;

  delete from public.subtasks where task_id = p_task_id and not (id = any(v_keep));
  return v_task;
end;
$function$;

revoke all on function public.update_task_with_subtasks_safe(uuid, integer, jsonb, jsonb) from public, anon;
grant execute on function public.update_task_with_subtasks_safe(uuid, integer, jsonb, jsonb) to authenticated;
