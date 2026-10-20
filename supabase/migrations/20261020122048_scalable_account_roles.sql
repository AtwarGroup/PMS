-- Additive roles: existing system roles, direct grants and workflow relations remain authoritative.
create table private.access_catalog(
 key text primary key,module text not null,label text not null,domain text,operation text not null,
 scopes text[] not null,requires_manager boolean not null default false,sort_order integer not null,
 check(domain is null or domain in('records','personal','salary','vehicles'))
);
insert into private.access_catalog values
 ('tasks.read_all','المهام','الاطلاع التنفيذي على جميع المهام',null,'read',array['all'],false,10),
 ('tasks.assign_indirect','المهام','تكليف الموظفين عبر التسلسل الإداري',null,'assign',array['team'],true,20);
insert into private.access_catalog(key,module,label,domain,operation,scopes,sort_order)
select 'employees.'||d||'.'||op,'بيانات الموظفين',label||' — '||case op when 'read' then 'عرض' else 'تعديل' end,d,op,array['team','all'],n+case op when 'read' then 0 else 1 end
from(values('records','البيانات الوظيفية',30),('personal','البيانات الشخصية',40),('salary','الرواتب',50),('vehicles','عهد المركبات',60))x(d,label,n)cross join(values('read'),('write'))y(op);
create table private.access_roles(id uuid primary key default gen_random_uuid(),name text not null unique check(length(btrim(name)) between 2 and 80),description text not null default '' check(length(description)<=500),active boolean not null default true,revision integer not null default 1,created_by uuid references public.profiles(id),updated_at timestamptz not null default now());
create table private.access_role_rules(role_id uuid not null references private.access_roles(id) on delete cascade,permission text not null references private.access_catalog(key),scope text not null check(scope in('all','team')),primary key(role_id,permission));
create table private.access_assignments(profile_id uuid not null references public.profiles(id) on delete cascade,role_id uuid not null references private.access_roles(id) on delete cascade,assigned_by uuid references public.profiles(id),created_at timestamptz not null default now(),primary key(profile_id,role_id));
create index access_assignments_role_idx on private.access_assignments(role_id);
create table private.access_direct_tasks(profile_id uuid primary key references public.profiles(id) on delete cascade,permissions text[] not null default '{}');
insert into private.access_direct_tasks select id,coalesce(permissions,'{}') from public.profiles;
create table private.access_audit(id bigint generated always as identity primary key,actor_id uuid,actor_name text not null,action text not null,target_id text not null,before_data jsonb,after_data jsonb,created_at timestamptz not null default now());
create index access_audit_created_idx on private.access_audit(created_at desc,id desc);
do $$declare t text;begin
 foreach t in array array['access_catalog','access_roles','access_role_rules','access_assignments','access_direct_tasks','access_audit']loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 execute format('create policy access_internal_only on private.%I for all to authenticated using(false) with check(false)',t);
 end loop;
end$$;
create function private.access_log(p_action text,p_target text,p_before jsonb,p_after jsonb)returns void language sql security definer set search_path=pg_catalog,public,private as $$
 insert into private.access_audit(actor_id,actor_name,action,target_id,before_data,after_data)
 values(auth.uid(),coalesce((select full_name from public.profiles where id=auth.uid()),'خدمة النظام'),p_action,p_target,p_before,p_after)
$$;
create function private.access_rebuild_tasks(p_profile uuid)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 -- Row lock serializes direct-grant changes, assignment edits and role edits for this account.
 perform 1 from public.profiles where id=p_profile for update;
 update public.profiles set permissions=array(select distinct permission from(
 select unnest(d.permissions) permission from private.access_direct_tasks d where d.profile_id=p_profile
 union all select g.permission from private.access_assignments a join private.access_roles r on r.id=a.role_id and r.active join private.access_role_rules g on g.role_id=r.id join private.access_catalog c on c.key=g.permission where a.profile_id=p_profile and c.domain is null
 )x order by permission)where id=p_profile;
end$$;
create function private.access_capture_profile()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if tg_op='INSERT' then insert into private.access_direct_tasks values(new.id,coalesce(new.permissions,'{}'))on conflict do nothing;
 else
 if (old.role,old.active,old.status)is distinct from(new.role,new.active,new.status)then
 perform private.access_log('ACCOUNT_ACCESS_CHANGED',new.id::text,jsonb_build_object('role',old.role,'active',old.active,'status',old.status),jsonb_build_object('role',new.role,'active',new.active,'status',new.status));end if;
 end if;return new;
end$$;
create trigger access_profile_created after insert on public.profiles for each row execute function private.access_capture_profile();
create trigger access_profile_changed after update of role,active,status on public.profiles for each row execute function private.access_capture_profile();
create function private.access_audit_hr()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if tg_op='INSERT' or to_jsonb(old)is distinct from to_jsonb(new)then perform private.access_log('DIRECT_EMPLOYEE_GRANT',new.profile_id::text,case when tg_op='UPDATE' then to_jsonb(old)else null end,to_jsonb(new));end if;return new;
end$$;
create trigger access_hr_grant_changed after insert or update on private.hr_access for each row execute function private.access_audit_hr();
create function private.access_set_task(p_profile uuid,p_key text,p_enabled boolean)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare b jsonb;
begin
 if not private.is_admin()then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_enabled is null or p_key not in('tasks.read_all','tasks.assign_indirect')then raise exception 'Invalid permission';end if;
 perform 1 from public.profiles where id=p_profile and(not p_enabled or p_key<>'tasks.assign_indirect' or role='manager')for update;
 if not found then raise exception 'Manager account required for indirect assignment';end if;
 select to_jsonb(d)into b from private.access_direct_tasks d where profile_id=p_profile;
 insert into private.access_direct_tasks values(p_profile,'{}')on conflict do nothing;
 update private.access_direct_tasks set permissions=case when p_enabled then array(select distinct x from unnest(permissions||array[p_key])x)else array_remove(permissions,p_key)end where profile_id=p_profile;
 perform private.access_rebuild_tasks(p_profile);
 perform private.access_log('DIRECT_TASK_GRANT',p_profile::text,b,(select to_jsonb(d)from private.access_direct_tasks d where profile_id=p_profile));
end$$;
create or replace function public.admin_set_executive_task_access(p_profile_id uuid,p_enabled boolean)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.access_set_task(p_profile_id,'tasks.read_all',p_enabled)$$;
create or replace function public.admin_set_indirect_task_assignment(p_profile_id uuid,p_enabled boolean)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.access_set_task(p_profile_id,'tasks.assign_indirect',p_enabled)$$;
create or replace function private.hr_allowed(p_employee uuid,p_domain text,p_write boolean default false)returns boolean language sql stable security definer set search_path=pg_catalog,public,private as $$
 select private.current_user_is_active() and(
 private.is_admin()
 or exists(select 1 from private.hr_access g where g.profile_id=auth.uid() and g.domain=p_domain and case when p_write then g.can_write else g.can_read end and(g.scope='all' or private.hr_in_team(p_employee)))
 or exists(select 1 from private.access_assignments a join private.access_roles r on r.id=a.role_id and r.active join private.access_role_rules g on g.role_id=r.id join private.access_catalog c on c.key=g.permission where a.profile_id=auth.uid() and c.domain=p_domain and c.operation=case when p_write then 'write'else 'read'end and(g.scope='all' or private.hr_in_team(p_employee)))
 or(p_domain='records' and not p_write and private.hr_in_team(p_employee)))
$$;
create function private.access_role_save(p_id uuid,p_revision integer,p_name text,p_description text,p_active boolean,p_rules jsonb)returns uuid language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare rid uuid:=p_id;b jsonb;u uuid;
begin
 if not private.is_admin()then raise exception 'Administrator access required' using errcode='42501';end if;
 if jsonb_typeof(p_rules)<>'array' or p_rules is null or p_active is null or length(btrim(p_name))not between 2 and 80 or p_name is null then raise exception 'Invalid role definition';end if;
 if exists(select 1 from jsonb_to_recordset(p_rules)x(permission text,scope text)left join private.access_catalog c on c.key=x.permission where c.key is null or x.scope is null or not x.scope=any(c.scopes))then raise exception 'Unsupported permission or scope';end if;
 if exists(select 1 from jsonb_to_recordset(p_rules)x(permission text,scope text)join private.access_catalog c on c.key=x.permission where c.operation='write' and not exists(select 1 from jsonb_to_recordset(p_rules)y(permission text,scope text)where y.permission=replace(c.key,'.write','.read')and(y.scope='all' or y.scope=x.scope)))then raise exception 'صلاحية التعديل تتطلب العرض في النطاق نفسه أو نطاق أوسع';end if;
 if rid is null then
 insert into private.access_roles(name,description,active,created_by)values(btrim(p_name),coalesce(btrim(p_description),''),p_active,auth.uid())returning id into rid;
 else
 select to_jsonb(r)||jsonb_build_object('rules',(select coalesce(jsonb_agg(to_jsonb(g)),'[]')from private.access_role_rules g where g.role_id=r.id))into b from private.access_roles r where id=rid for update;
 if not found then raise exception 'Role not found';end if;
 if (b->>'revision')::integer is distinct from p_revision then raise exception 'تم تعديل الدور من مستخدم آخر. حدّث البيانات.' using errcode='40001';end if;
 if exists(select 1 from private.access_assignments a join public.profiles p on p.id=a.profile_id where a.role_id=rid and p.role<>'manager')and exists(select 1 from jsonb_to_recordset(p_rules)x(permission text)join private.access_catalog c on c.key=x.permission where c.requires_manager)then raise exception 'هذا الدور مسند لحساب غير مدير ولا يمكن إضافة صلاحية التكليف غير المباشر';end if;
 update private.access_roles set name=btrim(p_name),description=coalesce(btrim(p_description),''),active=p_active,revision=revision+1,updated_at=now()where id=rid;
 end if;
 delete from private.access_role_rules where role_id=rid;
 insert into private.access_role_rules select rid,x.permission,x.scope from jsonb_to_recordset(p_rules)x(permission text,scope text);
 for u in select profile_id from private.access_assignments where role_id=rid order by profile_id loop perform private.access_rebuild_tasks(u);end loop;
 perform private.access_log('ROLE_SAVED',rid::text,b,(select to_jsonb(r)||jsonb_build_object('rules',p_rules)from private.access_roles r where id=rid));
 return rid;
end$$;
create function private.access_assign(p_profile uuid,p_roles uuid[],p_expected uuid[])returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare b uuid[];rid uuid;
begin
 if not private.is_admin()then raise exception 'Administrator access required' using errcode='42501';end if;
 -- Lock roles before profile to share lock ordering with role edits.
 perform 1 from private.access_roles where id=any(coalesce(p_roles,'{}')||coalesce(p_expected,'{}'))order by id for update;
 perform 1 from public.profiles where id=p_profile for update;
 if not found then raise exception 'Account not found';end if;
 select coalesce(array_agg(role_id order by role_id),'{}')into b from private.access_assignments where profile_id=p_profile;
 if b is distinct from array(select distinct x from unnest(coalesce(p_expected,'{}'))x order by x)then raise exception 'تم تغيير أدوار الحساب. حدّث البيانات.' using errcode='40001';end if;
 if exists(select 1 from unnest(coalesce(p_roles,'{}'))x left join private.access_roles r on r.id=x where r.id is null or(not r.active and not r.id=any(b)))then raise exception 'Role unavailable';end if;
 if exists(select 1 from private.access_role_rules g join private.access_catalog c on c.key=g.permission where g.role_id=any(p_roles)and c.requires_manager)and not exists(select 1 from public.profiles where id=p_profile and role='manager')then raise exception 'صلاحية التكليف عبر التسلسل الإداري تتطلب حساب مدير';end if;
 delete from private.access_assignments where profile_id=p_profile and not role_id=any(coalesce(p_roles,'{}'));
 insert into private.access_assignments(profile_id,role_id,assigned_by)select p_profile,x,auth.uid()from(select distinct unnest(coalesce(p_roles,'{}'))x)t on conflict do nothing;
 perform private.access_rebuild_tasks(p_profile);
 perform private.access_log('ROLES_ASSIGNED',p_profile::text,to_jsonb(b),to_jsonb(coalesce(p_roles,'{}')));
end$$;
create function private.access_admin_context()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.is_admin()then raise exception 'Administrator access required' using errcode='42501';end if;
 return jsonb_build_object(
 'catalog',(select coalesce(jsonb_agg(to_jsonb(c)order by sort_order),'[]')from private.access_catalog c),
 'roles',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('rules',(select coalesce(jsonb_agg(to_jsonb(g)order by permission),'[]')from private.access_role_rules g where g.role_id=r.id))order by r.name),'[]')from private.access_roles r),
 'assignments',(select coalesce(jsonb_agg(to_jsonb(a)),'[]')from private.access_assignments a),
 'direct_tasks',(select coalesce(jsonb_agg(to_jsonb(d)),'[]')from private.access_direct_tasks d),
 'direct_hr',(select coalesce(jsonb_agg(to_jsonb(g)),'[]')from private.hr_access g),
 'users',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',p.email,'role',p.role,'active',p.active,'status',p.status,'job_title',p.job_title,'department',p.department,'employee_code',p.employee_code,'manager_id',p.manager_id,'join_date',p.join_date,'permissions',p.permissions)order by full_name),'[]')from public.profiles p),
 'pending_employees',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'email',e.email,'department',d.name,'title',t.title)order by employee_code::bigint),'[]')from private.hr_employees e join private.hr_departments d on d.id=e.department_id join private.hr_titles t on t.id=e.title_id where e.profile_id is null));
end$$;
create function private.access_audit_list(p_before bigint default null)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.is_admin()then raise exception 'Administrator access required' using errcode='42501';end if;
 return(select coalesce(jsonb_agg(to_jsonb(x)order by id desc),'[]')from(select * from private.access_audit where p_before is null or id<p_before order by id desc limit 50)x);
end$$;
-- All user-facing wrappers are invokers; only checked private implementations bypass RLS.
create function public.access_admin_context()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.access_admin_context()$$;
create function public.access_role_save(p_id uuid,p_revision integer,p_name text,p_description text,p_active boolean,p_rules jsonb)returns uuid language sql security invoker set search_path=pg_catalog,private as $$select private.access_role_save(p_id,p_revision,p_name,p_description,p_active,p_rules)$$;
create function public.access_assign_roles(p_profile uuid,p_roles uuid[],p_expected uuid[])returns void language sql security invoker set search_path=pg_catalog,private as $$select private.access_assign(p_profile,p_roles,p_expected)$$;
create function public.access_audit_list(p_before bigint default null)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.access_audit_list(p_before)$$;
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'access_%'loop execute format('revoke all on function %s from public,anon,authenticated',f.signature);end loop;
end$$;
grant execute on function private.access_set_task(uuid,text,boolean),private.access_admin_context(),private.access_role_save(uuid,integer,text,text,boolean,jsonb),private.access_assign(uuid,uuid[],uuid[]),private.access_audit_list(bigint)to authenticated;
revoke all on function public.access_admin_context(),public.access_role_save(uuid,integer,text,text,boolean,jsonb),public.access_assign_roles(uuid,uuid[],uuid[]),public.access_audit_list(bigint),public.admin_set_executive_task_access(uuid,boolean),public.admin_set_indirect_task_assignment(uuid,boolean)from public,anon;
grant execute on function public.access_admin_context(),public.access_role_save(uuid,integer,text,text,boolean,jsonb),public.access_assign_roles(uuid,uuid[],uuid[]),public.access_audit_list(bigint),public.admin_set_executive_task_access(uuid,boolean),public.admin_set_indirect_task_assignment(uuid,boolean)to authenticated;
-- Employment type confirmed by the business for all current employees; no invitations or approvals.
alter table private.hr_employees add column employment_type text not null default 'دوام كامل';
update public.profiles set employment_type='دوام كامل' where employment_type is distinct from 'دوام كامل';
alter table public.profiles alter column employment_type set default 'دوام كامل';
create function private.access_account_update(p_profile uuid,p_role text,p_active boolean)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if not private.is_admin()then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_role not in('employee','manager','admin')or p_role is null or p_active is null then raise exception 'Invalid account settings';end if;
 if p_profile=auth.uid()and(p_role<>'admin' or not p_active)then raise exception 'لا يمكنك إيقاف حسابك أو إزالة صلاحيتك الإدارية';end if;
 update public.profiles set role=p_role,active=p_active,status=case when p_active then 'active'else 'inactive'end where id=p_profile;
 if not found then raise exception 'Account not found';end if;
end$$;
create function public.access_account_update(p_profile uuid,p_role text,p_active boolean)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.access_account_update(p_profile,p_role,p_active)$$;
create function private.access_direct_save(p_profile uuid,p_rules jsonb)returns void language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare k text;d text;r text;w text;prior text;
begin
 if not private.is_admin()then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_rules is null or jsonb_typeof(p_rules)<>'array'then raise exception 'Invalid grants';end if;
 perform 1 from public.profiles where id=p_profile for update;if not found then raise exception 'Account not found';end if;
 if exists(select 1 from jsonb_to_recordset(p_rules)x(permission text,scope text)left join private.access_catalog c on c.key=x.permission where c.key is null or x.scope is null or not x.scope=any(c.scopes))then raise exception 'Invalid permission or scope';end if;
 foreach k in array array['tasks.read_all','tasks.assign_indirect']loop
 if exists(select 1 from private.access_direct_tasks where profile_id=p_profile and k=any(permissions))is distinct from exists(select 1 from jsonb_to_recordset(p_rules)x(permission text)where x.permission=k)then
 perform private.access_set_task(p_profile,k,exists(select 1 from jsonb_to_recordset(p_rules)x(permission text)where x.permission=k));end if;
 end loop;
 foreach d in array array['records','personal','salary','vehicles']loop
 r:=null;w:=null;select scope into r from jsonb_to_recordset(p_rules)x(permission text,scope text)where permission='employees.'||d||'.read';select scope into w from jsonb_to_recordset(p_rules)x(permission text,scope text)where permission='employees.'||d||'.write';
 if w is not null and r is distinct from w then raise exception 'المنح المباشر يتطلب نطاق عرض وتعديل متطابقًا. استخدم الأدوار للنطاقات المستقلة.';end if;
 if exists(select 1 from private.hr_access where profile_id=p_profile and domain=d and(can_read is distinct from(r is not null)or can_write is distinct from(w is not null)or(r is not null and scope<>r)))or(r is not null and not exists(select 1 from private.hr_access where profile_id=p_profile and domain=d))then
 perform private.hr_grant(p_profile,d,coalesce(r,w,'team'),r is not null,w is not null);end if;
 end loop;
end$$;
create function public.access_direct_save(p_profile uuid,p_rules jsonb)returns void language sql security invoker set search_path=pg_catalog,private as $$select private.access_direct_save(p_profile,p_rules)$$;
create function private.access_capture_admin_audit()returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if new.action in('USER_CREATE','PASSWORD_RESET','USER_DELETE')then insert into private.access_audit(actor_id,actor_name,action,target_id,before_data,after_data)values(new.actor_id,coalesce(new.actor_name_snapshot,'مسؤول النظام'),new.action,coalesce(new.target_id,''),null,new.detail-'password');end if;return new;
end$$;
create trigger access_capture_admin_action after insert on public.admin_audit_log for each row execute function private.access_capture_admin_audit();
revoke all on function private.access_account_update(uuid,text,boolean),private.access_direct_save(uuid,jsonb),private.access_capture_admin_audit()from public,anon,authenticated;
grant execute on function private.access_account_update(uuid,text,boolean),private.access_direct_save(uuid,jsonb)to authenticated;
revoke all on function public.access_account_update(uuid,text,boolean),public.access_direct_save(uuid,jsonb)from public,anon;
grant execute on function public.access_account_update(uuid,text,boolean),public.access_direct_save(uuid,jsonb)to authenticated;
