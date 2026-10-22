-- An administrator's full access must not displace the operational fleet owner.
create or replace function private.fleet_owner()returns uuid language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare ids uuid[];
begin
 select coalesce(array_agg(p.id)filter(where p.role<>'admin'),array_agg(p.id))into ids
 from public.profiles p where p.active and p.status='active'
 and(p.role='admin'or'fleet'=any(p.allowed_modules))and(
 exists(select 1 from private.access_direct_tasks d where d.profile_id=p.id and 'fleet.approve'=any(d.permissions))
 or exists(select 1 from private.access_assignments a join private.access_roles r on r.id=a.role_id and r.active join private.access_role_rules g on g.role_id=r.id where a.profile_id=p.id and g.permission='fleet.approve'));
 if cardinality(ids)is distinct from 1 then raise exception 'يجب تعيين مسؤول أسطول واحد نشط من الحسابات والصلاحيات';end if;
 return ids[1];
end$$;
