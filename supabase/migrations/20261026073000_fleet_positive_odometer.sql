-- Require a real, positive maintenance reading; retain historical rows unchanged.
create function private.fleet_positive_request_odometer() returns trigger
language plpgsql security invoker set search_path=pg_catalog,private as $$
begin
 if new.workflow_version=2 and (new.odometer is null or new.odometer<=0) then
  raise exception 'أدخل قراءة العداد الحالية، ويجب أن تكون أكبر من صفر';
 end if;
 return new;
end$$;
revoke all on function private.fleet_positive_request_odometer() from public,anon,authenticated;
create trigger fleet_positive_request_odometer before insert or update of odometer on private.fleet_requests
for each row execute function private.fleet_positive_request_odometer();
