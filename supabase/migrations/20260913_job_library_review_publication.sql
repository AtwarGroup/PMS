begin;

create table if not exists public.job_descriptions (
  id uuid primary key default gen_random_uuid(),
  job_code text not null unique,
  title text not null,
  family text,
  job_level text,
  reports_to_title text,
  purpose text not null default '',
  content jsonb not null default '{}'::jsonb,
  published_snapshot jsonb,
  status text not null default 'DRAFT',
  reviewer_id uuid references public.profiles(id) on delete set null,
  review_note text,
  revision integer not null default 1,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  manager_approved_by uuid references public.profiles(id) on delete set null,
  manager_approved_at timestamptz,
  published_by uuid references public.profiles(id) on delete set null,
  published_at timestamptz,
  constraint job_descriptions_code_check check (job_code ~ '^JOB-[0-9]{3,}$'),
  constraint job_descriptions_status_check check (status in ('DRAFT','IN_REVIEW','CHANGES_REQUESTED','MANAGER_APPROVED','PUBLISHED','ARCHIVED')),
  constraint job_descriptions_revision_check check (revision > 0),
  constraint job_descriptions_content_object_check check (jsonb_typeof(content)='object')
);

create index if not exists job_descriptions_status_idx on public.job_descriptions(status);
create index if not exists job_descriptions_reviewer_idx on public.job_descriptions(reviewer_id,status);
create index if not exists job_descriptions_title_idx on public.job_descriptions(title);

create table if not exists public.job_description_versions (
  id bigint generated always as identity primary key,
  job_description_id uuid not null,
  job_code text not null,
  revision integer not null,
  action text not null,
  snapshot jsonb not null,
  actor_id uuid references public.profiles(id) on delete set null,
  change_note text,
  created_at timestamptz not null default now(),
  constraint job_description_versions_action_check check (action in ('CREATED','UPDATED','SUBMITTED','CHANGES_REQUESTED','MANAGER_APPROVED','PUBLISHED','ARCHIVED')),
  constraint job_description_versions_unique unique(job_description_id,revision)
);

create index if not exists job_description_versions_job_idx on public.job_description_versions(job_description_id,revision desc);
create index if not exists job_description_versions_actor_idx on public.job_description_versions(actor_id);

create table if not exists public.job_description_comments (
  id uuid primary key default gen_random_uuid(),
  job_description_id uuid not null references public.job_descriptions(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  body text not null,
  created_at timestamptz not null default now(),
  constraint job_description_comments_body_check check (char_length(btrim(body)) between 2 and 2000)
);

create index if not exists job_description_comments_job_idx on public.job_description_comments(job_description_id,created_at);
create index if not exists job_description_comments_author_idx on public.job_description_comments(author_id);

alter table public.profiles add column if not exists job_description_id uuid references public.job_descriptions(id) on delete set null;
create index if not exists profiles_job_description_id_idx on public.profiles(job_description_id);

alter table public.job_descriptions enable row level security;
alter table public.job_description_versions enable row level security;
alter table public.job_description_comments enable row level security;

revoke all on table public.job_descriptions from public,anon;
revoke all on table public.job_description_versions from public,anon,authenticated;
revoke all on table public.job_description_comments from public,anon;
grant select,insert,update on table public.job_descriptions to authenticated;
grant select on table public.job_description_versions to authenticated;
grant select,insert on table public.job_description_comments to authenticated;

create or replace function private.job_library_role()
returns text language sql stable security definer
set search_path to 'pg_catalog','public','private'
as $$ select role from public.profiles where id=(select auth.uid()) and active=true and status='active' limit 1 $$;

create or replace function private.can_review_job(p_job_id uuid)
returns boolean language sql stable security definer
set search_path to 'pg_catalog','public','private'
as $$
  select coalesce(
    private.job_library_role()='admin'
    or exists(select 1 from public.job_descriptions j where j.id=p_job_id and j.reviewer_id=(select auth.uid())),
    false
  )
$$;

create or replace function private.can_view_published_job(p_job_id uuid)
returns boolean language sql stable security definer
set search_path to 'pg_catalog','public','private'
as $$
  select coalesce(exists(
    select 1 from public.profiles p join public.job_descriptions j on j.id=p.job_description_id
    where p.id=(select auth.uid()) and p.active=true and p.status='active'
      and j.id=p_job_id and j.published_at is not null
  ) or exists(
    select 1 from public.profiles p join public.job_descriptions j on j.title=p.job_title
    where p.id=(select auth.uid()) and p.active=true and p.status='active'
      and p.job_description_id is null and j.id=p_job_id and j.published_at is not null
  ),false)
$$;

revoke all on function private.job_library_role() from public,anon;
revoke all on function private.can_review_job(uuid) from public,anon;
revoke all on function private.can_view_published_job(uuid) from public,anon;
grant execute on function private.job_library_role() to authenticated;
grant execute on function private.can_review_job(uuid) to authenticated;
grant execute on function private.can_view_published_job(uuid) to authenticated;

drop policy if exists job_descriptions_select_policy on public.job_descriptions;
create policy job_descriptions_select_policy on public.job_descriptions
for select to authenticated using (
  private.can_view_published_job(id)
  or private.job_library_role()='admin'
  or reviewer_id=(select auth.uid())
);

drop policy if exists job_descriptions_insert_policy on public.job_descriptions;
create policy job_descriptions_insert_policy on public.job_descriptions
for insert to authenticated with check (
  private.job_library_role()='admin'
  and created_by=(select auth.uid())
  and updated_by=(select auth.uid())
);

drop policy if exists job_descriptions_update_policy on public.job_descriptions;
create policy job_descriptions_update_policy on public.job_descriptions
for update to authenticated
using (private.job_library_role()='admin' or reviewer_id=(select auth.uid()))
with check (private.job_library_role()='admin' or reviewer_id=(select auth.uid()));

drop policy if exists job_description_versions_select_policy on public.job_description_versions;
create policy job_description_versions_select_policy on public.job_description_versions
for select to authenticated using (
  exists(select 1 from public.job_descriptions j where j.id=job_description_id)
);

drop policy if exists job_description_comments_select_policy on public.job_description_comments;
create policy job_description_comments_select_policy on public.job_description_comments
for select to authenticated using (private.can_review_job(job_description_id));

drop policy if exists job_description_comments_insert_policy on public.job_description_comments;
create policy job_description_comments_insert_policy on public.job_description_comments
for insert to authenticated with check (
  author_id=(select auth.uid()) and private.can_review_job(job_description_id)
);

create or replace function private.prepare_job_description()
returns trigger language plpgsql security invoker
set search_path to 'pg_catalog','public','private'
as $$
declare v_uid uuid:=(select auth.uid()); v_role text:=private.job_library_role();
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  new.job_code:=upper(btrim(new.job_code)); new.title:=btrim(new.title); new.purpose:=btrim(new.purpose);
  if tg_op='INSERT' then
    if v_role<>'admin' then raise exception 'Only administrators can import job descriptions'; end if;
    new.created_by:=v_uid; new.updated_by:=v_uid; new.created_at:=now(); new.updated_at:=now(); new.revision:=1;
    if new.status not in ('DRAFT','IN_REVIEW') then new.status:='DRAFT'; end if;
  else
    new.created_by:=old.created_by; new.created_at:=old.created_at; new.updated_by:=v_uid; new.updated_at:=now(); new.revision:=old.revision+1;
    if v_role<>'admin' then
      new.job_code:=old.job_code; new.reviewer_id:=old.reviewer_id; new.created_by:=old.created_by;
      if new.status not in ('IN_REVIEW','CHANGES_REQUESTED','MANAGER_APPROVED') then raise exception 'Reviewer cannot publish or archive'; end if;
      if old.status not in ('IN_REVIEW','CHANGES_REQUESTED') then raise exception 'This version is not open for manager review'; end if;
      if new.status='CHANGES_REQUESTED' and char_length(btrim(coalesce(new.review_note,'')))<2 then raise exception 'A review note is required'; end if;
      if new.status='MANAGER_APPROVED' then new.manager_approved_by:=v_uid; new.manager_approved_at:=now(); end if;
    end if;
    if v_role='admin' and new.status='PUBLISHED' and old.status<>'PUBLISHED' then
      if old.status<>'MANAGER_APPROVED' then raise exception 'Manager approval is required before publication'; end if;
      new.published_by:=v_uid; new.published_at:=now();
      new.published_snapshot:=jsonb_build_object(
        'job_code',new.job_code,'title',new.title,'family',new.family,'job_level',new.job_level,
        'reports_to_title',new.reports_to_title,'purpose',new.purpose,'content',new.content,
        'revision',new.revision,'published_at',now()
      );
    end if;
  end if;
  return new;
end $$;

create or replace function private.audit_job_description()
returns trigger language plpgsql security definer
set search_path to 'pg_catalog','public','private'
as $$
declare v_action text;
begin
  v_action:=case when tg_op='INSERT' then 'CREATED'
    when new.status<>old.status and new.status='IN_REVIEW' then 'SUBMITTED'
    when new.status<>old.status and new.status in ('CHANGES_REQUESTED','MANAGER_APPROVED','PUBLISHED','ARCHIVED') then new.status
    else 'UPDATED' end;
  insert into public.job_description_versions(job_description_id,job_code,revision,action,snapshot,actor_id,change_note)
  values(new.id,new.job_code,new.revision,v_action,to_jsonb(new),(select auth.uid()),new.review_note);
  return new;
end $$;

revoke all on function private.prepare_job_description() from public,anon,authenticated;
revoke all on function private.audit_job_description() from public,anon,authenticated;

drop trigger if exists job_descriptions_prepare on public.job_descriptions;
create trigger job_descriptions_prepare before insert or update on public.job_descriptions
for each row execute function private.prepare_job_description();
drop trigger if exists job_descriptions_audit on public.job_descriptions;
create trigger job_descriptions_audit after insert or update on public.job_descriptions
for each row execute function private.audit_job_description();

comment on table public.job_descriptions is 'Governed job library drafts, manager review and published descriptions.';
comment on table public.job_description_versions is 'Immutable snapshot history for every job-description revision and workflow decision.';
comment on table public.job_description_comments is 'Review discussion attached to a job description.';

commit;
