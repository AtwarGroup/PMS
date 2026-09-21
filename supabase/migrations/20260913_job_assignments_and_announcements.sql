begin;

alter table public.job_descriptions
  add column if not exists aliases text[] not null default array[]::text[];

create index if not exists job_descriptions_aliases_gin_idx
  on public.job_descriptions using gin(aliases);

create table if not exists public.employee_job_assignments (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  job_description_id uuid not null references public.job_descriptions(id) on delete restrict,
  effective_from date not null default current_date,
  assignment_note text,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  updated_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now()
);

create index if not exists employee_job_assignments_job_idx
  on public.employee_job_assignments(job_description_id);
create index if not exists employee_job_assignments_assigned_by_idx
  on public.employee_job_assignments(assigned_by);
create index if not exists employee_job_assignments_updated_by_idx
  on public.employee_job_assignments(updated_by);

alter table public.employee_job_assignments enable row level security;
revoke all on table public.employee_job_assignments from public,anon;
grant select,insert,update,delete on table public.employee_job_assignments to authenticated;

drop policy if exists employee_job_assignments_select_policy on public.employee_job_assignments;
create policy employee_job_assignments_select_policy on public.employee_job_assignments
for select to authenticated using (
  profile_id=(select auth.uid())
  or private.job_library_role()='admin'
  or exists(
    select 1 from public.profiles p
    where p.id=employee_job_assignments.profile_id and p.manager_id=(select auth.uid())
  )
);

drop policy if exists employee_job_assignments_insert_policy on public.employee_job_assignments;
create policy employee_job_assignments_insert_policy on public.employee_job_assignments
for insert to authenticated with check (
  private.job_library_role()='admin'
  and assigned_by=(select auth.uid())
  and updated_by=(select auth.uid())
);

drop policy if exists employee_job_assignments_update_policy on public.employee_job_assignments;
create policy employee_job_assignments_update_policy on public.employee_job_assignments
for update to authenticated
using (private.job_library_role()='admin')
with check (private.job_library_role()='admin' and updated_by=(select auth.uid()));

drop policy if exists employee_job_assignments_delete_policy on public.employee_job_assignments;
create policy employee_job_assignments_delete_policy on public.employee_job_assignments
for delete to authenticated using (private.job_library_role()='admin');

create or replace function private.prepare_employee_job_assignment()
returns trigger language plpgsql security invoker
set search_path to 'pg_catalog','public','private'
as $$
declare v_uid uuid:=(select auth.uid());
begin
  if v_uid is null or private.job_library_role()<>'admin' then
    raise exception 'Only the system administrator can assign job descriptions';
  end if;
  if tg_op='INSERT' then
    new.assigned_by:=v_uid; new.assigned_at:=now();
  else
    new.assigned_by:=old.assigned_by; new.assigned_at:=old.assigned_at;
  end if;
  new.updated_by:=v_uid; new.updated_at:=now();
  return new;
end $$;

revoke all on function private.prepare_employee_job_assignment() from public,anon,authenticated;
drop trigger if exists employee_job_assignments_prepare on public.employee_job_assignments;
create trigger employee_job_assignments_prepare before insert or update on public.employee_job_assignments
for each row execute function private.prepare_employee_job_assignment();

create or replace function private.can_view_published_job(p_job_id uuid)
returns boolean language sql stable security definer
set search_path to 'pg_catalog','public','private'
as $$
  select coalesce(
    exists(
      select 1 from public.employee_job_assignments a
      join public.job_descriptions j on j.id=a.job_description_id
      where a.profile_id=(select auth.uid()) and j.id=p_job_id and j.published_at is not null
    )
    or exists(
      select 1 from public.profiles p join public.job_descriptions j on j.id=p.job_description_id
      where p.id=(select auth.uid()) and j.id=p_job_id and j.published_at is not null
    )
    or exists(
      select 1 from public.profiles p join public.job_descriptions j on j.title=p.job_title
      where p.id=(select auth.uid()) and p.job_description_id is null
        and not exists(select 1 from public.employee_job_assignments a where a.profile_id=p.id)
        and j.id=p_job_id and j.published_at is not null
    ),false
  )
$$;

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null default 'ALL',
  importance text not null default 'NORMAL',
  status text not null default 'DRAFT',
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint announcements_title_check check (char_length(btrim(title)) between 2 and 160),
  constraint announcements_body_check check (char_length(btrim(body)) between 2 and 3000),
  constraint announcements_audience_check check (audience in ('EMPLOYEES','MANAGERS','ALL')),
  constraint announcements_importance_check check (importance in ('NORMAL','IMPORTANT')),
  constraint announcements_status_check check (status in ('DRAFT','PUBLISHED','ARCHIVED')),
  constraint announcements_dates_check check (ends_at is null or ends_at>starts_at)
);

create index if not exists announcements_feed_idx
  on public.announcements(status,starts_at desc,ends_at);
create index if not exists announcements_created_by_idx on public.announcements(created_by);
create index if not exists announcements_updated_by_idx on public.announcements(updated_by);

alter table public.announcements enable row level security;
revoke all on table public.announcements from public,anon;
grant select,insert,update,delete on table public.announcements to authenticated;

drop policy if exists announcements_select_policy on public.announcements;
create policy announcements_select_policy on public.announcements
for select to authenticated using (
  private.job_library_role()='admin'
  or (
    status='PUBLISHED' and starts_at<=now() and (ends_at is null or ends_at>now())
    and (
      audience='ALL'
      or (audience='EMPLOYEES' and private.job_library_role()='employee')
      or (audience='MANAGERS' and private.job_library_role()='manager')
    )
  )
);

drop policy if exists announcements_insert_policy on public.announcements;
create policy announcements_insert_policy on public.announcements
for insert to authenticated with check (
  private.job_library_role()='admin'
  and created_by=(select auth.uid()) and updated_by=(select auth.uid())
);

drop policy if exists announcements_update_policy on public.announcements;
create policy announcements_update_policy on public.announcements
for update to authenticated
using (private.job_library_role()='admin')
with check (private.job_library_role()='admin' and updated_by=(select auth.uid()));

drop policy if exists announcements_delete_policy on public.announcements;
create policy announcements_delete_policy on public.announcements
for delete to authenticated using (private.job_library_role()='admin');

create or replace function private.prepare_announcement()
returns trigger language plpgsql security invoker
set search_path to 'pg_catalog','public','private'
as $$
declare v_uid uuid:=(select auth.uid());
begin
  if v_uid is null or private.job_library_role()<>'admin' then
    raise exception 'Only the system administrator can manage announcements';
  end if;
  new.title:=btrim(new.title); new.body:=btrim(new.body);
  if tg_op='INSERT' then
    new.created_by:=v_uid; new.created_at:=now();
  else
    new.created_by:=old.created_by; new.created_at:=old.created_at;
  end if;
  new.updated_by:=v_uid; new.updated_at:=now();
  return new;
end $$;

revoke all on function private.prepare_announcement() from public,anon,authenticated;
drop trigger if exists announcements_prepare on public.announcements;
create trigger announcements_prepare before insert or update on public.announcements
for each row execute function private.prepare_announcement();

comment on table public.employee_job_assignments is 'Authoritative employee-to-job-description links; manager remains sourced from profiles.manager_id.';
comment on table public.announcements is 'Role-targeted homepage announcements managed by the system administrator.';

commit;
