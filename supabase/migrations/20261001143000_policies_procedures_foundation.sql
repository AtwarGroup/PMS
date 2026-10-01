begin;
create table public.policies (
 id uuid primary key default gen_random_uuid(),
 policy_no text not null unique,
 title text not null,
 category text not null,
 policy_type text not null default 'POLICY' check (policy_type in ('POLICY','PROCEDURE')),
 version integer not null default 1 check (version>0),
 status text not null default 'DRAFT' check (status in ('DRAFT','REVIEW','APPROVAL','FINAL_APPROVAL','PUBLISHED','RETURNED','ARCHIVED')),
 content text not null default '',
 owner_department text,
 effective_date date,
 next_review_date date,
 creator_id uuid not null default auth.uid() references public.profiles(id),
 reviewer_id uuid references public.profiles(id),
 approver_id uuid references public.profiles(id),
 final_approver_id uuid references public.profiles(id),
 published_by uuid references public.profiles(id),
 published_at timestamptz,
 acknowledgement_required boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.policy_audiences (
 id bigint generated always as identity primary key,
 policy_id uuid not null references public.policies(id) on delete cascade,
 audience_type text not null check (audience_type in ('ALL','MANAGERS','EMPLOYEES','DEPARTMENT','USER')),
 audience_value text,
 unique(policy_id,audience_type,audience_value)
);
create table public.policy_actions (
 id bigint generated always as identity primary key,
 policy_id uuid not null references public.policies(id) on delete cascade,
 actor_id uuid not null default auth.uid() references public.profiles(id),
 action text not null,
 from_status text,
 to_status text,
 note text,
 created_at timestamptz not null default now()
);
create table public.policy_acknowledgements (
 policy_id uuid not null references public.policies(id) on delete cascade,
 profile_id uuid not null references public.profiles(id) on delete cascade,
 acknowledged_at timestamptz not null default now(),
 primary key(policy_id,profile_id)
);
alter table public.policies enable row level security;
alter table public.policy_audiences enable row level security;
alter table public.policy_actions enable row level security;
alter table public.policy_acknowledgements enable row level security;
grant select,insert,update on public.policies to authenticated;
grant select,insert,update,delete on public.policy_audiences to authenticated;
grant select,insert on public.policy_actions to authenticated;
grant select,insert on public.policy_acknowledgements to authenticated;
grant usage,select on sequence public.policy_audiences_id_seq,public.policy_actions_id_seq to authenticated;

create or replace function private.can_view_policy(p public.policies)
returns boolean language sql stable security definer set search_path='pg_catalog','public','private' as $$
 select p.creator_id=auth.uid() or p.reviewer_id=auth.uid() or p.approver_id=auth.uid() or p.final_approver_id=auth.uid()
 or private.is_admin()
 or (p.status='PUBLISHED' and exists(
   select 1 from public.policy_audiences a join public.profiles me on me.id=auth.uid()
   where a.policy_id=p.id and (
    a.audience_type='ALL' or
    (a.audience_type='MANAGERS' and me.role in ('manager','admin')) or
    (a.audience_type='EMPLOYEES' and me.role='employee') or
    (a.audience_type='DEPARTMENT' and a.audience_value=me.department) or
    (a.audience_type='USER' and a.audience_value=me.id::text)
   )
 ))
$$;
revoke all on function private.can_view_policy(public.policies) from public,anon;
grant execute on function private.can_view_policy(public.policies) to authenticated;

create policy policies_select on public.policies for select to authenticated using(private.can_view_policy(policies));
create policy policies_insert on public.policies for insert to authenticated with check(creator_id=auth.uid() or private.is_admin());
create policy policies_update on public.policies for update to authenticated
 using(creator_id=auth.uid() or reviewer_id=auth.uid() or approver_id=auth.uid() or final_approver_id=auth.uid() or private.is_admin())
 with check(creator_id=creator_id);
create policy policy_audiences_select on public.policy_audiences for select to authenticated
 using(exists(select 1 from public.policies p where p.id=policy_id and private.can_view_policy(p)));
create policy policy_audiences_manage on public.policy_audiences for all to authenticated
 using(exists(select 1 from public.policies p where p.id=policy_id and (p.creator_id=auth.uid() or p.final_approver_id=auth.uid() or private.is_admin())))
 with check(exists(select 1 from public.policies p where p.id=policy_id and (p.creator_id=auth.uid() or p.final_approver_id=auth.uid() or private.is_admin())));
create policy policy_actions_select on public.policy_actions for select to authenticated
 using(exists(select 1 from public.policies p where p.id=policy_id and private.can_view_policy(p)));
create policy policy_actions_insert on public.policy_actions for insert to authenticated with check(actor_id=auth.uid());
create policy policy_ack_select on public.policy_acknowledgements for select to authenticated
 using(profile_id=auth.uid() or private.is_admin() or exists(select 1 from public.policies p where p.id=policy_id and p.creator_id=auth.uid()));
create policy policy_ack_insert on public.policy_acknowledgements for insert to authenticated with check(profile_id=auth.uid());

create index policies_status_idx on public.policies(status);
create index policies_category_idx on public.policies(category);
create index policies_review_date_idx on public.policies(next_review_date);
create index policy_audiences_policy_idx on public.policy_audiences(policy_id);
create index policy_actions_policy_idx on public.policy_actions(policy_id,created_at desc);
commit;