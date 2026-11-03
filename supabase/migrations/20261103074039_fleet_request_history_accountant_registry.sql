-- Read-only registry access must not turn finance-only accounts into operators.
create or replace function private.fleet_vehicle_registry_visible(p_vehicle uuid) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.current_user_is_active() and private.module_allowed('fleet') and
 (private.fleet_document_visible(p_vehicle) or
 (private.fleet_has('fleet.finance') and exists(select 1 from private.fleet_vehicles where id=p_vehicle)))
$$;
revoke all on function private.fleet_vehicle_registry_visible(uuid) from public,anon,authenticated;

DO $patch$
declare definition text; old_check text; new_check text;
begin
 select pg_get_functiondef('private.fleet_snapshot_before_operations()'::regprocedure) into definition;
 old_check := $old$where private.fleet_can_request_for(v.driver_id) or manage or approve or private.fleet_has('fleet.vehicles.read')$old$;
 new_check := $new$where private.fleet_vehicle_registry_visible(v.id)$new$;
 if strpos(definition,old_check)=0 then raise exception 'Fleet snapshot vehicle guard differs'; end if;
 definition := replace(definition,old_check,new_check);
 -- Documents keep their original permission boundary despite the wider registry.
 old_check := $old$'can_view_documents',manage or approve or private.fleet_has('fleet.vehicles.read')or jsonb_array_length(result->'vehicles')>0$old$;
 new_check := $new$'can_view_documents',manage or approve or private.fleet_has('fleet.vehicles.read')or exists(select 1 from private.fleet_vehicles v where private.fleet_document_visible(v.id))$new$;
 if strpos(definition,old_check)=0 then raise exception 'Fleet document navigation guard differs'; end if;
 definition := replace(definition,old_check,new_check);
 execute definition;

 select pg_get_functiondef('private.fleet_vehicle_profile(uuid)'::regprocedure) into definition;
 old_check := 'if not private.fleet_document_visible(v.id)then';
 if strpos(definition,old_check)=0 then raise exception 'Fleet vehicle profile guard differs'; end if;
 definition := replace(definition,old_check,'if not private.fleet_vehicle_registry_visible(v.id)then');
 old_check := $old$where d.vehicle_id=v.id and(d.kind<>'authorization'or d.authorized_driver_id=v.driver_id)$old$;
 new_check := $new$where d.vehicle_id=v.id and private.fleet_document_visible(v.id) and(d.kind<>'authorization'or d.authorized_driver_id=v.driver_id)$new$;
 if strpos(definition,old_check)=0 then raise exception 'Fleet vehicle profile document guard differs'; end if;
 execute replace(definition,old_check,new_check);

 -- The request visibility check above this aggregate remains mandatory.
 select pg_get_functiondef('private.fleet_detail_before_operations(uuid)'::regprocedure) into definition;
 old_check := 'where e.request_id=p_id and private.is_admin()';
 if strpos(definition,old_check)=0 then raise exception 'Fleet request history guard differs'; end if;
 execute replace(definition,old_check,'where e.request_id=p_id');
end $patch$;

-- Unsent drafts belong to their employee/creator; assignment does not publish them.
do $patch$
declare definition text; old_check text;
begin
 select pg_get_functiondef('private.fleet_visible(private.fleet_requests)'::regprocedure) into definition;
 old_check := 'private.current_user_is_active() and private.module_allowed(''fleet'') and case';
 if strpos(definition,old_check)=0 then raise exception 'Fleet request visibility guard differs'; end if;
 execute replace(definition,old_check,$new$private.current_user_is_active() and private.module_allowed('fleet') and
 (r.state<>'draft' or private.is_admin()
  or exists(select 1 from private.hr_employees e where e.id=r.driver_id and e.profile_id=auth.uid())
  or coalesce((select e.actor_id=auth.uid() from private.fleet_events e where e.request_id=r.id and e.action='draft_saved' order by e.id limit 1),false))
 and case$new$);
end $patch$;

-- Listing is a work queue, separate from authorized historical detail access.
-- Keep detail access stable so a successful transition can return its result.
create function private.fleet_request_listed(r private.fleet_requests) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.fleet_visible(r) and (
 r.state in('closed','rejected')
 or exists(select 1 from private.hr_employees e where e.id=r.driver_id and e.profile_id=auth.uid())
 or auth.uid()=any(private.fleet_request_responsibles(r))
 or (r.state in('draft','returned') and coalesce((select e.actor_id=auth.uid() from private.fleet_events e where e.request_id=r.id and e.action='draft_saved' order by e.id limit 1),false)))
$$;
create function private.fleet_handover_listed(h private.fleet_handovers) returns boolean
language sql stable security definer set search_path=pg_catalog,private,public as $$
 select private.fleet_handover_visible(h) and (
 h.state in('accepted','cancelled')
 or exists(select 1 from private.hr_employees e where e.id=h.employee_id and e.profile_id=auth.uid())
 or (h.state='draft' and h.created_by=auth.uid())
 or (h.state='pending_sender' and exists(select 1 from private.hr_employees e where e.id=h.deliverer_id and e.profile_id=auth.uid()))
 or (h.state in('fleet_review','disputed') and (private.is_admin() or auth.uid()=private.fleet_owner())
 and not exists(select 1 from private.hr_employees e where e.profile_id=auth.uid() and e.id in(h.employee_id,h.deliverer_id))))
$$;
revoke all on function private.fleet_request_listed(private.fleet_requests),private.fleet_handover_listed(private.fleet_handovers) from public,anon,authenticated;

do $patch$
declare signature text; definition text;
begin
 foreach signature in array array['private.fleet_snapshot_before_operations()','private.fleet_vehicle_profile(uuid)','private.fleet_operations_context_before_feedback()'] loop
  select pg_get_functiondef(signature::regprocedure) into definition;
  if strpos(definition,'private.fleet_visible(r)')=0 then raise exception 'Fleet request listing guard differs: %',signature; end if;
  definition:=replace(definition,'private.fleet_visible(r)','private.fleet_request_listed(r)');
  if signature<>'private.fleet_snapshot_before_operations()' then
   if strpos(definition,'private.fleet_handover_visible(h)')=0 then raise exception 'Fleet handover listing guard differs: %',signature; end if;
   definition:=replace(definition,'private.fleet_handover_visible(h)','private.fleet_handover_listed(h)');
  end if;
  execute definition;
 end loop;
end $patch$;
