begin;

-- The master description is changed only by the system administrator.
drop policy if exists job_descriptions_update_policy on public.job_descriptions;
create policy job_descriptions_update_policy on public.job_descriptions
for update to authenticated
using (private.job_library_role()='admin')
with check (private.job_library_role()='admin');

create table if not exists public.job_description_change_requests (
  id uuid primary key default gen_random_uuid(),
  job_description_id uuid not null references public.job_descriptions(id) on delete cascade,
  section text not null,
  item_index integer,
  action text not null,
  original_value jsonb,
  proposed_value jsonb,
  reason text not null,
  status text not null default 'PENDING',
  manager_id uuid not null references public.profiles(id) on delete restrict,
  admin_decision_by uuid references public.profiles(id) on delete set null,
  admin_decision_at timestamptz,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_change_section_check check (section in ('PURPOSE','RESPONSIBILITIES','AUTHORITIES','KPIS','REPORTS','QUALIFICATIONS')),
  constraint job_change_action_check check (action in ('ADD','MODIFY','DELETE','COMMENT')),
  constraint job_change_status_check check (status in ('PENDING','ACCEPTED','REJECTED','REVISED')),
  constraint job_change_reason_check check (char_length(btrim(reason)) between 2 and 2000)
);
create index if not exists job_change_requests_job_idx on public.job_description_change_requests(job_description_id,status,created_at);
create index if not exists job_change_requests_manager_idx on public.job_description_change_requests(manager_id,status);
alter table public.job_description_change_requests enable row level security;
revoke all on table public.job_description_change_requests from public,anon;
grant select,insert,update on table public.job_description_change_requests to authenticated;

drop policy if exists job_change_requests_select_policy on public.job_description_change_requests;
create policy job_change_requests_select_policy on public.job_description_change_requests
for select to authenticated using (private.job_library_role()='admin' or manager_id=(select auth.uid()));
drop policy if exists job_change_requests_insert_policy on public.job_description_change_requests;
create policy job_change_requests_insert_policy on public.job_description_change_requests
for insert to authenticated with check (
  manager_id=(select auth.uid()) and private.job_library_role()='manager'
  and exists(select 1 from public.job_descriptions j where j.id=job_description_id and j.reviewer_id=(select auth.uid()) and j.status in ('IN_REVIEW','CHANGES_REQUESTED'))
);
drop policy if exists job_change_requests_update_policy on public.job_description_change_requests;
create policy job_change_requests_update_policy on public.job_description_change_requests
for update to authenticated
using (private.job_library_role()='admin' or (manager_id=(select auth.uid()) and status='PENDING'))
with check (
  private.job_library_role()='admin'
  or (manager_id=(select auth.uid()) and status='PENDING' and admin_decision_by is null and admin_decision_at is null)
);

create or replace function private.prepare_job_change_request()
returns trigger language plpgsql security invoker
set search_path to 'pg_catalog','public','private'
as $$
declare v_uid uuid:=(select auth.uid()); v_role text:=private.job_library_role();
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  new.reason:=btrim(new.reason);
  if tg_op='INSERT' then
    if v_role<>'manager' then raise exception 'Only assigned managers can create proposals'; end if;
    new.manager_id:=v_uid; new.status:='PENDING'; new.created_at:=now();
    new.admin_decision_by:=null; new.admin_decision_at:=null; new.admin_note:=null;
  elsif v_role='manager' then
    new.job_description_id:=old.job_description_id; new.section:=old.section; new.item_index:=old.item_index;
    new.action:=old.action; new.original_value:=old.original_value; new.manager_id:=old.manager_id; new.status:='PENDING';
    new.admin_decision_by:=null; new.admin_decision_at:=null; new.admin_note:=null;
  elsif new.status<>old.status and new.status<>'PENDING' then
    new.admin_decision_by:=v_uid; new.admin_decision_at:=now();
  end if;
  new.updated_at:=now();
  return new;
end $$;
revoke all on function private.prepare_job_change_request() from public,anon,authenticated;
drop trigger if exists job_change_requests_prepare on public.job_description_change_requests;
create trigger job_change_requests_prepare before insert or update on public.job_description_change_requests
for each row execute function private.prepare_job_change_request();

create table if not exists public.form_library (
  id uuid primary key default gen_random_uuid(),
  form_code text not null unique,
  title text not null,
  description text,
  form_type text not null default 'FORM',
  file_url text,
  version text not null default '1.0',
  status text not null default 'DRAFT',
  owner_department text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint form_library_type_check check (form_type in ('FORM','REGISTER','REPORT','CHECKLIST','GUIDE')),
  constraint form_library_status_check check (status in ('DRAFT','PUBLISHED','ARCHIVED'))
);
create table if not exists public.job_description_forms (
  job_description_id uuid not null references public.job_descriptions(id) on delete cascade,
  form_id uuid not null references public.form_library(id) on delete cascade,
  usage_note text,
  display_order integer not null default 0,
  primary key(job_description_id,form_id)
);
alter table public.form_library enable row level security;
alter table public.job_description_forms enable row level security;
revoke all on table public.form_library,public.job_description_forms from public,anon;
grant select,insert,update,delete on table public.form_library,public.job_description_forms to authenticated;
drop policy if exists form_library_select_policy on public.form_library;
drop policy if exists form_library_admin_insert on public.form_library;
drop policy if exists form_library_admin_update on public.form_library;
drop policy if exists form_library_admin_delete on public.form_library;
drop policy if exists job_description_forms_select_policy on public.job_description_forms;
drop policy if exists job_description_forms_admin_insert on public.job_description_forms;
drop policy if exists job_description_forms_admin_update on public.job_description_forms;
drop policy if exists job_description_forms_admin_delete on public.job_description_forms;
create policy form_library_select_policy on public.form_library for select to authenticated using (status='PUBLISHED' or private.job_library_role()='admin');
create policy form_library_admin_insert on public.form_library for insert to authenticated with check (private.job_library_role()='admin' and created_by=(select auth.uid()) and updated_by=(select auth.uid()));
create policy form_library_admin_update on public.form_library for update to authenticated using (private.job_library_role()='admin') with check (private.job_library_role()='admin');
create policy form_library_admin_delete on public.form_library for delete to authenticated using (private.job_library_role()='admin');
create policy job_description_forms_select_policy on public.job_description_forms for select to authenticated using (exists(select 1 from public.job_descriptions j where j.id=job_description_id));
create policy job_description_forms_admin_insert on public.job_description_forms for insert to authenticated with check (private.job_library_role()='admin');
create policy job_description_forms_admin_update on public.job_description_forms for update to authenticated using (private.job_library_role()='admin') with check (private.job_library_role()='admin');
create policy job_description_forms_admin_delete on public.job_description_forms for delete to authenticated using (private.job_library_role()='admin');

comment on table public.job_description_change_requests is 'Item-level manager proposals reviewed by administrators without mutating the master or published snapshot.';
comment on table public.form_library is 'Central versioned directory of reusable forms, registers, reports, checklists and guides.';
commit;
