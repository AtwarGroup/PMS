-- Integrate fleet with the account unit selection introduced on main (#122).
update private.app_modules set ready=true where key='fleet';
do $guard$
declare f record;d text;hdr text;body text;
begin
 for f in select p.*,l.lanname,n.nspname,pg_get_function_result(p.oid)result
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
 where n.nspname in('public','private')and p.proname like 'fleet_%'
 and has_function_privilege('authenticated',p.oid,'execute')loop
  d:=pg_get_functiondef(f.oid);hdr:=split_part(d,'AS $function$',1);
  if f.lanname='plpgsql'then
   body:='BEGIN PERFORM private.require_module(''fleet''); '||regexp_replace(f.prosrc,'[;\s]+$','','g')||'; END';
  elsif f.lanname='sql'and not f.proretset then
   hdr:=replace(hdr,'LANGUAGE sql','LANGUAGE plpgsql');
   if f.result='void'then
    body:='BEGIN PERFORM private.require_module(''fleet''); PERFORM * FROM ('||regexp_replace(f.prosrc,'[;\s]+$','','g')||') module_result; RETURN; END';
   else
    body:='BEGIN PERFORM private.require_module(''fleet''); RETURN ('||regexp_replace(f.prosrc,'[;\s]+$','','g')||'); END';
   end if;
  else raise exception 'Unsupported fleet entry point: %',f.proname;
  end if;
  execute hdr||'AS $function$'||body||'$function$';
 end loop;
end$guard$;
-- A revoked owner must not keep blocking selection of the active replacement.
create or replace function private.fleet_owner()returns uuid language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare ids uuid[];
begin
 select array_agg(p.id)into ids from public.profiles p where p.active and p.status='active'
 and(p.role='admin'or'fleet'=any(p.allowed_modules))and(
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.approve'=any(d.permissions))
 or exists(select 1 from private.access_assignments a join private.access_roles r on r.id=a.role_id and r.active join private.access_role_rules g on g.role_id=r.id where a.profile_id=p.id and g.permission='fleet.approve'));
 if cardinality(ids)is distinct from 1 then raise exception 'يجب تعيين مسؤول أسطول واحد نشط من الحسابات والصلاحيات';end if;return ids[1];
end$$;
-- Notification rows follow the same unit boundary immediately after revocation.
create policy fleet_module_boundary on public.notifications as restrictive to authenticated
using(fleet_vehicle_id is null or private.module_allowed('fleet'));
