create table public.projects (
 id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 2 and 200),
 objective text not null default '' check(length(objective)<=5000), deliverables text not null default '' check(length(deliverables)<=5000),
 manager_id uuid not null references public.profiles(id), sponsor_id uuid not null references public.profiles(id),
 created_by uuid not null references public.profiles(id), start_date date not null, due_date date not null,
 status text not null default 'PLANNING' check(status in ('PLANNING','ACTIVE','PAUSED','CLOSED','CANCELLED')),
 health text not null default 'ON_TRACK' check(health in ('ON_TRACK','AT_RISK','BLOCKED')),
 revision integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(due_date>=start_date), check(manager_id<>sponsor_id)
);
create table public.project_members(project_id uuid references public.projects(id) on delete cascade, user_id uuid references public.profiles(id), primary key(project_id,user_id));
create table public.project_phases(id uuid primary key default gen_random_uuid(),project_id uuid not null references public.projects(id) on delete cascade,title text not null check(length(title) between 1 and 200),position integer not null default 0);
alter table public.tasks add column project_id uuid references public.projects(id), add column project_phase_id uuid references public.project_phases(id), add column project_weight numeric not null default 1 check(project_weight>0 and project_weight<=1000), add column project_milestone boolean not null default false;
create table public.project_dependencies(project_id uuid not null references public.projects(id) on delete cascade, task_id uuid references public.tasks(id), predecessor_id uuid references public.tasks(id),primary key(task_id,predecessor_id),check(task_id<>predecessor_id));
create table public.project_messages(id uuid primary key default gen_random_uuid(),project_id uuid not null references public.projects(id) on delete cascade,author_id uuid not null references public.profiles(id),author_name text not null,body text not null check(length(body) between 1 and 4000),task_id uuid references public.tasks(id),mentions uuid[] not null default '{}',created_at timestamptz not null default now());
create table public.project_events(id uuid primary key default gen_random_uuid(),project_id uuid not null references public.projects(id) on delete cascade,actor_id uuid references public.profiles(id),actor_name text not null,action text not null,detail text not null,created_at timestamptz not null default now());
create table public.project_risks(id uuid primary key default gen_random_uuid(),project_id uuid not null references public.projects(id) on delete cascade,title text not null check(length(title) between 2 and 500),owner_id uuid not null references public.profiles(id),due_date date not null,status text not null default 'OPEN' check(status in ('OPEN','RESOLVED')));
create index on public.projects(manager_id); create index on public.projects(sponsor_id); create index on public.projects(created_by);
create index on public.project_members(user_id);create index on public.project_phases(project_id);
create index on public.tasks(project_id);create index on public.tasks(project_phase_id);
create index on public.project_dependencies(project_id);create index on public.project_dependencies(predecessor_id);
create index on public.project_messages(project_id,created_at);create index on public.project_messages(author_id);create index on public.project_messages(task_id);
create index on public.project_events(project_id,created_at);create index on public.project_events(actor_id);
create index on public.project_risks(project_id);create index on public.project_risks(owner_id);

create function private.project_access(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.current_user_is_active() and exists(select 1 from public.projects p where p.id=p_id and (private.is_admin() or p.manager_id=auth.uid() or p.sponsor_id=auth.uid() or exists(select 1 from public.project_members m where m.project_id=p.id and m.user_id=auth.uid())))
$$;
create function private.project_manage(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.current_user_is_active() and exists(select 1 from public.projects p where p.id=p_id and (private.is_admin() or p.manager_id=auth.uid()))
$$;
create function private.project_event(p_id uuid,p_action text,p_detail text) returns void language sql security definer set search_path='' as $$
 insert into public.project_events(project_id,actor_id,actor_name,action,detail) select p_id,auth.uid(),full_name,p_action,p_detail from public.profiles where id=auth.uid()
$$;

do $$ declare t text;begin foreach t in array array['projects','project_members','project_phases','project_dependencies','project_messages','project_events','project_risks'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy project_read on public.%I for select to authenticated using (private.project_access(%I))',t,case when t='projects' then 'id' else 'project_id' end);
 end loop;end $$;

create function private.project_directory() returns table(id uuid,full_name text,role text) language sql stable security definer set search_path='' as $$
 select p.id,p.full_name,p.role from public.profiles p where p.active and p.status='active' and private.current_user_is_active() and (private.current_user_role() in ('admin','manager') or exists(select 1 from public.projects x where x.manager_id=auth.uid())) order by p.full_name
$$;
create function public.project_directory() returns table(id uuid,full_name text,role text) language sql set search_path='' as $$ select * from private.project_directory() $$;
create function private.project_people(p_id uuid) returns table(id uuid,full_name text,role text) language sql stable security definer set search_path='' as $$
 select u.id,u.full_name,u.role from public.profiles u where private.project_access(p_id) and exists(select 1 from public.projects p where p.id=p_id and (u.id in(p.manager_id,p.sponsor_id) or exists(select 1 from public.project_members m where m.project_id=p_id and m.user_id=u.id))) order by u.full_name
$$;
create function public.project_people(p_id uuid) returns table(id uuid,full_name text,role text) language sql set search_path='' as $$ select * from private.project_people(p_id) $$;

create function private.project_command(p_id uuid,p_revision integer,p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.projects%rowtype;t public.tasks%rowtype; v_id uuid;v_uid uuid:=auth.uid();v_members uuid[];v_assignee uuid;v_predecessor uuid;v_phase uuid;v_mentions uuid[];v_count integer;v_text text;
begin
 if v_uid is null or not private.current_user_is_active() then raise exception 'ATWAR_AUTH: inactive user';end if;
 if p_action='create' then
  if private.current_user_role() not in ('admin','manager') then raise exception 'إنشاء المشروع متاح للمدير ومسؤول النظام';end if;
  if not private.is_admin() and (p_data->>'manager_id')::uuid<>v_uid then raise exception 'حدد نفسك مديرًا للمشروع أو اطلب من مسؤول النظام إنشاءه';end if;
  if not private.user_is_active((p_data->>'manager_id')::uuid) or not private.user_is_active((p_data->>'sponsor_id')::uuid) then raise exception 'اختر مديرًا وراعيًا نشطين';end if;
  insert into public.projects(title,objective,deliverables,manager_id,sponsor_id,created_by,start_date,due_date) values(btrim(p_data->>'title'),coalesce(p_data->>'objective',''),coalesce(p_data->>'deliverables',''),(p_data->>'manager_id')::uuid,(p_data->>'sponsor_id')::uuid,v_uid,(p_data->>'start_date')::date,(p_data->>'due_date')::date) returning * into p;
  v_id:=p.id;
 else
  select * into p from public.projects where id=p_id for update;
  if not found or not private.project_access(p_id) then raise exception 'المشروع غير متاح';end if;
  if p_action='message' then
   if p.status in ('CLOSED','CANCELLED') then raise exception 'المشروع مغلق للقراءة فقط';end if;
   v_text:=btrim(p_data->>'body');v_id:=nullif(p_data->>'task_id','')::uuid;
   if v_id is not null and not exists(select 1 from public.tasks where id=v_id and project_id=p.id and deleted_at is null) then raise exception 'المهمة لا تنتمي للمشروع';end if;
   select coalesce(array_agg(value::uuid),'{}') into v_mentions from jsonb_array_elements_text(coalesce(p_data->'mentions','[]'));
   if exists(select 1 from unnest(v_mentions) u where not (u in(p.manager_id,p.sponsor_id) or exists(select 1 from public.project_members m where m.project_id=p.id and m.user_id=u))) then raise exception 'الإشارة متاحة لأعضاء المشروع فقط';end if;
   insert into public.project_messages(project_id,author_id,author_name,body,task_id,mentions) select p.id,v_uid,full_name,v_text,v_id,v_mentions from public.profiles where id=v_uid returning id into v_id;
   insert into public.notifications(recipient_id,task_id,type,title,message) select u,null,'project_mention','إشارة في مشروع: '||left(p.title,160),left(v_text,1800) from (select distinct unnest(v_mentions) u) x where u<>v_uid;
   return v_id;
  end if;
  if p.revision<>p_revision then raise exception 'ATWAR_CONFLICT: project changed';end if;
  if p.status in ('CLOSED','CANCELLED') then raise exception 'المشروع مغلق للقراءة فقط';end if;
  if p_action='close' then
   if v_uid<>p.sponsor_id then raise exception 'راعي المشروع وحده يعتمد إغلاقه';end if;
   if not exists(select 1 from public.tasks where project_id=p.id and deleted_at is null) or exists(select 1 from public.tasks where project_id=p.id and deleted_at is null and status not in('مكتملة','ملغاة')) then raise exception 'أكمل واعتمد مهام المشروع قبل إغلاقه';end if;
   update public.projects set status='CLOSED' where id=p.id;
  else
   if not private.project_manage(p.id) then raise exception 'هذا الإجراء متاح لمدير المشروع';end if;
   if p_action='settings' then
    if coalesce(p_data->>'status','') not in('PLANNING','ACTIVE','PAUSED') then raise exception 'حالة المشروع غير صالحة';end if;
    if exists(select 1 from public.tasks where project_id=p.id and deleted_at is null and (start_date<(p_data->>'start_date')::date or due_date>(p_data->>'due_date')::date)) then raise exception 'مدة المشروع يجب أن تشمل جميع مهامه';end if;
    if (p_data->>'start_date')::date>(p_data->>'due_date')::date then raise exception 'راجع ترتيب المواعيد';end if;
    update public.projects set title=btrim(p_data->>'title'),objective=p_data->>'objective',deliverables=p_data->>'deliverables',start_date=(p_data->>'start_date')::date,due_date=(p_data->>'due_date')::date,status=p_data->>'status',health=p_data->>'health' where id=p.id;
   elsif p_action='phase' then
    insert into public.project_phases(project_id,title,position) values(p.id,btrim(p_data->>'title'),(select count(*) from public.project_phases where project_id=p.id)) returning id into v_id;
   elsif p_action='task' then
    v_assignee:=(p_data->>'assignee_id')::uuid;v_phase:=nullif(p_data->>'phase_id','')::uuid;
    if not private.user_is_active(v_assignee) or not(v_assignee in(p.manager_id,p.sponsor_id) or exists(select 1 from public.project_members where project_id=p.id and user_id=v_assignee)) then raise exception 'اختر عضوًا نشطًا من فريق المشروع';end if;
    if v_phase is not null and not exists(select 1 from public.project_phases where id=v_phase and project_id=p.id) then raise exception 'المرحلة لا تنتمي للمشروع';end if;
    if (p_data->>'start_date')::date<p.start_date or (p_data->>'due_date')::date>p.due_date then raise exception 'مواعيد المهمة يجب أن تقع داخل مدة المشروع';end if;
    insert into public.tasks(title,description,task_type,creator_id,assignee_id,creator_name_snapshot,assignee_name_snapshot,start_date,due_date,project_id,project_phase_id,project_weight,project_milestone) select btrim(p_data->>'title'),coalesce(p_data->>'description',''),'project',v_uid,v_assignee,(select full_name from public.profiles where id=v_uid),u.full_name,(p_data->>'start_date')::date,(p_data->>'due_date')::date,p.id,v_phase,coalesce((p_data->>'weight')::numeric,1),coalesce((p_data->>'milestone')::boolean,false) from public.profiles u where u.id=v_assignee returning id into v_id;
   elsif p_action='dependency' then
    v_id:=(p_data->>'task_id')::uuid;v_predecessor:=(p_data->>'predecessor_id')::uuid;
    select count(*) into v_count from public.tasks where id in(v_id,v_predecessor) and project_id=p.id and deleted_at is null;
    if v_count<>2 then raise exception 'اختر مهمتين مختلفتين من المشروع';end if;
    if exists(with recursive chain(id) as (select predecessor_id from public.project_dependencies where task_id=v_predecessor union select d.predecessor_id from public.project_dependencies d join chain c on d.task_id=c.id) select 1 from chain where id=v_id) then raise exception 'لا يمكن إنشاء تبعية دائرية';end if;
    insert into public.project_dependencies values(p.id,v_id,v_predecessor) on conflict do nothing;
   elsif p_action='remove_dependency' then
    delete from public.project_dependencies where project_id=p.id and task_id=(p_data->>'task_id')::uuid and predecessor_id=(p_data->>'predecessor_id')::uuid;
   elsif p_action='risk' then
    v_assignee:=(p_data->>'owner_id')::uuid;
    if not(v_assignee in(p.manager_id,p.sponsor_id) or exists(select 1 from public.project_members where project_id=p.id and user_id=v_assignee)) then raise exception 'اختر مسؤولًا من المشروع';end if;
    insert into public.project_risks(project_id,title,owner_id,due_date) values(p.id,btrim(p_data->>'title'),v_assignee,(p_data->>'due_date')::date) returning id into v_id;
   elsif p_action='resolve_risk' then
    update public.project_risks set status='RESOLVED' where id=(p_data->>'id')::uuid and project_id=p.id;
   elsif p_action<>'members' then raise exception 'إجراء غير معروف';end if;
  end if;
  update public.projects set revision=revision+1,updated_at=now() where id=p.id;
 end if;
 if p_action in ('create','members') then
  select coalesce(array_agg(distinct value::uuid),'{}') into v_members from jsonb_array_elements_text(coalesce(p_data->'members','[]'));
  if exists(select 1 from unnest(v_members) u where not private.user_is_active(u)) then raise exception 'أحد أعضاء الفريق غير نشط';end if;
  if exists(select 1 from public.tasks where project_id=p.id and deleted_at is null and assignee_id not in(p.manager_id,p.sponsor_id) and not(assignee_id=any(v_members))) then raise exception 'لا يمكن إزالة عضو لديه مهام بالمشروع';end if;
  delete from public.project_members where project_id=p.id;
  insert into public.project_members select p.id,unnest(v_members);
 end if;
 perform private.project_event(p.id,p_action,coalesce(p_data->>'title',p_data->>'reason',p_action));
 return coalesce(v_id,p.id);
end $$;
create function public.project_command(p_id uuid,p_revision integer,p_action text,p_data jsonb) returns uuid language sql set search_path='' as $$ select private.project_command(p_id,p_revision,p_action,p_data) $$;

-- Route only project tasks through their own strict workflow; preserve all existing task behavior.
create function private.validate_project_task(o public.tasks,n public.tasks) returns public.tasks language plpgsql security definer set search_path='' as $$
declare p public.projects%rowtype;v_uid uuid:=auth.uid();v_manager boolean;v_approver uuid;v_allowed text[]:=array['updated_at','revision','completion_requires_approval','approval_commissioner_id'];
begin
 select * into p from public.projects where id=o.project_id for update;
 if not private.project_access(p.id) or p.status in('CLOSED','CANCELLED') then raise exception 'المشروع غير متاح للتعديل';end if;
 v_manager:=private.project_manage(p.id);v_approver:=case when o.assignee_id=p.manager_id then p.sponsor_id else p.manager_id end;
 if o.status in('قيد الانتظار','قيد التنفيذ') and n.status=o.status then
  if v_manager then v_allowed:=v_allowed||array['title','description','start_date','due_date','project_phase_id','project_weight','project_milestone','notes','manager_notes','priority','progress'];
  elsif o.assignee_id=v_uid then v_allowed:=v_allowed||array['progress','notes'];else raise exception 'المهمة غير متاحة للتعديل';end if;
 elsif o.status='قيد الانتظار' and n.status='قيد التنفيذ' then
  if v_uid<>o.assignee_id then raise exception 'المكلف وحده يبدأ المهمة';end if;
  if exists(select 1 from public.project_dependencies d join public.tasks t on t.id=d.predecessor_id where d.task_id=o.id and t.status<>'مكتملة') then raise exception 'أكمل واعتمد المهام السابقة أولًا';end if;
  n.started_at:=now();v_allowed:=v_allowed||array['status','started_at'];
 elsif o.status='قيد التنفيذ' and n.status='بانتظار الاعتماد' then
  if v_uid<>o.assignee_id or n.progress<>100 then raise exception 'المكلف يرسل المهمة بعد إكمالها 100%%';end if;
  n.submitted_at:=now();v_allowed:=v_allowed||array['status','progress','submitted_at'];
 elsif o.status='بانتظار الاعتماد' and n.status in('مكتملة','قيد التنفيذ') then
  if v_uid<>v_approver or v_uid=o.assignee_id then raise exception 'اعتماد المهمة لصاحب الصلاحية المحدد بالمشروع';end if;
  v_allowed:=v_allowed||array['status','progress','manager_notes','approved_at','approved_by_id','approved_by_name_snapshot','completed_at','actual_end_date','returned_at','returned_by_id','returned_by_name_snapshot'];
  if n.status='مكتملة' then n.progress:=100;n.approved_at:=now();n.approved_by_id:=v_uid;select full_name into n.approved_by_name_snapshot from public.profiles where id=v_uid;n.completed_at:=now();n.actual_end_date:=current_date;
  else n.progress:=least(n.progress,95);n.returned_at:=now();n.returned_by_id:=v_uid;select full_name into n.returned_by_name_snapshot from public.profiles where id=v_uid;end if;
 else raise exception 'انتقال حالة غير مسموح للمهمة';end if;
 if (to_jsonb(o)-v_allowed) is distinct from (to_jsonb(n)-v_allowed) then raise exception 'حقول المهمة محمية أو تحتاج صلاحية مدير المشروع';end if;
 if n.start_date<p.start_date or n.due_date>p.due_date or n.start_date is null or n.due_date is null then raise exception 'راجع مواعيد المهمة ضمن مدة المشروع';end if;
 if n.project_phase_id is not null and not exists(select 1 from public.project_phases where id=n.project_phase_id and project_id=p.id) then raise exception 'مرحلة غير صالحة';end if;
 if (n.start_date is distinct from o.start_date or n.due_date is distinct from o.due_date) and (not v_manager or nullif(btrim(n.manager_notes),'') is null or n.manager_notes is not distinct from o.manager_notes) then raise exception 'إعادة الجدولة تتطلب مدير المشروع وسببًا جديدًا';end if;
 n.revision:=o.revision+1;n.completion_requires_approval:=true;n.approval_commissioner_id:=v_approver;
 perform private.project_event(p.id,'TASK_UPDATE',n.title||' — '||n.status);
 return n;
end $$;

create function private.guard_project_task_insert() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.projects%rowtype;begin
 if tg_op='UPDATE' and (new.project_id is distinct from old.project_id or (old.project_id is null and (new.project_phase_id is distinct from old.project_phase_id or new.project_weight is distinct from old.project_weight or new.project_milestone is distinct from old.project_milestone))) then raise exception 'ربط المشروع محمي';end if;
 if tg_op='INSERT' and new.project_id is not null then
  select * into p from public.projects where id=new.project_id;
  if not private.project_manage(p.id) or p.status in('CLOSED','CANCELLED') then raise exception 'إنشاء المهمة متاح لمدير المشروع';end if;
  if new.assignee_id not in(p.manager_id,p.sponsor_id) and not exists(select 1 from public.project_members where project_id=p.id and user_id=new.assignee_id) then raise exception 'المكلف ليس عضوًا بالمشروع';end if;
  if new.start_date is null or new.due_date is null or new.start_date<p.start_date or new.due_date>p.due_date then raise exception 'مواعيد المهمة خارج المشروع';end if;
  if new.project_phase_id is not null and not exists(select 1 from public.project_phases where id=new.project_phase_id and project_id=p.id) then raise exception 'مرحلة غير صالحة';end if;
  if new.status<>'قيد الانتظار' or new.progress<>0 or new.creator_id<>auth.uid() then raise exception 'بيانات إنشاء المهمة غير صالحة';end if;
 end if;return new;end $$;
create trigger a_project_task_guard before insert or update on public.tasks for each row execute function private.guard_project_task_insert();

do $$ declare s text;begin
 s:=pg_get_functiondef('private.validate_task_workflow()'::regprocedure);
 s:=replace(s,'begin'||chr(10),'begin'||chr(10)||' if old.project_id is not null then return private.validate_project_task(old,new); end if;'||chr(10));execute s;
 s:=pg_get_functiondef('private.enforce_task_schedule_owner()'::regprocedure);
 s:=regexp_replace(s,'begin','begin'||chr(10)||'  if old.project_id is not null and private.project_manage(old.project_id) then return new; end if;');execute s;
 s:=pg_get_functiondef('private.classify_task_completion()'::regprocedure);
 s:=replace(s,'begin'||chr(10),'begin'||chr(10)||' if new.project_id is not null then new.completion_requires_approval:=true; select case when new.assignee_id=p.manager_id then p.sponsor_id else p.manager_id end into new.approval_commissioner_id from public.projects p where p.id=new.project_id; return new; end if;'||chr(10));execute s;
 s:=pg_get_functiondef('private.create_task_notification()'::regprocedure);
 s:=replace(s,'if new.creator_id<>new.assignee_id then v_manager_id:=new.creator_id;', 'if new.project_id is not null then v_manager_id:=new.approval_commissioner_id; elsif new.creator_id<>new.assignee_id then v_manager_id:=new.creator_id;');execute s;
end $$;
-- Add project membership without granting unrelated employee data.
create or replace function private.can_view_task(target_task uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.current_user_is_active() and exists(select 1 from public.tasks t where t.id=target_task and t.deleted_at is null and (t.creator_id=auth.uid() or t.assignee_id=auth.uid() or t.delegated_by_id=auth.uid() or private.is_admin() or private.manages_user(t.assignee_id) or (t.project_id is not null and private.project_access(t.project_id))))
$$;
create or replace function private.can_modify_task(target_task uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.current_user_is_active() and exists(select 1 from public.tasks t where t.id=target_task and ((t.project_id is not null and private.project_access(t.project_id) and (t.assignee_id=auth.uid() or private.project_manage(t.project_id) or t.approval_commissioner_id=auth.uid())) or (t.project_id is null and (private.is_admin() or t.assignee_id=auth.uid() or (private.current_user_role()='manager' and (private.is_direct_manager(t.assignee_id) or t.creator_id=auth.uid()))))))
$$;
do $$ declare f record;begin for f in select p.oid::regprocedure signature,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('private','public') and (p.proname like 'project_%' or p.proname in('validate_project_task','guard_project_task_insert')) loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.proname in('project_access','project_manage','project_directory','project_people','project_command') then execute format('grant execute on function %s to authenticated',f.signature);end if;
 end loop;end $$;
