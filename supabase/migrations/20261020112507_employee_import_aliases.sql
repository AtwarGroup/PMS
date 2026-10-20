-- Install as a private, postgres-only maintenance function via apply_migration.
-- The employee payload is supplied separately and MUST NEVER be committed.
create or replace function private.import_employee_master(p_rows jsonb,p_source_hash text,p_dry_run boolean default true)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public,private as $import$
declare r jsonb;x record;v_import uuid;v_admin uuid:=auth.uid();v_employee uuid;v_department uuid;v_section uuid;v_title uuid;v_profile uuid;v_manager uuid;v_count integer;v_accounts integer;v_notifications integer;v_email integer;v_task_count integer;v_fingerprint text;v_result jsonb;v_triggers jsonb;v_j public.job_descriptions%rowtype;v_effective date:='2026-10-20';
begin
 if current_user<>'postgres' or not private.is_admin() then raise exception 'Postgres maintenance operator and administrator identity required' using errcode='42501';end if;
 if jsonb_array_length(p_rows)<>135 or p_source_hash!~'^[a-f0-9]{64}$' then raise exception 'Unexpected import source';end if;
 if exists(select 1 from private.hr_imports where source_sha256=p_source_hash) then raise exception 'تم استيراد هذا الملف سابقًا';end if;
 if exists(select 1 from private.hr_employees) then raise exception 'Initial employee import requires an empty master';end if;
 begin
  perform set_config('lock_timeout','5s',true);
  lock table public.profiles,public.job_descriptions,public.tasks,public.employee_job_assignments in access exclusive mode;
  select count(*) into v_accounts from auth.users;
  select count(*) into v_notifications from public.notifications;
  select count(*) into v_email from public.job_publication_email_outbox;
  select count(*) into v_task_count from public.tasks;
  select md5(coalesce(string_agg((to_jsonb(t)-array['updated_at','revision','creator_name_snapshot','assignee_name_snapshot','delegated_by_name_snapshot','approved_by_name_snapshot','returned_by_name_snapshot','reopened_by_name_snapshot'])::text,'' order by t.id),'')) into v_fingerprint from public.tasks t where task_type<>'job_workflow';
  select jsonb_agg(jsonb_build_object('table',c.relname,'name',t.tgname,'enabled',t.tgenabled)) into v_triggers from pg_trigger t join pg_class c on c.oid=t.tgrelid where t.tgrelid in('public.job_descriptions'::regclass,'public.tasks'::regclass,'public.employee_job_assignments'::regclass,'public.employee_job_change_requests'::regclass,'public.job_description_change_requests'::regclass) and not t.tgisinternal and t.tgenabled<>'D' and t.tgname<>'job_descriptions_audit';
  for r in select value from jsonb_array_elements(v_triggers) loop execute format('alter table public.%I disable trigger %I',r->>'table',r->>'name');end loop;
  insert into private.hr_imports(source_name,source_sha256,effective_from,employee_count,existing_accounts,actor_id,summary)
   values('قاعدة البيانات.xlsx',p_source_hash,v_effective,135,23,v_admin,jsonb_build_object('mode','administrative_baseline','email',false,'reapproval',false,'accounts_created',0))returning id into v_import;
  insert into private.hr_import_snapshots select v_import,'profile',p.id,to_jsonb(p) from public.profiles p where exists(select 1 from jsonb_array_elements(p_rows)q where lower(q->>'email')=lower(p.email));
  insert into private.hr_import_snapshots select v_import,'job',j.id,to_jsonb(j) from public.job_descriptions j where exists(select 1 from jsonb_array_elements(p_rows)q where q->>'job_code'=j.job_code);
  insert into private.hr_import_snapshots select v_import,'assignment',a.profile_id,to_jsonb(a) from public.employee_job_assignments a where exists(select 1 from private.hr_import_snapshots s where s.import_id=v_import and s.entity='profile' and s.entity_id=a.profile_id);
  select count(*) into v_count from private.hr_import_snapshots where import_id=v_import and entity='profile';
  if v_count<>23 then raise exception 'Existing account reconciliation failed: %',v_count;end if;
  for r in select value from jsonb_array_elements(p_rows) loop
   if nullif(r->>'employee_code','') is null or nullif(r->>'email','') is null or nullif(r->>'department','') is null or nullif(r->>'section','') is null then raise exception 'Incomplete employee row';end if;
   insert into private.hr_departments(name) values(btrim(r->>'department'))on conflict(name)do update set name=excluded.name returning id into v_department;
   insert into private.hr_sections(department_id,name)values(v_department,btrim(r->>'section'))on conflict(department_id,name)do update set name=excluded.name returning id into v_section;
   select * into strict v_j from public.job_descriptions where job_code=r->>'job_code' and status<>'ARCHIVED';
   insert into private.hr_titles(title,job_description_id)values(btrim(r->>'title'),v_j.id)on conflict(title)do update set job_description_id=excluded.job_description_id returning id into v_title;
   select id into v_profile from public.profiles where lower(email)=lower(r->>'email');
   if v_profile is not null and not exists(select 1 from private.hr_import_snapshots where import_id=v_import and entity='profile' and entity_id=v_profile)then raise exception 'Unreviewed account match';end if;
   insert into private.hr_employees(employee_code,full_name,email,department_id,section_id,title_id,profile_id,join_date,effective_from)
    values(r->>'employee_code',btrim(r->>'full_name'),lower(btrim(r->>'email')),v_department,v_section,v_title,v_profile,(r->>'join_date')::date,v_effective)returning id into v_employee;
   insert into private.hr_personal values(v_employee,r->>'residency_number',r->>'nationality',nullif(r->>'phone',''));
   insert into private.hr_compensation(employee_id,basic,allowances,effective_from)values(v_employee,(r->>'basic')::numeric,(r->>'allowances')::numeric,v_effective);
   if abs((r->>'basic')::numeric+(r->>'allowances')::numeric-(r->>'total')::numeric)>0.01 then raise exception 'Salary reconciliation failed';end if;
   insert into private.hr_vehicles values(v_employee,nullif(r->>'vin',''),nullif(r->>'plate',''),nullif(r->>'vehicle_type',''));
  end loop;
  for r in select value from jsonb_array_elements(p_rows)loop
   v_manager:=null;
   if nullif(r->>'manager_code','') is not null then select id into strict v_manager from private.hr_employees where employee_code=r->>'manager_code';end if;
   update private.hr_employees set manager_id=v_manager where employee_code=r->>'employee_code';
  end loop;
  if exists(with recursive ancestry as(select id,manager_id,array[id] path,false cycle from private.hr_employees union all select a.id,m.manager_id,a.path||m.id,m.id=any(a.path) from ancestry a join private.hr_employees m on m.id=a.manager_id where not a.cycle and cardinality(a.path)<=135)select 1 from ancestry where cycle or cardinality(path)>135)then raise exception 'Employee hierarchy cycle';end if;
  if(select count(*) from private.hr_employees where manager_id is null)<>1 then raise exception 'Expected one hierarchy root';end if;
  -- Keep current Auth UUIDs, passwords, sessions, permissions, assignments and task links.
  update public.profiles p set full_name=e.full_name,employee_code=e.employee_code,department=d.name,job_title=t.title,join_date=e.join_date,manager_id=m.profile_id,
   role=case when p.role='employee' and exists(select 1 from private.hr_employees child where child.manager_id=e.id)then 'manager' else p.role end
   from private.hr_employees e join private.hr_departments d on d.id=e.department_id join private.hr_titles t on t.id=e.title_id left join private.hr_employees m on m.id=e.manager_id where p.id=e.profile_id;
  -- Preserve description IDs/content. Refresh taxonomy for all referenced titles.
  -- Existing employees' descriptions become an administrative baseline without new approvals.
  for x in select t.job_description_id,t.title,string_agg(distinct d.name,' / ' order by d.name)department from private.hr_titles t join private.hr_employees e on e.title_id=t.id join private.hr_departments d on d.id=e.department_id group by t.id loop
   select * into strict v_j from public.job_descriptions where id=x.job_description_id;
   if exists(select 1 from public.employee_job_assignments a join private.hr_employees e on e.profile_id=a.profile_id where a.job_description_id=v_j.id)then
    update public.job_descriptions set title=x.title,family=x.department,status='PUBLISHED',revision=revision+1,updated_by=v_admin,updated_at=now(),published_by=coalesce(published_by,v_admin),published_at=now(),review_note='تحديث إداري للمرحلة الثانية بتوجيه الإدارة؛ دون إعادة اعتماد أو بريد أو إقرار موظف.',
     published_snapshot=jsonb_build_object('job_code',v_j.job_code,'title',x.title,'family',x.department,'job_level',v_j.job_level,'reports_to_title',v_j.reports_to_title,'purpose',v_j.purpose,'content',v_j.content,'revision',v_j.revision+1,'published_at',now())where id=v_j.id;
   elsif v_j.title is distinct from x.title or v_j.family is distinct from x.department then
    update public.job_descriptions set title=x.title,family=x.department,revision=revision+1,updated_by=v_admin,updated_at=now(),review_note='توحيد التصنيف والمسمى حسب قاعدة بيانات المرحلة الثانية.' where id=v_j.id;
   end if;
  end loop;
  -- Archive superseded proposals, retaining their complete prior state.
  update public.employee_job_change_requests req set status='ARCHIVED',archived_at=now(),archive_reason='تهيئة إدارية للمرحلة الثانية دون إعادة اعتماد',archive_snapshot=to_jsonb(req),approval_snapshot=null,manager_decided_at=null
   where status in('MANAGER_REVIEW','ADMIN_REVIEW','NEEDS_CHANGES','APPLIED')and exists(select 1 from private.hr_import_snapshots s where s.import_id=v_import and s.entity='job' and s.entity_id=req.job_description_id);
  update public.job_description_change_requests req set status='ARCHIVED',archived_at=now(),archive_snapshot=to_jsonb(req)where status='PENDING' and exists(select 1 from private.hr_import_snapshots s where s.import_id=v_import and s.entity='job' and s.entity_id=req.job_description_id);
  perform set_config('app.migration_mode','on',true);
  insert into private.hr_import_snapshots select v_import,'workflow_task',t.id,to_jsonb(t)from public.tasks t where t.task_type='job_workflow' and t.deleted_at is null and t.status not in('مكتملة','ملغاة')and exists(select 1 from private.hr_import_snapshots s where s.import_id=v_import and s.entity='job' and s.entity_id::text=t.legacy_metadata#>>'{job_workflow,job_id}');
  update public.tasks t set deleted_at=now(),deleted_by=v_admin,delete_reason='أرشفة مسار سابق بعد التهيئة الإدارية للمرحلة الثانية',revision=revision+1 where exists(select 1 from private.hr_import_snapshots s where s.import_id=v_import and s.entity='workflow_task' and s.entity_id=t.id);
  update public.notifications n set read_at=coalesce(read_at,now())where exists(select 1 from private.hr_import_snapshots s where s.import_id=v_import and s.entity='workflow_task' and s.entity_id=n.task_id);
  perform set_config('app.migration_mode','off',true);
  -- Store per-domain baseline history without duplicating private data into public logs.
  insert into private.hr_history(employee_id,domain,after_data,effective_from,actor_id,reason)select id,'records',to_jsonb(e),v_effective,v_admin,'الاستيراد الأولي المعتمد — المرحلة الثانية'from private.hr_employees e;
  insert into private.hr_history(employee_id,domain,after_data,effective_from,actor_id,reason)select employee_id,'personal',to_jsonb(p)-'employee_id',v_effective,v_admin,'الاستيراد الأولي المعتمد'from private.hr_personal p;
  insert into private.hr_history(employee_id,domain,after_data,effective_from,actor_id,reason)select employee_id,'salary',to_jsonb(p)-'employee_id',v_effective,v_admin,'راتب شهري بالريال السعودي — استيراد أولي'from private.hr_compensation p;
  insert into private.hr_history(employee_id,domain,after_data,effective_from,actor_id,reason)select employee_id,'vehicles',to_jsonb(p)-'employee_id',v_effective,v_admin,'الاستيراد الأولي المعتمد'from private.hr_vehicles p;
  for r in select value from jsonb_array_elements(v_triggers)loop execute format('alter table public.%I %s trigger %I',r->>'table',case r->>'enabled' when 'A' then 'enable always' when 'R' then 'enable replica' else 'enable' end,r->>'name');end loop;
  if(select count(*) from auth.users)<>v_accounts or(select count(*)from public.notifications)<>v_notifications or(select count(*)from public.job_publication_email_outbox)<>v_email or(select count(*)from public.tasks)<>v_task_count then raise exception 'Unexpected account, notification, email or task creation';end if;
  if v_fingerprint is distinct from(select md5(coalesce(string_agg((to_jsonb(t)-array['updated_at','revision','creator_name_snapshot','assignee_name_snapshot','delegated_by_name_snapshot','approved_by_name_snapshot','returned_by_name_snapshot','reopened_by_name_snapshot'])::text,'' order by t.id),''))from public.tasks t where task_type<>'job_workflow') then raise exception 'Business task data changed';end if;
  if exists(select 1 from private.hr_import_snapshots s join public.job_descriptions j on j.id=s.entity_id where s.import_id=v_import and s.entity='job' and(j.purpose is distinct from s.before_data->>'purpose' or j.content is distinct from s.before_data->'content'))then raise exception 'Description responsibilities or KPIs changed';end if;
  if exists(select 1 from private.hr_import_snapshots s join public.employee_job_assignments a on a.profile_id=s.entity_id where s.import_id=v_import and s.entity='assignment' and to_jsonb(a)<>s.before_data)then raise exception 'Existing job binding changed';end if;
  v_result:=jsonb_build_object('employees',(select count(*)from private.hr_employees),'linked_accounts',(select count(*)from private.hr_employees where profile_id is not null),'departments',(select count(*)from private.hr_departments),'sections',(select count(*)from private.hr_sections),'titles',(select count(*)from private.hr_titles),'accounts_created',0,'notifications_created',0,'emails_created',0,'archived_workflow_tasks',(select count(*)from private.hr_import_snapshots where import_id=v_import and entity='workflow_task'),'dry_run',p_dry_run);
  if p_dry_run then raise exception 'HR_IMPORT_DRY_RUN_COMPLETE';end if;
 exception when raise_exception then if sqlerrm<>'HR_IMPORT_DRY_RUN_COMPLETE' then raise;end if;return v_result;end;
 return v_result;
end $import$;
revoke all on function private.import_employee_master(jsonb,text,boolean) from public,anon,authenticated,service_role;
