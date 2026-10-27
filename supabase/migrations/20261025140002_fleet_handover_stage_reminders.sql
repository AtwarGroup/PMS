-- Per-stage reminders route to the actual actor in the new custody cycle.
create function private.fleet_handover_responsible(h private.fleet_handovers)returns uuid language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare recipient uuid;sender uuid;receiver uuid;
begin
 select profile_id into receiver from private.hr_employees where id=h.employee_id;select profile_id into sender from private.hr_employees where id=h.deliverer_id;
 if h.state='pending_sender'then return sender;elsif h.state in('pending_receiver','pending_driver')then return receiver;end if;
 begin recipient:=private.fleet_owner();exception when raise_exception then recipient:=null;end;
 if recipient is null or recipient in(sender,receiver)then select id into recipient from public.profiles where role='admin'and active and status='active'and id is distinct from sender and id is distinct from receiver order by id limit 1;end if;return recipient;
end$$;
revoke all on function private.fleet_handover_responsible(private.fleet_handovers)from public,anon,authenticated;
do $$declare p record;d text;begin
 for p in select oid from pg_proc where pronamespace='private'::regnamespace and proname in('process_fleet_workflow_alerts','process_fleet_workflow_alerts_before_review','fleet_operations_context_before_feedback')loop
 d:=pg_get_functiondef(p.oid);
 d:=replace(d,'state=''pending_driver''' ,'state in(''pending_driver'',''pending_sender'',''fleet_review'',''pending_receiver'')');
 d:=replace(d,'h.state=''pending_driver''' ,'h.state in(''pending_driver'',''pending_sender'',''fleet_review'',''pending_receiver'')');
 d:=replace(d,'h.submitted_at','case when h.workflow_version=2 then h.updated_at else h.submitted_at end');
 d:=replace(d,'submitted_at<=now()','(case when workflow_version=2 then updated_at else submitted_at end)<=now()');
 d:=replace(d,'select profile_id into recipient from private.hr_employees where id=h.employee_id;','recipient:=private.fleet_handover_responsible(h);');
 execute d;
 end loop;
end$$;
