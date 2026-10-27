-- Return only the aggregate needed for delay calculations, never audit details.
create or replace function public.task_approval_pause_days(p_task_ids uuid[], p_timezone text default 'Asia/Riyadh')
returns table(task_id uuid, paused_days integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.current_user_is_active() then
    raise exception 'Active authenticated account required' using errcode='42501';
  end if;
  if coalesce(cardinality(p_task_ids),0)>100 then
    raise exception 'At most 100 tasks per request' using errcode='22023';
  end if;
  if p_timezone is null or length(p_timezone)>64 or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone) then
    raise exception 'Invalid timezone' using errcode='22023';
  end if;
  return query
  with allowed as (
    select t.id from public.tasks t
    where t.id=any(p_task_ids) and t.deleted_at is null
      and private.module_task_allowed(t.id)
      and (private.can_view_task(t.id) or private.has_permission('tasks.read_all'))
      and (t.project_id is null or private.project_access(t.project_id))
  ), history as (
    select a.task_id,a.event_type,a.created_at,
      lead(a.event_type) over (partition by a.task_id order by a.created_at,a.sequence_no) next_type,
      lead(a.created_at) over (partition by a.task_id order by a.created_at,a.sequence_no) next_at
    from public.task_activity a join allowed t on t.id=a.task_id
    where a.event_type in ('submitted','reopened')
  )
  select t.id,coalesce(sum(greatest(0, (h.next_at at time zone p_timezone)::date-(h.created_at at time zone p_timezone)::date)) filter (where h.event_type='submitted' and h.next_type='reopened'),0)::integer
  from allowed t left join history h on h.task_id=t.id group by t.id;
end $$;
revoke all on function public.task_approval_pause_days(uuid[],text) from public,anon;
grant execute on function public.task_approval_pause_days(uuid[],text) to authenticated;
