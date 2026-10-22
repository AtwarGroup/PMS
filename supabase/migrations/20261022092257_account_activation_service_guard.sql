-- Do not resolve an authenticated-only helper when the trusted service role inserts a profile.
create or replace function private.guard_profile_modules()returns trigger language plpgsql security invoker set search_path=pg_catalog,public,private as $$
begin
 if tg_op='INSERT'or new.allowed_modules is distinct from old.allowed_modules then
  if current_user in('authenticated','anon')then
   if not private.is_admin()then raise exception 'Administrator access required'using errcode='42501';end if;
  end if;
  perform private.validate_module_keys(new.allowed_modules);
  new.allowed_modules:=array(select distinct k from unnest(new.allowed_modules)k order by k);
  if tg_op='UPDATE'then new.module_revision:=old.module_revision+1;end if;
 elsif tg_op='UPDATE'then new.module_revision:=old.module_revision+case when (new.role,new.active,new.status)is distinct from(old.role,old.active,old.status)then 1 else 0 end;end if;
 return new;
end$$;
