-- Client-role regression. Every fixture, grant and audit row is rolled back.
begin;
select set_config('qa.module_admin',id::text,true)from public.profiles where email='e2e-admin@atwargroup.test';
select set_config('qa.module_employee',id::text,true)from public.profiles where email='e2e-employee@atwargroup.test';
set local role authenticated;
do $qa$
declare a uuid:=current_setting('qa.module_admin')::uuid;e uuid:=current_setting('qa.module_employee')::uuid;ctx jsonb;r integer;t uuid;note uuid;project_id uuid;outside_project uuid;pt uuid;m uuid;pol uuid;pv uuid;denied boolean;f record;arguments text;tested integer:=0;
begin
 if a is null or e is null then raise exception 'QA fixtures unavailable';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 ctx:=public.access_admin_context();if jsonb_array_length(ctx->'module_catalog')<>8 then raise exception 'Module catalog missing';end if;
 select module_revision into r from public.profiles where id=e;
 perform public.account_access_save(e,'employee',true,array['tasks','workspace','projects','policies','communication','employees','job_library'],r);
 select id into strict m from public.profiles where email='e2e-manager@atwargroup.test';
 pol:=public.policy_create('QA-'||gen_random_uuid()::text,'QA module policy','[{"id":"s1","title":"Test","body":"Test content"}]','QA');
 select id into strict pv from public.policy_versions where policy_id=pol;
 perform public.policy_configure(pol,1,'QA module policy',a,m,a,m,array['EMPLOYEES'],array[]::uuid[]);
 perform public.policy_save(pv,2,'[{"id":"s1","title":"Test","body":"Updated test content"}]','QA');
 perform public.policy_decide(pv,3,false,'QA prepared',null);
 project_id:=public.project_command(null,0,'create',jsonb_build_object('title','QA module project','manager_id',m,'sponsor_id',a,'start_date',current_date,'due_date',current_date+10,'members',jsonb_build_array(e)));
 outside_project:=public.project_command(null,0,'create',jsonb_build_object('title','QA outside module project','manager_id',m,'sponsor_id',a,'start_date',current_date,'due_date',current_date+10));
 pt:=public.project_command(project_id,1,'task',jsonb_build_object('title','QA module project task','assignee_id',e,'start_date',current_date,'due_date',current_date+2));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
 t:=public.create_task_safe('QA module boundary',e,'متوسطة','',current_date,current_date+1,'');
 note:=public.workspace_save_note('QA module workspace');
 if not exists(select 1 from public.tasks where id=t)then raise exception 'Baseline task unavailable';end if;
 perform 1 from public.policies;perform public.project_directory();perform public.employee_master_context();perform public.search_tasks_safe('QA module boundary',20);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 select module_revision into r from public.profiles where id=e;
 perform public.account_access_save(e,'employee',true,array[]::text[],r);
 -- Stale changes fail before modifying any account setting.
 denied:=false;begin perform public.account_access_save(e,'manager',true,array['policies'],r);exception when serialization_failure then denied:=true;end;if not denied then raise exception 'Stale module update accepted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
 if exists(select 1 from public.tasks where id=t)or exists(select 1 from public.quick_notes where id=note)or exists(select 1 from public.projects)or exists(select 1 from public.policies)then raise exception 'Disabled unit leaked raw rows';end if;
 ctx:=public.account_module_context();if jsonb_array_length(ctx->'allowed')<>0 then raise exception 'Empty selection widened';end if;
 denied:=false;begin update public.profiles set allowed_modules=array['tasks']where id=e;exception when insufficient_privilege then denied:=true;end;if private.module_allowed('tasks')then raise exception 'User changed own module access';end if;
 denied:=false;begin perform public.account_access_save(e,'admin',true,array['tasks'],1);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Employee saved access';end if;
 -- Every guarded public endpoint rejects before original validation or side effects.
 for f in select p.oid,p.proname,p.proargtypes from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.prosrc like '%PERFORM private.require_module%'loop
 select string_agg('NULL::'||format_type(v,null),','order by ord)into arguments from unnest(f.proargtypes)with ordinality x(v,ord);
 denied:=false;begin execute format('select public.%I(%s)',f.proname,coalesce(arguments,''));exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Disabled RPC accepted: %',f.proname;end if;tested:=tested+1;
 end loop;
 if tested<50 then raise exception 'RPC boundary coverage incomplete: %',tested;end if;
 if public.communication_status()or public.communication_trial_status()then raise exception 'Communication edge gate bypassed module';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 select module_revision into r from public.profiles where id=e;
 denied:=false;begin perform public.account_access_save(e,'employee',true,array['fleet'],r);exception when invalid_parameter_value then denied:=true;end;if not denied then raise exception 'Unreleased fleet enabled';end if;
 perform public.account_access_save(e,'employee',true,array['tasks'],r);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
 if not exists(select 1 from public.tasks where id=pt)or exists(select 1 from public.projects where id=project_id)then raise exception 'Tasks-only access changed project-task relation';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);select module_revision into r from public.profiles where id=e;
 perform public.account_access_save(e,'employee',true,array['projects'],r);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
 if exists(select 1 from public.tasks where id=t)or not exists(select 1 from public.tasks where id=pt)or not exists(select 1 from public.projects where id=project_id)or exists(select 1 from public.projects where id=outside_project)then raise exception 'Projects-only boundary lost membership isolation';end if;
 perform public.update_task_safe(pt,1,'{"status":"قيد التنفيذ"}');
 denied:=false;begin perform public.task_followup_context(t);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Project access exposed ordinary task RPC';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);select module_revision into r from public.profiles where id=e;
 perform public.account_access_save(e,'employee',true,array['policies'],r);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
 perform 1 from public.policies;
 if private.module_allowed('tasks')or private.module_allowed('workspace')or not private.module_allowed('policies')then raise exception 'Unit selection not independent';end if;
 denied:=false;begin perform public.workspace_save_note('Must not save');exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Workspace write not guarded';end if;
 -- Admin core access remains available even with an empty optional selection.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 select module_revision into r from public.profiles where id=a;
 perform public.account_access_save(a,'admin',true,array[]::text[],r);
 if not private.module_allowed('tasks')or not private.module_allowed('policies')then raise exception 'Administrator locked out';end if;
 if not exists(select 1 from jsonb_array_elements(public.access_audit_list())x where x->>'action'='MODULE_ACCESS_CHANGED')then raise exception 'Module changes not audited';end if;
end$qa$;
rollback;
