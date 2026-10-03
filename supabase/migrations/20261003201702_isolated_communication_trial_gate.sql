create table private.communication_trial_control (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 updated_at timestamptz not null default now()
);
create table private.communication_trial_access (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 added_at timestamptz not null default now()
);
alter table private.communication_trial_control enable row level security;
alter table private.communication_trial_access enable row level security;
revoke all on private.communication_trial_control,private.communication_trial_access from public,anon,authenticated;
insert into private.communication_trial_control(singleton,enabled) values(true,false);
insert into private.communication_trial_access(user_id)
select id from public.profiles
where email in ('e2e-admin@atwargroup.test','e2e-manager@atwargroup.test','e2e-employee@atwargroup.test')
and active is true and status='active';
create function private.communication_trial_allowed() returns boolean
language sql stable security definer set search_path=''
as $function$
 select auth.uid() is not null
 and exists(select 1 from private.communication_trial_control where singleton and enabled)
 and exists(select 1 from private.communication_trial_access a join public.profiles p on p.id=a.user_id where a.user_id=auth.uid() and p.active is true and p.status='active')
$function$;
revoke all on function private.communication_trial_allowed() from public,anon,authenticated;
create function public.communication_trial_status() returns boolean
language sql stable security definer set search_path=''
as $function$ select private.communication_trial_allowed() $function$;
revoke all on function public.communication_trial_status() from public,anon;
grant execute on function public.communication_trial_status() to authenticated;
comment on function public.communication_trial_status() is 'Isolated communication trial gate; default off; never grants task or project access.';
