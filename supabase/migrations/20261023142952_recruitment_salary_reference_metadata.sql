-- Salary values are imported privately from approved Site source ec77eba804232fcaca16c38f63e9894a98623e65.
-- No compensation amounts or candidate information are committed to the public repository.
-- Extend the existing direct-grant command, preserving tasks, employee data and fleet permissions.
alter function private.access_direct_save(uuid,jsonb)rename to access_direct_save_before_recruitment;
create function private.access_direct_save(p_profile uuid,p_rules jsonb)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare prior jsonb;legacy jsonb;begin
 if not private.is_admin()then raise exception 'Administrator access required'using errcode='42501';end if;
 if p_rules is null or jsonb_typeof(p_rules)<>'array'then raise exception 'Invalid grants';end if;
 if exists(select 1 from jsonb_to_recordset(p_rules)x(permission text,scope text)left join private.access_catalog c on c.key=x.permission where c.key is null or x.scope is null or not x.scope=any(c.scopes))then raise exception 'Invalid permission or scope';end if;
 select coalesce(jsonb_agg(value),'[]')into legacy from jsonb_array_elements(p_rules)where value->>'permission'not like 'recruitment.%';
 perform private.access_direct_save_before_recruitment(p_profile,legacy);
 select to_jsonb(d)into prior from private.access_direct_tasks d where profile_id=p_profile for update;
 update private.access_direct_tasks set permissions=array(select k from unnest(permissions)k where k not like 'recruitment.%')||array(select distinct value->>'permission'from jsonb_array_elements(p_rules)where value->>'permission'like 'recruitment.%')where profile_id=p_profile;
 perform private.access_rebuild_tasks(p_profile);perform private.access_log('DIRECT_RECRUITMENT_GRANT',p_profile::text,prior,(select to_jsonb(d)from private.access_direct_tasks d where profile_id=p_profile));end$$;
revoke all on function private.access_direct_save_before_recruitment(uuid,jsonb)from public,anon,authenticated;
revoke all on function private.access_direct_save(uuid,jsonb)from public,anon;
grant execute on function private.access_direct_save(uuid,jsonb)to authenticated;
