-- Creator-owned, reversible project deletion. Preserve work and audit records.
alter table public.projects add column deleted_at timestamptz, add column deleted_by uuid references public.profiles(id);
create or replace function private.project_access(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.current_user_is_active() and exists(select 1 from public.projects p where p.id=p_id and p.deleted_at is null and (private.is_admin() or p.created_by=auth.uid() or p.manager_id=auth.uid() or p.sponsor_id=auth.uid() or exists(select 1 from public.project_members m where m.project_id=p.id and m.user_id=auth.uid())))
$$;
create or replace function private.project_manage(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.current_user_is_active() and exists(select 1 from public.projects p where p.id=p_id and p.deleted_at is null and (private.is_admin() or p.manager_id=auth.uid()))
$$;
create function private.project_delete(p_id uuid,p_revision integer) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.projects%rowtype;
begin
 if auth.uid() is null or not private.current_user_is_active() then raise exception 'ATWAR_AUTH: inactive user';end if;
 select * into p from public.projects where id=p_id for update;
 if not found or p.deleted_at is not null or p.created_by<>auth.uid() then raise exception 'حذف المشروع متاح لمن أنشأه فقط';end if;
 if p.revision<>p_revision then raise exception 'ATWAR_CONFLICT: project changed';end if;
 perform private.project_event(p.id,'DELETE','حذف المشروع من العرض مع الاحتفاظ بسجله ومهامه وملفاته');
 update public.projects set deleted_at=now(),deleted_by=auth.uid() where id=p.id;
 return p.id;
end $$;
create function public.project_delete(p_id uuid,p_revision integer) returns uuid language sql security invoker set search_path='' as $$select private.project_delete(p_id,p_revision)$$;
-- Even broad task-read permissions must not surface work belonging to deleted projects.
alter policy tasks_select_policy on public.tasks using (
 (private.can_view_task(id) or private.has_permission('tasks.read_all')) and
 (project_id is null or private.project_access(project_id))
);
-- Presence records accept only the authenticated user's server timestamp.
create table private.user_presence(user_id uuid primary key references public.profiles(id) on delete cascade,last_seen timestamptz not null);
alter table private.user_presence enable row level security;
revoke all on private.user_presence from public,anon,authenticated;
create function private.presence_ping() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.current_user_is_active() then raise exception 'ATWAR_AUTH: inactive user';end if;
 insert into private.user_presence(user_id,last_seen) values(auth.uid(),now()) on conflict(user_id) do update set last_seen=excluded.last_seen;
end $$;
create function public.presence_ping() returns void language sql security invoker set search_path='' as $$select private.presence_ping()$$;
create function private.project_presence(p_id uuid) returns table(user_id uuid,online boolean) language plpgsql security definer set search_path='' as $$
begin
 if not private.project_access(p_id) then raise exception 'المشروع غير متاح';end if;
 return query select u.id,coalesce(s.last_seen>now()-interval '90 seconds',false) from public.profiles u left join private.user_presence s on s.user_id=u.id where private.user_is_active(u.id) and (exists(select 1 from public.project_members m where m.project_id=p_id and m.user_id=u.id) or exists(select 1 from public.projects p where p.id=p_id and u.id in(p.manager_id,p.sponsor_id)));
end $$;
create function public.project_presence(p_id uuid) returns table(user_id uuid,online boolean) language sql security invoker set search_path='' as $$select * from private.project_presence(p_id)$$;
revoke all on function private.project_delete(uuid,integer),public.project_delete(uuid,integer),private.presence_ping(),public.presence_ping(),private.project_presence(uuid),public.project_presence(uuid) from public,anon,authenticated;
grant execute on function private.project_delete(uuid,integer),public.project_delete(uuid,integer),private.presence_ping(),public.presence_ping(),private.project_presence(uuid),public.project_presence(uuid) to authenticated;
