begin;
set local lock_timeout='2s';
set local statement_timeout='30s';
create temp table incident_acl_before(actor uuid primary key,ids uuid[])on commit drop;
do $$declare actor uuid;seen uuid[];begin
 for actor in select id from(select id,row_number()over(partition by role,status,('tasks'=any(allowed_modules)),('projects'=any(allowed_modules)),('tasks.read_all'=any(permissions))order by id)n from public.profiles)p where n=1 loop
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 select coalesce(array_agg(id order by id),'{}'::uuid[])into seen from public.tasks;
 perform set_config('role','postgres',true);
 insert into incident_acl_before values(actor,seen);
 end loop;
end$$;
-- Equivalent task visibility with statement-scoped account checks and row-local ownership.
-- Keep deleted-record, project, module and active-account boundaries unchanged.
alter policy module_boundary on public.tasks using(
 (select private.module_allowed('tasks'))or(project_id is not null and(select private.module_allowed('projects')))
);
alter policy tasks_select_policy on public.tasks using(
 (
  (deleted_at is null and(select private.current_user_is_active())and(
   creator_id=(select auth.uid())or assignee_id=(select auth.uid())or delegated_by_id=(select auth.uid())or(select private.is_admin())
  ))or private.can_view_task(id)or(select private.has_permission('tasks.read_all'))
 )and(project_id is null or private.project_access(project_id))
);
do $$declare r record;seen uuid[];begin
 for r in select * from incident_acl_before loop
 perform set_config('request.jwt.claims',jsonb_build_object('sub',r.actor,'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 select coalesce(array_agg(id order by id),'{}'::uuid[])into seen from public.tasks;
 perform set_config('role','postgres',true);
 assert seen=r.ids,'task visibility changed';
 end loop;
end$$;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from public.profiles where role='admin'and active and status='active'order by id limit 1),'role','authenticated')::text,true);
set local role authenticated;
explain(analyze,format json)select id,title,status,assignee_id,creator_id,due_date from public.tasks where deleted_at is null order by created_at desc limit 500;
rollback;
