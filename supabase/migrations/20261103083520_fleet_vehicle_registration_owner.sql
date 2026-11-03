-- Optional for existing records; identifiers remain text to preserve leading zeros.
alter table private.fleet_vehicles
 add column registration_number text check(registration_number is null or registration_number ~ '^[0-9]{1,30}$'),
 add column owner_identity_number text check(owner_identity_number is null or owner_identity_number ~ '^[0-9]{1,30}$');

do $patch$
declare definition text;needle text;replacement text;
begin
 select pg_get_functiondef('private.fleet_vehicle_save_before_operations(uuid,integer,jsonb,text)'::regprocedure) into definition;
 needle:='insert into private.fleet_vehicles(id,plate,vin,vehicle_type,model,city,driver_id,active,odometer)';
 if strpos(definition,needle)=0 then raise exception 'Fleet vehicle insert columns differ';end if;
 definition:=replace(definition,needle,'insert into private.fleet_vehicles(id,plate,vin,vehicle_type,model,city,driver_id,active,odometer,registration_number,owner_identity_number)');
 needle:=$old$coalesce((p_data->>'odometer')::integer,0))$old$;
 replacement:=$new$coalesce((p_data->>'odometer')::integer,0),nullif(translate(btrim(p_data->>'registration_number'),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),''),nullif(translate(btrim(p_data->>'owner_identity_number'),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),''))$new$;
 if strpos(definition,needle)=0 then raise exception 'Fleet vehicle insert values differ';end if;
 definition:=replace(definition,needle,replacement);
 needle:='city=excluded.city,driver_id=excluded.driver_id';
 replacement:=$new$city=excluded.city,registration_number=case when p_data ? 'registration_number' then excluded.registration_number else private.fleet_vehicles.registration_number end,owner_identity_number=case when p_data ? 'owner_identity_number' then excluded.owner_identity_number else private.fleet_vehicles.owner_identity_number end,driver_id=excluded.driver_id$new$;
 if strpos(definition,needle)=0 then raise exception 'Fleet vehicle update differs';end if;
 execute replace(definition,needle,replacement);
end $patch$;
