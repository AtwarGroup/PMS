create or replace function private.team_employee_published_job(p_profile_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, private
as $$
declare v_profile public.profiles%rowtype; v_job_id uuid; v_snapshot jsonb;
begin
 if auth.uid() is null or not private.can_assign_task_target(p_profile_id)
    or not exists(select 1 from public.profiles where id=auth.uid() and role in ('manager','admin')) then
   raise exception 'Employee outside permitted team scope' using errcode='42501';
 end if;
 select * into v_profile from public.profiles where id=p_profile_id;
 select job_description_id into v_job_id from public.employee_job_assignments where profile_id=p_profile_id;
 v_job_id:=coalesce(v_job_id,v_profile.job_description_id);
 -- Match by title only for legacy profiles with no explicit assignment.
 if v_job_id is null then
   select id into v_job_id from public.job_descriptions
   where title=v_profile.job_title and published_at is not null
   order by published_at desc,id limit 1;
 end if;
 select published_snapshot into v_snapshot from public.job_descriptions
 where id=v_job_id and published_at is not null and published_snapshot is not null;
 return jsonb_build_object('full_name',v_profile.full_name,'job_title',v_profile.job_title,
   'job_id',v_job_id,'snapshot',v_snapshot);
end;
$$;
revoke all on function private.team_employee_published_job(uuid) from public,anon,authenticated;
create or replace function public.get_team_employee_job(p_profile_id uuid)
returns jsonb language sql stable security invoker
set search_path = pg_catalog
as $$ select private.team_employee_published_job(p_profile_id); $$;
revoke all on function public.get_team_employee_job(uuid) from public,anon;
grant execute on function private.team_employee_published_job(uuid) to authenticated;
grant execute on function public.get_team_employee_job(uuid) to authenticated;
