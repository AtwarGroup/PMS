-- Cron continues calling the private scheduler. Manual API execution is admin-only.
create or replace function public.run_recurring_tasks_safe()
returns integer language plpgsql security definer
set search_path='public','private','pg_temp' as $$
begin
 if not private.current_user_is_active() or private.current_user_role() is distinct from 'admin' then
  raise exception 'Administrator permission required';
 end if;
 return private.materialize_recurring_tasks();
end $$;
revoke all on function public.run_recurring_tasks_safe() from public,anon;
grant execute on function public.run_recurring_tasks_safe() to authenticated;
