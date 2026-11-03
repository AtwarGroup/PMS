-- Supervisor identity comes from the employee manager link and existing access grants.
create function private.fleet_supervised_owner() returns uuid
language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare owner_id uuid; employee uuid;
begin
 if not private.current_user_is_active() or not private.module_allowed('fleet') then return null;end if;
 begin owner_id:=private.fleet_owner();exception when raise_exception then return null;end;
 select e.id into employee from private.hr_employees e join private.hr_employees m on m.id=e.manager_id
 where e.profile_id=owner_id and m.profile_id=auth.uid();
 if employee is not null and private.fleet_has('fleet.requests.read',employee) then return owner_id;end if;
 return null;
end $$;
create function private.fleet_request_queue_for(r private.fleet_requests,p_actor uuid) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select p_actor is not null and (r.state in('closed','rejected')
 or exists(select 1 from private.hr_employees e where e.id=r.driver_id and e.profile_id=p_actor)
 or p_actor=any(private.fleet_request_responsibles(r))
 or (r.state in('draft','returned') and coalesce((select e.actor_id=p_actor from private.fleet_events e where e.request_id=r.id and e.action='draft_saved' order by e.id limit 1),false)))
$$;
create function private.fleet_handover_queue_for(h private.fleet_handovers,p_actor uuid) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select p_actor is not null and (h.state in('accepted','cancelled')
 or exists(select 1 from private.hr_employees e where e.id=h.employee_id and e.profile_id=p_actor)
 or (h.state='draft' and h.created_by=p_actor)
 or (h.state='pending_sender' and exists(select 1 from private.hr_employees e where e.id=h.deliverer_id and e.profile_id=p_actor))
 or (h.state in('fleet_review','disputed') and p_actor=private.fleet_owner()
 and not exists(select 1 from private.hr_employees e where e.profile_id=p_actor and e.id in(h.employee_id,h.deliverer_id))))
$$;
create or replace function private.fleet_visible(r private.fleet_requests) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.current_user_is_active() and private.module_allowed('fleet') and (
 private.is_admin() or private.fleet_request_queue_for(r,private.fleet_supervised_owner()) or (
 (r.state<>'draft'
  or exists(select 1 from private.hr_employees e where e.id=r.driver_id and e.profile_id=auth.uid())
  or coalesce((select e.actor_id=auth.uid() from private.fleet_events e where e.request_id=r.id and e.action='draft_saved' order by e.id limit 1),false))
 and case when private.fleet_finance_only() then
  exists(select 1 from private.hr_employees e where e.id=r.driver_id and e.profile_id=auth.uid())
  or (r.accountant_id=auth.uid() and private.fleet_has('fleet.finance'))
 else exists(select 1 from private.hr_employees e where e.id=r.driver_id and e.profile_id=auth.uid())
  or private.fleet_can_request_for(r.driver_id) or coalesce(r.manager_id=auth.uid(),false)
  or (r.accountant_id=auth.uid() and private.fleet_has('fleet.finance'))
  or private.fleet_has('fleet.approve') or private.fleet_has('fleet.requests.read',r.driver_id)
 end))
$$;
create or replace function private.fleet_handover_visible(h private.fleet_handovers) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.current_user_is_active() and private.module_allowed('fleet') and (
 private.is_admin() or private.fleet_handover_queue_for(h,private.fleet_supervised_owner())
 or private.fleet_handover_visible_legacy(h)
 or (h.workflow_version=2 and exists(select 1 from private.hr_employees e where e.profile_id=auth.uid() and (e.id=h.employee_id or (e.id=h.deliverer_id and h.state<>'draft')))))
$$;
create or replace function private.fleet_request_listed(r private.fleet_requests) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.fleet_visible(r) and (private.is_admin()
 or private.fleet_request_queue_for(r,auth.uid()) or private.fleet_request_queue_for(r,private.fleet_supervised_owner()))
$$;
create or replace function private.fleet_handover_listed(h private.fleet_handovers) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.fleet_handover_visible(h) and (private.is_admin()
 or private.fleet_handover_queue_for(h,auth.uid()) or private.fleet_handover_queue_for(h,private.fleet_supervised_owner()))
$$;
revoke all on function private.fleet_supervised_owner(),private.fleet_request_queue_for(private.fleet_requests,uuid),private.fleet_handover_queue_for(private.fleet_handovers,uuid),private.fleet_visible(private.fleet_requests),private.fleet_handover_visible(private.fleet_handovers),private.fleet_request_listed(private.fleet_requests),private.fleet_handover_listed(private.fleet_handovers) from public,anon,authenticated;

do $patch$
declare definition text; needle text;
begin
 select pg_get_functiondef('private.fleet_snapshot_before_operations()'::regprocedure) into definition;
 needle:=$old$'finance_only',private.fleet_finance_only(),$old$;
 if strpos(definition,needle)=0 then raise exception 'Fleet snapshot flags differ';end if;
 execute replace(definition,needle,needle||$new$'supervised_owner_id',private.fleet_supervised_owner(),'supervised_owner_employee_id',(select id from private.hr_employees where profile_id=private.fleet_supervised_owner()),$new$);
end $patch$;
