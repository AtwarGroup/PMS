begin;

alter table public.profiles
  add column if not exists employee_code text,
  add column if not exists join_date date,
  add column if not exists work_location text,
  add column if not exists employment_type text;

create or replace function public.get_my_manager_profile()
returns table(id uuid,full_name text,email text)
language sql stable security definer
set search_path='pg_catalog','public'
as $$
  select manager.id,manager.full_name,manager.email
  from public.profiles employee
  join public.profiles manager on manager.id=employee.manager_id
  where employee.id=(select auth.uid())
    and employee.active=true and employee.status='active'
  limit 1
$$;
revoke all on function public.get_my_manager_profile() from public,anon;
grant execute on function public.get_my_manager_profile() to authenticated;

create or replace function public.admin_update_profile_details(
  p_profile_id uuid,
  p_employee_code text default null,
  p_join_date date default null,
  p_work_location text default null,
  p_employment_type text default null
)
returns void language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
begin
  if not private.is_admin() then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  update public.profiles set
    employee_code=nullif(btrim(coalesce(p_employee_code,'')),''),
    join_date=p_join_date,
    work_location=nullif(btrim(coalesce(p_work_location,'')),''),
    employment_type=nullif(btrim(coalesce(p_employment_type,'')),''),
    updated_at=now()
  where id=p_profile_id;
  if not found then raise exception 'Profile not found'; end if;
end $$;
revoke all on function public.admin_update_profile_details(uuid,text,date,text,text) from public,anon;
grant execute on function public.admin_update_profile_details(uuid,text,date,text,text) to authenticated;

commit;
