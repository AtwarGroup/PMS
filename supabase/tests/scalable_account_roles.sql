-- Exercise real client roles. All records, grants, edits and profile changes roll back.
begin;
do $setup$
declare d uuid;s uuid;t uuid;a uuid;m uuid;e uuid;ma uuid;ea uuid;outside_id uuid;
begin
 select id into strict a from public.profiles where email='e2e-admin@atwargroup.test';
 select id into strict m from public.profiles where email='e2e-manager@atwargroup.test';
 select id into strict e from public.profiles where email='e2e-employee@atwargroup.test';
 perform set_config('qa.hr_admin',a::text,true);perform set_config('qa.hr_manager',m::text,true);perform set_config('qa.hr_employee',e::text,true);
 insert into private.hr_departments(name)values('QA employee access '||gen_random_uuid())returning id into d;
 insert into private.hr_sections(department_id,name)values(d,'QA')returning id into s;
 insert into private.hr_titles(title)values('QA employee title '||gen_random_uuid())returning id into t;
 insert into private.hr_employees(employee_code,full_name,email,department_id,section_id,title_id,profile_id,join_date,effective_from)values('990000001','QA manager','qa.hr.manager@atwargroup.test',d,s,t,m,current_date,current_date)returning id into ma;
 insert into private.hr_employees(employee_code,full_name,email,department_id,section_id,title_id,profile_id,manager_id,join_date,effective_from)values('990000002','QA employee','qa.hr.employee@atwargroup.test',d,s,t,e,ma,current_date,current_date)returning id into ea;
 insert into private.hr_employees(employee_code,full_name,email,department_id,section_id,title_id,join_date,effective_from)values('990000003','QA outside','qa.hr.outside@atwargroup.test',d,s,t,current_date,current_date)returning id into outside_id;
 insert into private.hr_compensation(employee_id,basic,allowances,effective_from)values(ma,1000,100,current_date),(ea,2000,200,current_date),(outside_id,3000,300,current_date);
 insert into private.hr_personal values(ma,'2999999901','QA',null),(ea,'2999999902','QA','0500000000'),(outside_id,'2999999903','QA',null);
 insert into private.hr_vehicles(employee_id)values(ma),(ea),(outside_id);
 perform set_config('qa.hr_manager_record',ma::text,true);perform set_config('qa.hr_record',ea::text,true);perform set_config('qa.hr_outside',outside_id::text,true);
end $setup$;
set local role authenticated;
do $qa$
declare a uuid:=current_setting('qa.hr_admin')::uuid;m uuid:=current_setting('qa.hr_manager')::uuid;e uuid:=current_setting('qa.hr_employee')::uuid;outside_id uuid:=current_setting('qa.hr_outside')::uuid;team_id uuid:=current_setting('qa.hr_record')::uuid;rid uuid;rid2 uuid;j jsonb;denied boolean;rules jsonb;
begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
 denied:=false;begin perform public.access_admin_context();exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Employee viewed account directory';end if;
 denied:=false;begin perform public.access_role_save(null,null,'QA denied','',true,'[]');exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Employee created role';end if;
 denied:=false;begin perform public.access_account_update(e,'admin',true);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Employee escalated';end if;
 denied:=false;begin perform 1 from private.access_roles;exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Private roles exposed';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 j:=public.access_admin_context();if jsonb_array_length(j->'catalog')<>10 then raise exception 'Catalog mismatch';end if;
 denied:=false;begin perform public.access_role_save(null,null,'QA invalid','',true,'[{"permission":"employees.salary.write","scope":"all"}]');exception when raise_exception then denied:=true;end;if not denied then raise exception 'Write without read accepted';end if;
 denied:=false;begin perform public.access_role_save(null,null,'QA invalid','',true,'[{"permission":"tasks.read_all","scope":"team"}]');exception when raise_exception then denied:=true;end;if not denied then raise exception 'Unsupported scope accepted';end if;
 rules:='[{"permission":"employees.salary.read","scope":"all"},{"permission":"employees.salary.write","scope":"team"},{"permission":"tasks.read_all","scope":"all"}]';
 rid:=public.access_role_save(null,null,'QA payroll '||gen_random_uuid(),'QA',true,rules);
 perform public.access_assign_roles(m,array[rid],array[]::uuid[]);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 j:=public.employee_master_detail(outside_id);if not(j?'salary')or(j#>>'{rights,salary,write}')::boolean then raise exception 'Read-all widened team write';end if;
 j:=public.employee_master_detail(team_id);if not(j#>>'{rights,salary,write}')::boolean then raise exception 'Role team write missing';end if;
 if not private.has_permission('tasks.read_all')then raise exception 'Role task permission not projected';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 perform public.admin_set_executive_task_access(m,true);
 perform public.access_assign_roles(m,array[]::uuid[],array[rid]);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 if not private.has_permission('tasks.read_all')then raise exception 'Removing role revoked independent direct grant';end if;
 denied:=false;begin perform public.employee_master_detail(outside_id);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Removed role retained salary access';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 perform public.admin_set_executive_task_access(m,false);
 perform public.access_assign_roles(m,array[rid],array[]::uuid[]);
 perform public.access_role_save(rid,1,'QA payroll '||rid,'QA',false,rules);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 if private.has_permission('tasks.read_all')then raise exception 'Disabled role retained task permission';end if;
 denied:=false;begin perform public.employee_master_detail(outside_id);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Disabled role retained salary permission';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 denied:=false;begin perform public.access_role_save(rid,1,'QA stale','',true,rules);exception when sqlstate 'PT409' then denied:=true;end;if not denied then raise exception 'Stale role revision accepted';end if;
 denied:=false;begin perform public.access_assign_roles(m,array[]::uuid[],array[]::uuid[]);exception when sqlstate 'PT409' then denied:=true;end;if not denied then raise exception 'Stale assignment accepted';end if;
 rid2:=public.access_role_save(null,null,'QA indirect '||gen_random_uuid(),'',true,'[{"permission":"tasks.assign_indirect","scope":"team"}]');
 denied:=false;begin perform public.access_assign_roles(e,array[rid2],array[]::uuid[]);exception when raise_exception then denied:=true;end;if not denied then raise exception 'Employee got manager-only capability';end if;
 denied:=false;begin perform public.access_account_update(a,'employee',false);exception when raise_exception then denied:=true;end;if not denied then raise exception 'Self admin lockout accepted';end if;
 -- A failure in a direct bundle rolls back earlier changes in that bundle.
 denied:=false;begin perform public.access_direct_save(e,'[{"permission":"tasks.read_all","scope":"all"},{"permission":"employees.salary.write","scope":"all"}]');exception when raise_exception then denied:=true;end;if not denied then raise exception 'Invalid direct bundle accepted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);if private.has_permission('tasks.read_all')then raise exception 'Partial direct bundle persisted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 j:=public.access_audit_list();if jsonb_array_length(j)<5 then raise exception 'Audit missing';end if;
 perform public.access_account_update(m,'manager',false);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 denied:=false;begin perform public.employee_master_detail(team_id);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Inactive account retained access';end if;
end $qa$;
rollback;
