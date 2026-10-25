-- Append-only history continues to be recorded. Only active system administrators may read it.
do $$
declare tbl text;
begin
 foreach tbl in array array['task_activity','policy_events','project_events','improvement_events','employee_job_change_events','job_periodic_review_events','work_relation_history','job_description_versions'] loop
  if to_regclass('public.'||tbl) is null then continue;end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename=tbl and policyname='admin_only_action_history') then
   execute format('create policy admin_only_action_history on public.%I as restrictive for select to authenticated using ((select private.is_admin()))',tbl);
  end if;
 end loop;
end$$;
-- Private RPCs run as their owner, so filter their audit aggregates explicitly as well.
do $$
declare change record;definition text;patched text;
begin
 for change in select * from (values
  ('private.fleet_detail_before_operations(uuid)','where e.request_id=p_id','where e.request_id=p_id and private.is_admin()'),
  ('private.fleet_vehicle_profile(uuid)','where e.vehicle_id=v.id and','where e.vehicle_id=v.id and private.is_admin() and'),
  ('private.hr_detail_before_fleet(uuid)','where h.employee_id=e.id and','where h.employee_id=e.id and private.is_admin() and'),
  ('private.recruitment_detail_v1(uuid)','from private.recruitment_events e where request_id=p_request','from private.recruitment_events e where request_id=p_request and private.is_admin()')
 ) as changes(signature,needle,replacement) loop
  if to_regprocedure(change.signature) is null then continue;end if;
  definition:=pg_get_functiondef(to_regprocedure(change.signature));
  if strpos(definition,change.replacement)>0 then continue;end if;
  if strpos(definition,change.needle)=0 then raise exception 'Audit read guard target changed: %',change.signature;end if;
  patched:=replace(definition,change.needle,change.replacement);execute patched;
 end loop;
end$$;
-- The UI uses an explicit server-verified admin flag, never a business/module permission.
create or replace function public.fleet_snapshot() returns jsonb language sql set search_path=pg_catalog,private as $$select private.fleet_snapshot()||jsonb_build_object('audit_admin',private.is_admin())$$;
create or replace function public.recruitment_context() returns jsonb language sql set search_path=pg_catalog,private as $$select private.recruitment_context()||jsonb_build_object('audit_admin',private.is_admin())$$;
revoke all on function public.fleet_snapshot(),public.recruitment_context() from public,anon;
grant execute on function public.fleet_snapshot(),public.recruitment_context() to authenticated;
