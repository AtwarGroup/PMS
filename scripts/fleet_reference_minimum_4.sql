-- Restrict new financial references in both workflow versions without modifying historical payments.
do $migration$
declare definition text; before text := $$if length(btrim(coalesce(p_data->>'reference','')))<10 then raise exception 'مرجع العملية 10 أحرف على الأقل';end if;$$; after text := $$if length(btrim(coalesce(p_data->>'reference','')))<4 then raise exception 'مرجع العملية 4 أحرف على الأقل';end if;$$;
begin
 select pg_get_functiondef('private.fleet_command(uuid,integer,text,jsonb)'::regprocedure) into definition;
 if position(before in definition)=0 then raise exception 'Fleet command reference validation differs from expected; no changes applied';end if;
 execute replace(definition,before,after);
end $migration$;
create or replace function private.fleet_check_payment_reference() returns trigger language plpgsql security invoker set search_path=pg_catalog as $guard$
begin
 if length(btrim(coalesce(new.reference,'')))<4 then raise exception 'مرجع العملية 4 أحرف على الأقل';end if;
 return new;
end $guard$;
revoke all on function private.fleet_check_payment_reference() from public,anon,authenticated;
create trigger fleet_payment_reference_minimum before insert or update of reference on private.fleet_payments for each row execute function private.fleet_check_payment_reference();
