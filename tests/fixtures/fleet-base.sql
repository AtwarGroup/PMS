-- Isolated PostgreSQL fixture. No Auth API, production credentials, emails or real employee data.
-- The HR/access migrations themselves are loaded unchanged by fleet-test-db.mjs.
create role anon;create role authenticated;create role service_role bypassrls;
create schema auth;create schema private;
grant usage on schema private,auth to authenticated;
create function auth.uid()returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create table public.profiles(id uuid primary key,full_name text not null,email text not null,role text not null default 'employee',active boolean not null default true,status text not null default 'active',permissions text[] default '{}',employee_code text,department text,job_title text,join_date date,manager_id uuid,employment_type text,updated_at timestamptz default now());
alter table public.profiles enable row level security;
create table auth.users(id uuid primary key,email text);
create table public.employee_job_assignments(profile_id uuid primary key,job_description_id uuid);
create table public.job_descriptions(id uuid primary key default gen_random_uuid(),job_code text,title text,status text,department text);
create table public.admin_audit_log(id bigint generated always as identity primary key,actor_id uuid,actor_name_snapshot text,action text,target_id text,detail jsonb);
create function private.current_user_is_active()returns boolean language sql stable security definer set search_path=pg_catalog,public as $$select exists(select 1 from public.profiles p where p.id=auth.uid()and p.active=true and p.status='active')$$;
create function private.is_admin()returns boolean language sql stable security definer set search_path=pg_catalog,public as $$select exists(select 1 from public.profiles p where p.id=auth.uid()and p.active=true and p.status='active'and p.role='admin')$$;
create function private.current_user_role()returns text language sql stable security definer set search_path=pg_catalog,public as $$select p.role from public.profiles p where p.id=auth.uid()and p.active=true and p.status='active'limit 1$$;

create table public.notifications(id uuid primary key default gen_random_uuid(),recipient_id uuid not null references public.profiles(id),type text not null,title text not null,message text,created_at timestamptz not null default now(),read_at timestamptz);
alter table public.notifications enable row level security;

-- Match production: the service role does not execute the authenticated-only admin helper.
revoke all on function private.is_admin()from public;
grant execute on function private.is_admin()to authenticated;
