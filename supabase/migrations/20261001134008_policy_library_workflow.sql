begin;
create table public.policies(
 id uuid primary key default gen_random_uuid(),code text not null unique check(length(code) between 2 and 40),title text not null check(length(title) between 2 and 200),
 preparer_id uuid references public.profiles(id),reviewer_id uuid references public.profiles(id),approver_id uuid references public.profiles(id),ratifier_id uuid references public.profiles(id),
 audience_groups text[] not null default '{}',management_viewer_ids uuid[] not null default '{}',revision integer not null default 1,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(audience_groups <@ array['MANAGEMENT','MANAGERS','EMPLOYEES']::text[])
);
create table public.policy_versions(
 id uuid primary key default gen_random_uuid(),policy_id uuid not null references public.policies(id),version_number integer not null,version_label text not null default '',
 status text not null default 'PREPARATION' check(status in('PREPARATION','REVIEW','APPROVAL','RATIFICATION','APPROVED')),
 content jsonb not null default '[]' check(jsonb_typeof(content)='array'),revision integer not null default 1,cycle integer not null default 1,
 effective_date date,approved_by uuid references public.profiles(id),approved_at timestamptz,
 audience_groups text[] not null default '{}',management_viewer_ids uuid[] not null default '{}',current_task_id uuid references public.tasks(id),
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(policy_id,version_number),
 check(status<>'APPROVED' or (effective_date is not null and approved_by is not null and approved_at is not null))
);
create unique index policy_one_draft_idx on public.policy_versions(policy_id) where status<>'APPROVED';
create index policy_effective_idx on public.policy_versions(policy_id,effective_date,version_number) where status='APPROVED';
create index policy_tasks_idx on public.policy_versions(current_task_id);
create table public.policy_events(id uuid primary key default gen_random_uuid(),policy_id uuid not null references public.policies(id),version_id uuid references public.policy_versions(id),actor_id uuid not null references public.profiles(id),actor_name text not null,action text not null,from_stage text,to_stage text,note text not null default '',created_at timestamptz not null default now());
create index policy_events_policy_idx on public.policy_events(policy_id,created_at);
create table public.policy_comments(id uuid primary key default gen_random_uuid(),version_id uuid not null references public.policy_versions(id),section_id text not null,actor_id uuid not null references public.profiles(id),actor_name text not null,body text not null check(length(body) between 2 and 2000),created_at timestamptz not null default now());
create index policy_comments_version_idx on public.policy_comments(version_id,created_at);
create function private.policy_worker(p uuid) returns boolean language sql stable security definer set search_path='pg_catalog','public','private' as $$
 select private.current_user_is_active() and (private.is_admin() or exists(select 1 from public.policies where id=p and auth.uid() in(preparer_id,reviewer_id,approver_id,ratifier_id)))
$$;
create function private.policy_visible_version(v uuid) returns boolean language sql stable security definer set search_path='pg_catalog','public','private' as $$
 select private.current_user_is_active() and exists(select 1 from public.policy_versions x where x.id=v and (private.policy_worker(x.policy_id) or (
 x.id=(select y.id from public.policy_versions y where y.policy_id=x.policy_id and y.status='APPROVED' and y.effective_date<=current_date order by y.version_number desc limit 1)
 and (( 'MANAGEMENT'=any(x.audience_groups) and auth.uid()=any(x.management_viewer_ids)) or ('MANAGERS'=any(x.audience_groups) and private.current_user_role()='manager') or ('EMPLOYEES'=any(x.audience_groups) and private.current_user_role()='employee')))))
$$;
alter table public.policies enable row level security;alter table public.policy_versions enable row level security;alter table public.policy_events enable row level security;alter table public.policy_comments enable row level security;
revoke all on public.policies,public.policy_versions,public.policy_events,public.policy_comments from public,anon,authenticated;
grant select on public.policies,public.policy_versions,public.policy_events,public.policy_comments to authenticated;
create policy policy_read on public.policies for select to authenticated using(private.policy_worker(id) or exists(select 1 from public.policy_versions where policy_id=policies.id));
create policy policy_version_read on public.policy_versions for select to authenticated using(private.policy_visible_version(id));
create policy policy_event_read on public.policy_events for select to authenticated using(private.policy_worker(policy_id));
create policy policy_comment_read on public.policy_comments for select to authenticated using(exists(select 1 from public.policy_versions v where v.id=version_id and private.policy_worker(v.policy_id)));
create function private.policy_log(p uuid,v uuid,a text,f text,t text,n text) returns void language sql security definer set search_path='pg_catalog','public' as $$
 insert into public.policy_events(policy_id,version_id,actor_id,actor_name,action,from_stage,to_stage,note) select p,v,auth.uid(),full_name,a,f,t,coalesce(n,'') from public.profiles where id=auth.uid()
$$;
create function private.policy_validate_content(c jsonb) returns void language plpgsql set search_path='pg_catalog' as $$
begin
 if c is null or jsonb_typeof(c)<>'array' or jsonb_array_length(c) not between 1 and 150 or octet_length(c::text)>1000000 then raise exception 'Policy requires 1–150 sections';end if;
 if exists(select 1 from jsonb_array_elements(c) s where jsonb_typeof(s)<>'object' or length(coalesce(s->>'id','')) not between 1 and 100 or length(btrim(coalesce(s->>'title',''))) not between 2 and 200 or length(btrim(coalesce(s->>'body',''))) not between 2 and 60000) or (select count(distinct s->>'id') from jsonb_array_elements(c) s)<>jsonb_array_length(c) then raise exception 'Each section requires a unique ID, title and text';end if;
end $$;
-- Nested triggers own workflow tasks. Existing job_workflow guard forbids manual completion.
create function private.sync_policy_tasks() returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare p public.policies%rowtype;owner uuid;t uuid;ownername text;creatorname text;stage text;
begin
 select * into p from public.policies where id=new.policy_id;
 owner:=case new.status when 'PREPARATION' then p.preparer_id when 'REVIEW' then p.reviewer_id when 'APPROVAL' then p.approver_id when 'RATIFICATION' then p.ratifier_id else null end;
 if tg_op='UPDATE' and new.status=old.status and new.cycle=old.cycle then return new;end if;
 if new.current_task_id is not null then update public.tasks set status='مكتملة',progress=100,completed_at=now(),actual_end_date=current_date,revision=revision+1,updated_at=now() where id=new.current_task_id and deleted_at is null and status<>'مكتملة';end if;
 t:=null;
 if owner is not null then
  select full_name into ownername from public.profiles where id=owner;select full_name into creatorname from public.profiles where id=new.created_by;
  stage:=case new.status when 'PREPARATION' then 'إعداد' when 'REVIEW' then 'مراجعة' when 'APPROVAL' then 'موافقة' else 'اعتماد' end;
  insert into public.tasks(title,description,task_type,creator_id,assignee_id,creator_name_snapshot,assignee_name_snapshot,status,priority,progress,start_date,legacy_metadata)
  values(left(stage||' السياسة: '||p.title,200),'افتح السياسة لمراجعة محتواها واتخاذ إجراء المرحلة. تُغلق هذه المهمة تلقائيًا عند انتقال السياسة أو إعادتها للإعداد.','job_workflow',new.created_by,owner,creatorname,ownername,'قيد الانتظار','normal',0,current_date,jsonb_build_object('job_workflow',jsonb_build_object('policy_id',p.id,'policy_version_id',new.id,'phase','POLICY_'||new.status,'cycle',new.cycle))) returning id into t;
 end if;
 update public.policy_versions set current_task_id=t where id=new.id;return new;
end $$;
create trigger policy_stage_tasks after insert or update of status,cycle on public.policy_versions for each row execute function private.sync_policy_tasks();
create function private.policy_create(p_code text,p_title text,p_content jsonb,p_label text) returns uuid language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare p uuid;v uuid;
begin
 if not private.current_user_is_active() or not private.is_admin() then raise exception 'System administrator required' using errcode='42501';end if;
 perform private.policy_validate_content(p_content);
 insert into public.policies(code,title,created_by) values(btrim(p_code),btrim(p_title),auth.uid()) returning id into p;
 insert into public.policy_versions(policy_id,version_number,version_label,content,created_by) values(p,1,left(coalesce(p_label,''),100),p_content,auth.uid()) returning id into v;
 perform private.policy_log(p,v,'CREATE',null,'PREPARATION','إنشاء مسودة');return p;
end $$;
create function private.policy_configure(p_id uuid,p_revision integer,p_title text,p_preparer uuid,p_reviewer uuid,p_approver uuid,p_ratifier uuid,p_audience text[],p_management uuid[]) returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare p public.policies%rowtype;
begin
 if not private.current_user_is_active() or not private.is_admin() then raise exception 'System administrator required' using errcode='42501';end if;
 select * into p from public.policies where id=p_id for update;if not found then raise exception 'Policy not found';end if;
 if p_revision is null or p.revision<>p_revision then raise exception 'ATWAR_CONFLICT: policy configuration changed';end if;
 if p_audience is null or p_management is null then raise exception 'Audience required';end if;
 if exists(select 1 from unnest(array[p_preparer,p_reviewer,p_approver,p_ratifier]||p_management) u where u is not null and not exists(select 1 from public.profiles where id=u and active=true and status='active')) then raise exception 'Select active users';end if;
 update public.policies set title=btrim(p_title),preparer_id=p_preparer,reviewer_id=p_reviewer,approver_id=p_approver,ratifier_id=p_ratifier,audience_groups=p_audience,management_viewer_ids=p_management,revision=revision+1,updated_at=now() where id=p_id;
 -- Invalidates stale open screens and reassigns the active stage task atomically.
 update public.policy_versions set cycle=cycle+1,revision=revision+1,updated_at=now() where policy_id=p_id and status<>'APPROVED';
 perform private.policy_log(p_id,null,'CONFIGURE',null,null,'تحديث أصحاب المراحل وفئات العرض؛ يسري على الإصدار القادم عند اعتماده');
end $$;
create function private.policy_save(p_id uuid,p_revision integer,p_content jsonb,p_label text) returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v public.policy_versions%rowtype;p public.policies%rowtype;
begin
 select policy_id into p.id from public.policy_versions where id=p_id;
 select * into p from public.policies where id=p.id for update;select * into v from public.policy_versions where id=p_id for update;
 if not private.current_user_is_active() or not (private.is_admin() or auth.uid()=p.preparer_id) then raise exception 'Assigned preparer required' using errcode='42501';end if;
 if v.status<>'PREPARATION' then raise exception 'Editing is allowed only during preparation';end if;
 if p_revision is null or v.revision<>p_revision then raise exception 'ATWAR_CONFLICT: version changed';end if;
 perform private.policy_validate_content(p_content);
 update public.policy_versions set content=p_content,version_label=left(coalesce(p_label,''),100),revision=revision+1,updated_at=now() where id=p_id;
 perform private.policy_log(p.id,v.id,'EDIT',v.status,v.status,'حفظ محتوى المسودة');
end $$;
create function private.policy_decide(p_id uuid,p_revision integer,p_return boolean,p_note text,p_effective date) returns text language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v public.policy_versions%rowtype;p public.policies%rowtype;owner uuid;nextstage text;
begin
 select policy_id into p.id from public.policy_versions where id=p_id;select * into p from public.policies where id=p.id for update;select * into v from public.policy_versions where id=p_id for update;
 owner:=case v.status when 'PREPARATION' then p.preparer_id when 'REVIEW' then p.reviewer_id when 'APPROVAL' then p.approver_id when 'RATIFICATION' then p.ratifier_id end;
 if not private.current_user_is_active() or owner is null or auth.uid()<>owner then raise exception 'Assigned stage owner required' using errcode='42501';end if;
 if p_revision is null or v.revision<>p_revision then raise exception 'ATWAR_CONFLICT: version changed';end if;
 if p_return is null or length(btrim(coalesce(p_note,''))) not between 2 and 2000 then raise exception 'Decision note required';end if;
 if p_return and v.status='PREPARATION' then raise exception 'Already in preparation';end if;
 if exists(select 1 from unnest(array[p.preparer_id,p.reviewer_id,p.approver_id,p.ratifier_id]) u where u is null or not exists(select 1 from public.profiles where id=u and active=true and status='active')) then raise exception 'Configure all four active stage owners';end if;
 perform private.policy_validate_content(v.content);
 nextstage:=case when p_return then 'PREPARATION' when v.status='PREPARATION' then 'REVIEW' when v.status='REVIEW' then 'APPROVAL' when v.status='APPROVAL' then 'RATIFICATION' else 'APPROVED' end;
 if nextstage='APPROVED' then
  if p_effective is null or p_effective<current_date or p_effective<coalesce((select max(effective_date) from public.policy_versions where policy_id=p.id and status='APPROVED'),current_date) then raise exception 'Effective date must be today or later and follow the preceding version';end if;
  if cardinality(p.audience_groups)=0 or ('MANAGEMENT'=any(p.audience_groups) and cardinality(p.management_viewer_ids)=0) then raise exception 'Select publication audience';end if;
 end if;
 update public.policy_versions set status=nextstage,revision=revision+1,cycle=cycle+1,updated_at=now(),
 effective_date=case when nextstage='APPROVED' then p_effective else null end,approved_by=case when nextstage='APPROVED' then auth.uid() else null end,approved_at=case when nextstage='APPROVED' then now() else null end,
 audience_groups=case when nextstage='APPROVED' then p.audience_groups else '{}'::text[] end,management_viewer_ids=case when nextstage='APPROVED' then p.management_viewer_ids else '{}'::uuid[] end where id=v.id;
 perform private.policy_log(p.id,v.id,case when p_return then 'RETURN' else 'ADVANCE' end,v.status,nextstage,btrim(p_note));return nextstage;
end $$;
create function private.policy_new_version(p_id uuid,p_revision integer) returns uuid language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare p public.policies%rowtype;v public.policy_versions%rowtype;n uuid;
begin
 if not private.current_user_is_active() or not private.is_admin() then raise exception 'System administrator required' using errcode='42501';end if;
 select * into p from public.policies where id=p_id for update;
 if not found or p_revision is null or p.revision<>p_revision then raise exception 'ATWAR_CONFLICT: policy configuration changed';end if;
 if exists(select 1 from public.policy_versions where policy_id=p_id and status<>'APPROVED') then raise exception 'Finish the current draft first';end if;
 select * into v from public.policy_versions where policy_id=p_id order by version_number desc limit 1;
 if not found then raise exception 'Approved version required';end if;
 insert into public.policy_versions(policy_id,version_number,version_label,content,created_by) values(p_id,v.version_number+1,'إصدار جديد',v.content,auth.uid()) returning id into n;
 update public.policies set revision=revision+1,updated_at=now() where id=p_id;
 perform private.policy_log(p_id,n,'NEW_VERSION',null,'PREPARATION','إنشاء إصدار من النسخة السابقة');return n;
end $$;
create function private.policy_comment(p_id uuid,p_section text,p_body text) returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v public.policy_versions%rowtype;
begin
 select * into v from public.policy_versions where id=p_id for share;
 if not found or not private.policy_worker(v.policy_id) then raise exception 'Policy participant required' using errcode='42501';end if;
 if v.status='APPROVED' then raise exception 'Open a new version to review approved content';end if;
 if not exists(select 1 from jsonb_array_elements(v.content) s where s->>'id'=p_section) then raise exception 'Section not found';end if;
 insert into public.policy_comments(version_id,section_id,actor_id,actor_name,body) select v.id,p_section,auth.uid(),full_name,btrim(p_body) from public.profiles where id=auth.uid();
end $$;
create function private.policy_directory() returns table(id uuid,full_name text,role text) language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
 if not private.current_user_is_active() or not private.is_admin() then raise exception 'System administrator required' using errcode='42501';end if;
 return query select p.id,p.full_name,p.role::text from public.profiles p where p.active=true and p.status='active' order by p.full_name;
end $$;
-- Only invoker wrappers are exposed through the API.
create function public.policy_create(p_code text,p_title text,p_content jsonb,p_label text) returns uuid language sql security invoker set search_path='pg_catalog','private' as $$ select private.policy_create(p_code,p_title,p_content,p_label) $$;
revoke all on function private.policy_create(text,text,jsonb,text),public.policy_create(text,text,jsonb,text) from public,anon;
grant execute on function private.policy_create(text,text,jsonb,text),public.policy_create(text,text,jsonb,text) to authenticated;
create function public.policy_configure(p_id uuid,p_revision integer,p_title text,p_preparer uuid,p_reviewer uuid,p_approver uuid,p_ratifier uuid,p_audience text[],p_management uuid[]) returns void language sql security invoker set search_path='pg_catalog','private' as $$ select private.policy_configure(p_id,p_revision,p_title,p_preparer,p_reviewer,p_approver,p_ratifier,p_audience,p_management) $$;
revoke all on function private.policy_configure(uuid,integer,text,uuid,uuid,uuid,uuid,text[],uuid[]),public.policy_configure(uuid,integer,text,uuid,uuid,uuid,uuid,text[],uuid[]) from public,anon;
grant execute on function private.policy_configure(uuid,integer,text,uuid,uuid,uuid,uuid,text[],uuid[]),public.policy_configure(uuid,integer,text,uuid,uuid,uuid,uuid,text[],uuid[]) to authenticated;
create function public.policy_save(p_id uuid,p_revision integer,p_content jsonb,p_label text) returns void language sql security invoker set search_path='pg_catalog','private' as $$ select private.policy_save(p_id,p_revision,p_content,p_label) $$;
revoke all on function private.policy_save(uuid,integer,jsonb,text),public.policy_save(uuid,integer,jsonb,text) from public,anon;
grant execute on function private.policy_save(uuid,integer,jsonb,text),public.policy_save(uuid,integer,jsonb,text) to authenticated;
create function public.policy_decide(p_id uuid,p_revision integer,p_return boolean,p_note text,p_effective date) returns text language sql security invoker set search_path='pg_catalog','private' as $$ select private.policy_decide(p_id,p_revision,p_return,p_note,p_effective) $$;
revoke all on function private.policy_decide(uuid,integer,boolean,text,date),public.policy_decide(uuid,integer,boolean,text,date) from public,anon;
grant execute on function private.policy_decide(uuid,integer,boolean,text,date),public.policy_decide(uuid,integer,boolean,text,date) to authenticated;
create function public.policy_new_version(p_id uuid,p_revision integer) returns uuid language sql security invoker set search_path='pg_catalog','private' as $$ select private.policy_new_version(p_id,p_revision) $$;
revoke all on function private.policy_new_version(uuid,integer),public.policy_new_version(uuid,integer) from public,anon;
grant execute on function private.policy_new_version(uuid,integer),public.policy_new_version(uuid,integer) to authenticated;
create function public.policy_comment(p_id uuid,p_section text,p_body text) returns void language sql security invoker set search_path='pg_catalog','private' as $$ select private.policy_comment(p_id,p_section,p_body) $$;
revoke all on function private.policy_comment(uuid,text,text),public.policy_comment(uuid,text,text) from public,anon;
grant execute on function private.policy_comment(uuid,text,text),public.policy_comment(uuid,text,text) to authenticated;
create function public.policy_directory() returns table(id uuid,full_name text,role text) language sql security invoker set search_path='pg_catalog','private' as $$ select * from private.policy_directory() $$;
revoke all on function private.policy_directory(),public.policy_directory() from public,anon;
grant execute on function private.policy_directory(),public.policy_directory() to authenticated;
revoke all on function private.policy_worker(uuid) from public,anon;
grant execute on function private.policy_worker(uuid) to authenticated;
revoke all on function private.policy_visible_version(uuid) from public,anon;
grant execute on function private.policy_visible_version(uuid) to authenticated;
revoke all on function private.policy_log(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function private.policy_validate_content(jsonb) from public,anon,authenticated;
revoke all on function private.sync_policy_tasks() from public,anon,authenticated;
create function private.policy_people(p_id uuid) returns table(id uuid,full_name text,role text) language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
 if not private.policy_worker(p_id) then raise exception 'Policy participant required' using errcode='42501';end if;
 return query select x.id,x.full_name,x.role::text from public.profiles x join public.policies p on p.id=p_id where x.id in(p.preparer_id,p.reviewer_id,p.approver_id,p.ratifier_id);
end $$;
create function public.policy_people(p_id uuid) returns table(id uuid,full_name text,role text) language sql security invoker set search_path='pg_catalog','private' as $$ select * from private.policy_people(p_id) $$;
revoke all on function private.policy_people(uuid),public.policy_people(uuid) from public,anon;
grant execute on function private.policy_people(uuid),public.policy_people(uuid) to authenticated;
commit;
