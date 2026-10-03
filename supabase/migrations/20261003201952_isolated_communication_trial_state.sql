create table private.communication_trial_state(singleton boolean primary key default true check(singleton),version bigint not null default 0,state jsonb not null default '{}',updated_at timestamptz not null default now(),check(octet_length(state::text)<=33554432));
alter table private.communication_trial_state enable row level security;
revoke all on private.communication_trial_state from public,anon,authenticated;
insert into private.communication_trial_state(singleton) values(true);
create function private.communication_trial_actor(p_actor uuid) returns boolean language sql stable security definer set search_path='' as $f$
 select exists(select 1 from private.communication_trial_control where singleton and enabled)
 and exists(select 1 from private.communication_trial_access a join public.profiles p on p.id=a.user_id where a.user_id=p_actor and p.active is true and p.status='active')
$f$;
revoke all on function private.communication_trial_actor(uuid) from public,anon,authenticated;
create function public.communication_trial_load(p_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $f$
declare v jsonb; begin
 if not private.communication_trial_actor(p_actor) then raise exception 'التجربة مغلقة أو الحساب غير متاح';end if;
 select jsonb_build_object('version',s.version,'state',s.state,'users',(select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'role',p.role,'department',coalesce(p.department,''),'manager',case when exists(select 1 from private.communication_trial_access a2 where a2.user_id=p.manager_id) then p.manager_id else null end)) from private.communication_trial_access a join public.profiles p on p.id=a.user_id where p.active is true and p.status='active')) into v from private.communication_trial_state s where singleton;
 return v;end $f$;
create function public.communication_trial_save(p_actor uuid,p_version bigint,p_state jsonb) returns boolean language plpgsql security definer set search_path='' as $f$
begin
 if not private.communication_trial_actor(p_actor) then raise exception 'التجربة مغلقة أو الحساب غير متاح';end if;
 if p_state is null or jsonb_typeof(p_state)<>'object' then raise exception 'حالة غير صحيحة';end if;
 update private.communication_trial_state set state=p_state,version=version+1,updated_at=now() where singleton and version=p_version;
 return found;end $f$;
revoke all on function public.communication_trial_load(uuid),public.communication_trial_save(uuid,bigint,jsonb) from public,anon,authenticated;
grant execute on function public.communication_trial_load(uuid),public.communication_trial_save(uuid,bigint,jsonb) to service_role;
