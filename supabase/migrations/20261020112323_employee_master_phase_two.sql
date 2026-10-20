-- Employee records are independent of Auth accounts. Sensitive data stays private.
create table private.hr_departments(id uuid primary key default gen_random_uuid(),name text not null unique check(length(btrim(name))>1));
create table private.hr_sections(id uuid primary key default gen_random_uuid(),department_id uuid not null references private.hr_departments(id),name text not null,unique(department_id,name),unique(id,department_id));
create table private.hr_titles(id uuid primary key default gen_random_uuid(),title text not null unique,job_description_id uuid unique references public.job_descriptions(id));
create table private.hr_employees(
 id uuid primary key default gen_random_uuid(),employee_code text not null unique check(employee_code~'^[0-9]+$'),
 full_name text not null check(length(btrim(full_name))>=2),email text not null,
 department_id uuid not null references private.hr_departments(id),section_id uuid not null,
 title_id uuid not null references private.hr_titles(id),manager_id uuid references private.hr_employees(id) deferrable initially deferred,
 profile_id uuid unique references public.profiles(id) on delete set null,join_date date not null,
 effective_from date not null,revision integer not null default 1,updated_at timestamptz not null default now(),
 foreign key(section_id,department_id) references private.hr_sections(id,department_id),check(manager_id is distinct from id)
);
create unique index hr_employee_email_key on private.hr_employees(lower(email));
create index hr_employee_manager_idx on private.hr_employees(manager_id);
create table private.hr_personal(employee_id uuid primary key references private.hr_employees(id),residency_number text not null unique check(residency_number~'^[0-9]{10}$'),nationality text not null,phone text check(phone is null or phone~'^05[0-9]{8}$'));
create table private.hr_compensation(employee_id uuid primary key references private.hr_employees(id),basic numeric(14,2) not null check(basic>=0),allowances numeric(14,2) not null check(allowances>=0),total numeric(14,2) generated always as(basic+allowances) stored,currency text not null default 'SAR' check(currency='SAR'),period text not null default 'MONTHLY' check(period='MONTHLY'),effective_from date not null);
create table private.hr_vehicles(employee_id uuid primary key references private.hr_employees(id),vin text,plate text,vehicle_type text);
create table private.hr_access(profile_id uuid not null references public.profiles(id),domain text not null check(domain in('records','personal','salary','vehicles')),scope text not null check(scope in('all','team')),can_read boolean not null default false,can_write boolean not null default false,granted_by uuid not null references public.profiles(id),updated_at timestamptz not null default now(),primary key(profile_id,domain),check(not can_write or can_read));
create table private.hr_history(id bigint generated always as identity primary key,employee_id uuid not null references private.hr_employees(id),domain text not null check(domain in('records','personal','salary','vehicles')),before_data jsonb,after_data jsonb not null,effective_from date not null,actor_id uuid references public.profiles(id),reason text not null,created_at timestamptz not null default now());
create index hr_history_employee_idx on private.hr_history(employee_id,id desc);
create table private.hr_imports(id uuid primary key default gen_random_uuid(),source_name text not null,source_sha256 text not null unique,effective_from date not null,employee_count integer not null,existing_accounts integer not null,actor_id uuid not null references public.profiles(id),created_at timestamptz not null default now(),summary jsonb not null);
create table private.hr_import_snapshots(import_id uuid not null references private.hr_imports(id),entity text not null,entity_id uuid not null,before_data jsonb not null,primary key(import_id,entity,entity_id));
do $security$ declare t text;begin
 foreach t in array array['hr_departments','hr_sections','hr_titles','hr_employees','hr_personal','hr_compensation','hr_vehicles','hr_access','hr_history','hr_imports','hr_import_snapshots'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  execute format('create policy hr_internal_only on private.%I for all to authenticated using(false) with check(false)',t);
 end loop;
end $security$;

create function private.hr_in_team(p_employee uuid) returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 with recursive ancestors as(
  select id,manager_id,profile_id,array[id] path from private.hr_employees where id=p_employee
  union all select e.id,e.manager_id,e.profile_id,a.path||e.id from private.hr_employees e join ancestors a on e.id=a.manager_id where not e.id=any(a.path) and cardinality(a.path)<100
 ) select exists(select 1 from ancestors where profile_id=auth.uid())
$$;
revoke all on function private.hr_in_team(uuid) from public,anon,authenticated;
create function private.hr_allowed(p_employee uuid,p_domain text,p_write boolean default false) returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active() and (
  private.is_admin() or exists(select 1 from private.hr_access g where g.profile_id=auth.uid() and g.domain=p_domain and case when p_write then g.can_write else g.can_read end and(g.scope='all' or private.hr_in_team(p_employee)))
  or(p_domain='records' and not p_write and private.hr_in_team(p_employee))
 )
$$;
revoke all on function private.hr_allowed(uuid,text,boolean) from public,anon,authenticated;

create function private.hr_context() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501';end if;
 return jsonb_build_object('admin',private.is_admin(),'departments',(select coalesce(jsonb_agg(to_jsonb(d) order by name),'[]') from private.hr_departments d),'sections',(select coalesce(jsonb_agg(to_jsonb(s) order by name),'[]') from private.hr_sections s),'titles',(select coalesce(jsonb_agg(to_jsonb(t) order by title),'[]') from private.hr_titles t),
 'grants',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from private.hr_access g where private.is_admin() or g.profile_id=auth.uid()),
 'users',case when private.is_admin() then(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) order by full_name),'[]') from public.profiles where active and status='active' and email not like '%@atwargroup.test') else '[]'::jsonb end);
end $$;
create function private.hr_list() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'email',e.email,'department',d.name,'section',s.name,'title',t.title,'manager',m.full_name,'manager_code',m.employee_code,'profile_id',e.profile_id,'login_active',coalesce(p.active and p.status='active',false),'revision',e.revision,'can_write',private.hr_allowed(e.id,'records',true)) order by e.employee_code::bigint),'[]')
 from private.hr_employees e join private.hr_departments d on d.id=e.department_id join private.hr_sections s on s.id=e.section_id join private.hr_titles t on t.id=e.title_id left join private.hr_employees m on m.id=e.manager_id left join public.profiles p on p.id=e.profile_id
 where private.hr_allowed(e.id,'records',false) or private.hr_allowed(e.id,'personal',false) or private.hr_allowed(e.id,'salary',false) or private.hr_allowed(e.id,'vehicles',false));
end $$;
create function private.hr_detail(p_id uuid) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare e private.hr_employees%rowtype;result jsonb;domain_name text;allowed boolean:=false;
begin
 if not private.current_user_is_active() then raise exception 'Authentication required' using errcode='42501';end if;
 foreach domain_name in array array['records','personal','salary','vehicles'] loop allowed:=allowed or private.hr_allowed(p_id,domain_name,false);end loop;
 if not allowed then raise exception 'Employee access denied' using errcode='42501';end if;
 select * into strict e from private.hr_employees where id=p_id;
 result:=jsonb_build_object('record',to_jsonb(e),'rights',(select jsonb_object_agg(d,jsonb_build_object('read',private.hr_allowed(e.id,d,false),'write',private.hr_allowed(e.id,d,true))) from unnest(array['records','personal','salary','vehicles']) d));
 if private.hr_allowed(e.id,'personal',false) then result:=result||jsonb_build_object('personal',(select to_jsonb(p)-'employee_id' from private.hr_personal p where employee_id=e.id));end if;
 if private.hr_allowed(e.id,'salary',false) then result:=result||jsonb_build_object('salary',(select to_jsonb(p)-'employee_id' from private.hr_compensation p where employee_id=e.id));end if;
 if private.hr_allowed(e.id,'vehicles',false) then result:=result||jsonb_build_object('vehicles',(select to_jsonb(p)-'employee_id' from private.hr_vehicles p where employee_id=e.id));end if;
 return result||jsonb_build_object('history',(select coalesce(jsonb_agg(to_jsonb(h) order by h.id desc),'[]') from (select h.id,h.domain,h.before_data,h.after_data,h.effective_from,h.created_at,h.reason,p.full_name actor from private.hr_history h left join public.profiles p on p.id=h.actor_id where h.employee_id=e.id and private.hr_allowed(e.id,h.domain,false) order by h.id desc limit 100)h));
end $$;

create function private.hr_save(p_id uuid,p_domain text,p_revision integer,p_payload jsonb,p_effective date,p_reason text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare e private.hr_employees%rowtype;b jsonb;a jsonb;v_manager uuid;v_profile_manager uuid;v_cycle boolean;
begin
 if not private.hr_allowed(p_id,p_domain,true) then raise exception 'Edit permission required' using errcode='42501';end if;
 if p_effective is null or p_effective>timezone('Asia/Riyadh',now())::date then raise exception 'تاريخ السريان الحالي أو السابق مطلوب';end if;
 if char_length(btrim(coalesce(p_reason,'')))<3 then raise exception 'سبب التعديل مطلوب';end if;
 select * into strict e from private.hr_employees where id=p_id for update;
 if e.revision<>p_revision then raise exception 'تم تعديل السجل؛ أعد تحميله قبل الحفظ' using errcode='40001';end if;
 if p_domain='records' then
  b:=to_jsonb(e);v_manager:=nullif(p_payload->>'manager_id','')::uuid;
  with recursive a as(select id,manager_id,array[id] path from private.hr_employees where id=v_manager union all select p.id,p.manager_id,a.path||p.id from private.hr_employees p join a on p.id=a.manager_id where not p.id=any(a.path) and cardinality(a.path)<100) select exists(select 1 from a where id=e.id) into v_cycle;
  if v_cycle then raise exception 'الارتباط الإداري يسبب حلقة؛ اختر مديرًا آخر';end if;
  update private.hr_employees set full_name=btrim(p_payload->>'full_name'),department_id=(p_payload->>'department_id')::uuid,section_id=(p_payload->>'section_id')::uuid,title_id=(p_payload->>'title_id')::uuid,manager_id=v_manager,join_date=(p_payload->>'join_date')::date,effective_from=p_effective where id=e.id;
  if e.profile_id is not null then
   select profile_id into v_profile_manager from private.hr_employees where id=v_manager;
   update public.profiles p set full_name=x.full_name,employee_code=x.employee_code,department=d.name,job_title=t.title,join_date=x.join_date,manager_id=v_profile_manager from private.hr_employees x join private.hr_departments d on d.id=x.department_id join private.hr_titles t on t.id=x.title_id where x.id=e.id and p.id=e.profile_id;
  end if;
 elsif p_domain='personal' then
  select to_jsonb(p)-'employee_id' into b from private.hr_personal p where employee_id=e.id;
  update private.hr_personal set residency_number=btrim(p_payload->>'residency_number'),nationality=btrim(p_payload->>'nationality'),phone=nullif(btrim(p_payload->>'phone'),'') where employee_id=e.id;
 elsif p_domain='salary' then
  select to_jsonb(p)-'employee_id' into b from private.hr_compensation p where employee_id=e.id;
  update private.hr_compensation set basic=(p_payload->>'basic')::numeric,allowances=(p_payload->>'allowances')::numeric,effective_from=p_effective where employee_id=e.id;
 elsif p_domain='vehicles' then
  select to_jsonb(p)-'employee_id' into b from private.hr_vehicles p where employee_id=e.id;
  update private.hr_vehicles set vin=nullif(btrim(p_payload->>'vin'),''),plate=nullif(btrim(p_payload->>'plate'),''),vehicle_type=nullif(btrim(p_payload->>'vehicle_type'),'') where employee_id=e.id;
 else raise exception 'Invalid employee domain';end if;
 update private.hr_employees set revision=revision+1,updated_at=now() where id=e.id;
 if p_domain='records' then select to_jsonb(x) into a from private.hr_employees x where id=e.id;
 elsif p_domain='personal' then select to_jsonb(x)-'employee_id' into a from private.hr_personal x where employee_id=e.id;
 elsif p_domain='salary' then select to_jsonb(x)-'employee_id' into a from private.hr_compensation x where employee_id=e.id;
 else select to_jsonb(x)-'employee_id' into a from private.hr_vehicles x where employee_id=e.id;end if;
 insert into private.hr_history(employee_id,domain,before_data,after_data,effective_from,actor_id,reason)values(e.id,p_domain,b,a,p_effective,auth.uid(),btrim(p_reason));
 return private.hr_detail(e.id);
end $$;
create function private.hr_grant(p_profile uuid,p_domain text,p_scope text,p_read boolean,p_write boolean) returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.current_user_is_active() or not private.is_admin() then raise exception 'Administrator permission required' using errcode='42501';end if;
 if not exists(select 1 from public.profiles where id=p_profile and active and status='active') then raise exception 'الحساب غير نشط';end if;
 insert into private.hr_access(profile_id,domain,scope,can_read,can_write,granted_by)values(p_profile,p_domain,p_scope,p_read,p_write,auth.uid())on conflict(profile_id,domain)do update set scope=excluded.scope,can_read=excluded.can_read,can_write=excluded.can_write,granted_by=excluded.granted_by,updated_at=now();
end $$;

-- Internal checked implementations live outside the Data API. Narrow invoker RPCs.
revoke all on function private.hr_context(),private.hr_list(),private.hr_detail(uuid),private.hr_save(uuid,text,integer,jsonb,date,text),private.hr_grant(uuid,text,text,boolean,boolean) from public,anon,authenticated;
grant execute on function private.hr_context(),private.hr_list(),private.hr_detail(uuid),private.hr_save(uuid,text,integer,jsonb,date,text),private.hr_grant(uuid,text,text,boolean,boolean) to authenticated;
create function public.employee_master_context()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.hr_context()$$;
create function public.employee_master_list()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.hr_list()$$;
create function public.employee_master_detail(p_id uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.hr_detail(p_id)$$;
create function public.employee_master_save(p_id uuid,p_domain text,p_revision integer,p_payload jsonb,p_effective date,p_reason text)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.hr_save(p_id,p_domain,p_revision,p_payload,p_effective,p_reason)$$;
create function public.employee_master_grant(p_profile uuid,p_domain text,p_scope text,p_read boolean,p_write boolean)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.hr_grant(p_profile,p_domain,p_scope,p_read,p_write)$$;
revoke all on function public.employee_master_context(),public.employee_master_list(),public.employee_master_detail(uuid),public.employee_master_save(uuid,text,integer,jsonb,date,text),public.employee_master_grant(uuid,text,text,boolean,boolean) from public,anon;
grant execute on function public.employee_master_context(),public.employee_master_list(),public.employee_master_detail(uuid),public.employee_master_save(uuid,text,integer,jsonb,date,text),public.employee_master_grant(uuid,text,text,boolean,boolean) to authenticated;
comment on table private.hr_employees is 'Employee master independent from Auth; activation is a separate authorized operation.';
comment on table private.hr_compensation is 'Monthly SAR compensation; access only via explicitly scoped HR RPC permissions.';
-- Install as a private, postgres-only maintenance function via apply_migration.
-- The employee payload is supplied separately and MUST NEVER be committed.
create function private.import_employee_master(p_rows jsonb,p_source_hash text,p_dry_run boolean default true)
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
  for x in select t.job_description_id,t.title,min(d.name)department,count(distinct d.id)department_count from private.hr_titles t join private.hr_employees e on e.title_id=t.id join private.hr_departments d on d.id=e.department_id group by t.id loop
   if x.department_count<>1 then raise exception 'Conflicting department for shared description';end if;
   select * into strict v_j from public.job_descriptions where id=x.job_description_id;
   if exists(select 1 from public.employee_job_assignments a join private.hr_employees e on e.profile_id=a.profile_id where a.job_description_id=v_j.id)then
    update public.job_descriptions set title=x.title,family=x.department,status='PUBLISHED',revision=revision+1,updated_by=v_admin,updated_at=now(),published_by=coalesce(published_by,v_admin),published_at=now(),review_note='تحديث إداري للمرحلة الثانية بتوجيه الإدارة؛ دون إعادة اعتماد أو بريد أو إقرار موظف.',
     published_snapshot=jsonb_build_object('job_code',v_j.job_code,'title',x.title,'family',x.department,'job_level',v_j.job_level,'reports_to_title',v_j.reports_to_title,'purpose',v_j.purpose,'content',v_j.content,'revision',v_j.revision+1,'published_at',now())where id=v_j.id;
   elsif v_j.title is distinct from x.title or v_j.family is distinct from x.department then
    update public.job_descriptions set title=x.title,family=x.department,revision=revision+1,updated_by=v_admin,updated_at=now(),review_note='توحيد التصنيف والمسمى حسب قاعدة بيانات المرحلة الثانية.' where id=v_j.id;
   end if;
  end loop;
  -- Archive superseded proposals, retaining their complete prior state.
  update public.employee_job_change_requests r set status='ARCHIVED',archived_at=now(),archive_reason='تهيئة إدارية للمرحلة الثانية دون إعادة اعتماد',archive_snapshot=to_jsonb(r),approval_snapshot=null,manager_decided_at=null
   where status in('MANAGER_REVIEW','ADMIN_REVIEW','NEEDS_CHANGES','APPLIED')and exists(select 1 from private.hr_import_snapshots s where s.import_id=v_import and s.entity='job' and s.entity_id=r.job_description_id);
  update public.job_description_change_requests r set status='ARCHIVED',archived_at=now(),archive_snapshot=to_jsonb(r)where status='PENDING' and exists(select 1 from private.hr_import_snapshots s where s.import_id=v_import and s.entity='job' and s.entity_id=r.job_description_id);
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
