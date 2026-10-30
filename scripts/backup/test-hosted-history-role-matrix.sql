-- STAGING ONLY. Read-only role test; no grant changes.
begin;
set local statement_timeout='30s';
set local role authenticated;
do $audit$
declare actor uuid; tbl text; seen bigint; checks int:=0;
begin
 for actor in select ('70000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(2,8)n loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  foreach tbl in array array['task_activity','policy_events','project_events','improvement_events','employee_job_change_events','job_periodic_review_events','work_relation_history','job_description_versions'] loop
   if to_regclass('public.'||tbl) is null then continue;end if;
   execute format('select count(*) from public.%I',tbl) into seen;
   assert seen=0,'Nonadmin action history visibility: '||tbl;
   checks:=checks+1;
  end loop;
 end loop;
 assert checks=56,'Expected eight tables and seven synthetic nonadmin actors';
 perform set_config('request.jwt.claims','{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
 assert private.is_admin(),'Synthetic admin recognized';
 perform set_config('qa.history_checks',checks::text,true);
end $audit$;
select 'PASS actual authenticated role: nonadmin action history denied in 56 actor/table combinations; admin recognized' as result;
rollback;